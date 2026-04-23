import Foundation
import AVFoundation

@Observable
final class RealtimeSession: NSObject, URLSessionWebSocketDelegate {
    // Observable state
    var isConnected = false
    var voiceState: VoiceState = .idle
    var liveCaption: String = ""
    var errorMessage: String?
    var pendingDrawBlock: DrawBlock?
    var drawTick: Int = 0

    // Private
    private var socket: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var converter: AVAudioConverter?
    private var isEngineGraphBuilt = false
    private let sampleRate: Double = 24_000

    private var isTalking = false
    private var bytesAppendedThisTurn = 0
    private var isAssistantResponding = false
    private var pendingCallName: String?
    private var pendingCallId: String?
    private var transcriptBuffer = ""
    @ObservationIgnored private var pendingStartContinuation: CheckedContinuation<Void, Never>?

    // MARK: - Init

    override init() {
        super.init()
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }

    // MARK: - Public

    func connect() async {
        guard let key = Keychain.read("openai"), !key.isEmpty else {
            await MainActor.run { errorMessage = "Add your OpenAI API key in Settings." }
            return
        }

        let micOK = await AVAudioApplication.requestRecordPermission()
        guard micOK else {
            await MainActor.run { errorMessage = "Microphone access denied." }
            return
        }

        do { try setupAudio() } catch {
            await MainActor.run { errorMessage = "Audio setup failed: \(error.localizedDescription)" }
            return
        }

        var req = URLRequest(url: URL(string: "wss://api.openai.com/v1/realtime?model=gpt-realtime")!)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        socket = urlSession.webSocketTask(with: req)
        socket?.resume()
        receive()
    }

    func disconnect() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        if engine.isRunning { engine.stop() }
        isConnected = false
        voiceState = .idle
    }

    func startTalking() {
        guard isConnected else { return }
        Task { @MainActor in
            if isAssistantResponding {
                player.stop()
                send(["type": "response.cancel"])
                // Wait up to 800ms for server to confirm cancellation via response.done
                await withCheckedContinuation { cont in
                    self.pendingStartContinuation = cont
                    Task {
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        if let c = self.pendingStartContinuation {
                            self.pendingStartContinuation = nil
                            c.resume()
                        }
                    }
                }
            }
            if !engine.isRunning {
                print("[Audio] engine not running when startTalking called — restarting")
                do { try engine.start() } catch {
                    print("[Audio] engine restart FAILED: \(error)")
                    self.errorMessage = "Mic not ready — try again"
                    return
                }
            }
            bytesAppendedThisTurn = 0
            isTalking = true
            voiceState = .listening
            print("[Audio] push-to-talk START")
        }
    }

    func stopTalking() {
        guard isTalking else { return }
        isTalking = false
        voiceState = .idle
        print("[Audio] STOP called — bytesAppendedThisTurn=\(bytesAppendedThisTurn), isTalking=\(isTalking)")
        let minBytes: Double = 24000 * 2 * 0.15  // 150ms at 24kHz PCM16 mono
        if Double(bytesAppendedThisTurn) < minBytes {
            print("[Audio] STOP — only \(bytesAppendedThisTurn) bytes captured, aborting (hold longer)")
            send(["type": "input_audio_buffer.clear"])
            Task { @MainActor in
                self.errorMessage = "Hold the orb a bit longer while speaking"
            }
            return
        }
        guard !isAssistantResponding else {
            print("[Audio] STOP — assistant still responding, skipping response.create")
            send(["type": "input_audio_buffer.commit"])
            return
        }
        print("[Audio] STOP — committing \(bytesAppendedThisTurn) bytes")
        send(["type": "input_audio_buffer.commit"])
        send(["type": "response.create"])
    }

    // MARK: - Audio setup

    private func setupAudio() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true, options: [.notifyOthersOnDeactivation])

        do {
            try engine.inputNode.setVoiceProcessingEnabled(true)
            print("[Audio] voice processing enabled (AEC active)")
        } catch {
            print("[Audio] AEC enable failed: \(error.localizedDescription)")
        }

        let hwFmt = engine.inputNode.outputFormat(forBus: 0)
        guard hwFmt.sampleRate > 0, hwFmt.channelCount > 0 else {
            throw NSError(domain: "Realtime", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Audio input format invalid (sampleRate=\(hwFmt.sampleRate), channels=\(hwFmt.channelCount)). Microphone may be unavailable."
            ])
        }

        let playFmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        if !isEngineGraphBuilt {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: playFmt)
            isEngineGraphBuilt = true
        }

        let monoFmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let conv = AVAudioConverter(from: hwFmt, to: monoFmt) else {
            throw NSError(domain: "Realtime", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create audio converter"])
        }
        converter = conv

        engine.inputNode.removeTap(onBus: 0)
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFmt) { [weak self] buf, _ in
            guard let self, self.isTalking, let conv = self.converter else { return }
            if buf.frameLength > 0, Int.random(in: 0..<20) == 0 {
                print("[Audio] mic buffer flowing (\(buf.frameLength) frames)")
            }
            let outCapacity = AVAudioFrameCount(Double(buf.frameLength) * self.sampleRate / hwFmt.sampleRate)
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: monoFmt, frameCapacity: outCapacity) else { return }
            var err: NSError?
            conv.convert(to: outBuf, error: &err) { _, status in status.pointee = .haveData; return buf }
            if err != nil { return }
            guard let ch = outBuf.floatChannelData?[0], outBuf.frameLength > 0 else { return }
            let n = Int(outBuf.frameLength)
            var pcm = Data(count: n * 2)
            pcm.withUnsafeMutableBytes { raw in
                let i16 = raw.bindMemory(to: Int16.self).baseAddress!
                for i in 0..<n {
                    let s = max(-1, min(1, ch[i]))
                    i16[i] = Int16(s * 32767)
                }
            }
            self.send(["type": "input_audio_buffer.append", "audio": pcm.base64EncodedString()])
            self.bytesAppendedThisTurn += pcm.count
        }

        try engine.start()
        player.play()
    }

    private func scheduleAudio(_ pcm: Data) {
        guard pcm.count >= 2 else { return }
        let frames = AVAudioFrameCount(pcm.count / 2)
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames) else { return }
        buf.frameLength = frames
        pcm.withUnsafeBytes { raw in
            let i16 = raw.bindMemory(to: Int16.self).baseAddress!
            let out = buf.floatChannelData![0]
            for i in 0..<Int(frames) { out[i] = Float(i16[i]) / 32767.0 }
        }
        player.scheduleBuffer(buf, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    // MARK: - WebSocket

    private func receive() {
        socket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                if case .string(let s) = msg { self.handle(s) }
                self.receive()
            case .failure(let e):
                Task { @MainActor in
                    self.errorMessage = "WebSocket: \(e.localizedDescription)"
                    self.isConnected = false
                }
            }
        }
    }

    private func send(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        socket?.send(.string(text)) { _ in }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        print("[WS] event: \(type)")

        switch type {
        case "session.created":
            Task { @MainActor in self.isConnected = true }
            configureSession()

        case "response.created":
            isAssistantResponding = true
            transcriptBuffer = ""
            Task { @MainActor in self.voiceState = .speaking }

        case "response.audio.delta":
            if let delta = json["delta"] as? String, let pcm = Data(base64Encoded: delta) {
                scheduleAudio(pcm)
            }

        case "response.audio_transcript.delta":
            if let d = json["delta"] as? String {
                transcriptBuffer += d
                Task { @MainActor in self.liveCaption = self.transcriptBuffer }
            }

        case "response.audio.done":
            Task { @MainActor in self.voiceState = .idle }

        case "response.output_item.added":
            if let item = json["item"] as? [String: Any],
               (item["type"] as? String) == "function_call" {
                pendingCallName = item["name"] as? String
                pendingCallId   = item["call_id"] as? String
            }

        case "response.function_call_arguments.done":
            let name   = (json["name"]    as? String) ?? pendingCallName ?? ""
            let callId = (json["call_id"] as? String) ?? pendingCallId   ?? ""
            let args   = (json["arguments"] as? String) ?? ""
            print("[Draw] function_call.done — name=\(name), argsLen=\(args.count), preview=\(String(args.prefix(200)))")
            if name == "draw_on_whiteboard" { handleDraw(args: args, callId: callId) }
            pendingCallName = nil; pendingCallId = nil

        case "response.done":
            isAssistantResponding = false
            pendingStartContinuation?.resume()
            pendingStartContinuation = nil
            Task { @MainActor in self.voiceState = .idle }

        case "session.updated":
            print("[Config] session.update ACCEPTED")

        case "error":
            if let e = json["error"] as? [String: Any], let msg = e["message"] as? String {
                print("[WS] ERROR: \(msg)")
                Task { @MainActor in self.errorMessage = msg }
            }

        default: break
        }
    }

    private func handleDraw(args: String, callId: String) {
        print("[Draw] handleDraw called, \(args.count) bytes")
        guard let data = args.data(using: .utf8) else { return }
        do {
            let block = try JSONDecoder().decode(DrawBlock.self, from: data)
            print("[Draw] decoded \(block.commands.count) commands")
            Task { @MainActor in
                self.pendingDrawBlock = block
                self.drawTick &+= 1
            }
            send([
                "type": "conversation.item.create",
                "item": [
                    "type": "function_call_output",
                    "call_id": callId,
                    "output": "{\"ok\":true}"
                ] as [String: Any]
            ])
            send(["type": "response.create"])
        } catch {
            print("[Draw] decode FAILED: \(error.localizedDescription)")
        }
    }

    // MARK: - Session configuration

    private func configureSession() {
        transcriptBuffer = ""
        Task { @MainActor in self.liveCaption = "" }

        let instructions = """
        CRITICAL: Every single response you give MUST start with a call to the draw_on_whiteboard tool. Sketch something relevant to what you're saying, even if small. If you cannot think of anything to draw, sketch a circle with a label. You MUST call the tool — no exceptions.

        You are Hoot — a warm, encouraging AI tutor. You help students one-on-one via voice.

        LANGUAGE: Reply in English only, always. Never Spanish, French, or any other language.

        STYLE: Keep replies SHORT — one or two sentences. Warm, casual, conversational. Ask quick checking questions. Invite the student to respond.

        WHITEBOARD — NON-NEGOTIABLE: You have the draw_on_whiteboard tool. CALL IT for any maths, equation, geometry, diagram, graph, or visual concept. Calling the tool IS the teaching method — drawing is not optional. If a student asks about anything mathematical or visual, you MUST call draw_on_whiteboard at the start of your response. Narrate what you're drawing as you draw it.

        Coordinates for drawing: canvas is 900 wide × 600 tall, (0,0) at top-left. Use x in 50-850 range, y in 50-550 range. Text size 20-40pt.
        """

        print("[Config] sending session.update with model=gpt-realtime (GA schema), voice=marin")
        print("[Config] instructions length=\(instructions.count)")

        send([
            "type": "session.update",
            "session": [
                "model": "gpt-realtime",
                "output_modalities": ["audio"],
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": NSNumber(value: 24000)] as [String: Any],
                        "transcription": ["model": "whisper-1", "language": "en"] as [String: Any],
                        "turn_detection": NSNull()
                    ] as [String: Any],
                    "output": [
                        "format": ["type": "audio/pcm"] as [String: Any],
                        "voice": "marin",
                        "speed": NSNumber(value: 1.0)
                    ] as [String: Any]
                ] as [String: Any],
                "instructions": instructions,
                "tools": [drawToolSchema()],
                "tool_choice": ["type": "function", "name": "draw_on_whiteboard"] as [String: Any]
            ] as [String: Any]
        ])

        send([
            "type": "response.create",
            "response": [
                "instructions": "Greet the student warmly in ONE short sentence IN ENGLISH. Ask what they'd like to learn today. English only."
            ] as [String: Any]
        ])
    }

    private func drawToolSchema() -> [String: Any] {
        [
            "type": "function",
            "name": "draw_on_whiteboard",
            "description": "Draw on the shared whiteboard. Call this whenever explaining any mathematical concept, equation, geometry, graph, diagram, or step-by-step working. Calling is REQUIRED for visual/mathematical content — never describe a drawing in words instead of calling this tool.",
            "parameters": [
                "type": "object",
                "properties": [
                    "clear": ["type": "boolean", "description": "True to clear board first. Default false."],
                    "commands": [
                        "type": "array",
                        "description": "Array of 2-8 drawing commands.",
                        "items": [
                            "type": "object",
                            "properties": [
                                "type":  ["type": "string", "enum": ["text", "line", "arrow", "circle", "rect"]],
                                "x":     ["type": "number"], "y":  ["type": "number"],
                                "x1":    ["type": "number"], "y1": ["type": "number"],
                                "x2":    ["type": "number"], "y2": ["type": "number"],
                                "cx":    ["type": "number"], "cy": ["type": "number"], "r": ["type": "number"],
                                "w":     ["type": "number"], "h":  ["type": "number"],
                                "text":  ["type": "string"],
                                "size":  ["type": "number"],
                                "color": ["type": "string", "description": "Hex color like #FF6B35"],
                                "fill":  ["type": "boolean"],
                                "width": ["type": "number"]
                            ] as [String: Any],
                            "required": ["type"]
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any],
                "required": ["commands"]
            ] as [String: Any]
        ]
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        print("[WS] opened")
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("[WS] closed code=\(closeCode.rawValue)")
        Task { @MainActor in self.isConnected = false; self.voiceState = .idle }
    }
}
