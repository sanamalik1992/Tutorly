import Foundation
import AVFoundation

// RealtimeSession connects to the OpenAI Realtime API over WebSocket.
// Audio: hardware mic (48 kHz Float32) → AVAudioConverter → 24 kHz Float32 → Int16 PCM.
// connect() is NOT called automatically — the user must tap "Connect Voice".
//
// PRODUCTION NOTE: For a shipped app, mint ephemeral tokens from a server endpoint
// instead of sending the raw API key from the device.

private let bargeInRMSThreshold: Float = 0.015   // real speech ~0.02+, echo ~0.003-0.008

@Observable
final class RealtimeSession {

    // MARK: - Observable state

    var isConnected       = false
    var isMuted           = false
    var isTutorSpeaking   = false
    var isStudentSpeaking = false
    var errorMessage: String?

    // TutorSession wires this to its own pendingDrawBlock / drawTick
    var onDraw: ((DrawBlock) -> Void)?

    // MARK: - Private

    private var socket: URLSessionWebSocketTask?
    private let urlSession = URLSession(configuration: .default)

    private let engine     = AVAudioEngine()
    private let player     = AVAudioPlayerNode()
    private var converter: AVAudioConverter?
    private var isEngineGraphBuilt = false   // engine.attach/connect are one-time ops

    private let sampleRate: Double = 24_000
    private var pendingCallName: String?
    private var pendingCallId:   String?

    // Barge-in: RMS gate + reduced cooldown
    @ObservationIgnored private var isAssistantResponding = false
    @ObservationIgnored private var lastAssistantFinishTime: Date = .distantPast
    @ObservationIgnored private var lastSpeechStartedTime: Date = .distantPast
    @ObservationIgnored private var pendingBargeInTimer: Timer?
    @ObservationIgnored private var bargeInAudioRMS: Float = 0.0
    private let bargeinCooldown: TimeInterval = 0.25

    // Mode toggle — updated by TutorSession.mode.didSet via updateMode()
    @ObservationIgnored var currentMode: TutorMode = .teach

    // MARK: - Connect / disconnect

    func connect() {
        guard !isConnected else { return }
        guard let key = Keychain.readOpenAI(), !key.isEmpty else {
            errorMessage = "Add your OpenAI API key in Settings to use voice mode."
            return
        }
        Task {
            let granted = await AVAudioApplication.requestRecordPermission()
            guard granted else {
                await MainActor.run { self.errorMessage = "Microphone access denied." }
                return
            }
            await MainActor.run {
                do {
                    try self.setupAudio()
                    self.openSocket(key: key)
                } catch {
                    self.errorMessage = "Audio setup failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func disconnect() {
        pendingBargeInTimer?.invalidate()
        pendingBargeInTimer = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        converter         = nil
        isConnected       = false
        isTutorSpeaking   = false
        isStudentSpeaking = false
    }

    func toggleMute() { isMuted.toggle() }

    func sendText(_ text: String) {
        guard isConnected else { return }
        send([
            "type": "conversation.item.create",
            "item": [
                "type": "message", "role": "user",
                "content": [["type": "input_text", "text": text]]
            ] as [String: Any]
        ])
        send(["type": "response.create"])
    }

    func updateMode(_ mode: TutorMode) {
        currentMode = mode
        guard isConnected else { return }
        print("[Session] updateMode → \(mode.rawValue), sending session.update")
        send([
            "type": "session.update",
            "session": ["instructions": buildInstructions(mode: mode)] as [String: Any]
        ])
    }

    // MARK: - WebSocket

    private func openSocket(key: String) {
        var req = URLRequest(
            url: URL(string: "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview")!)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("realtime=v1",   forHTTPHeaderField: "OpenAI-Beta")

        socket = urlSession.webSocketTask(with: req)
        socket?.resume()
        isConnected = true
        readLoop()
    }

    private func readLoop() {
        socket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                switch msg {
                case .string(let s):  self.handle(s)
                case .data(let d):
                    if let s = String(data: d, encoding: .utf8) { self.handle(s) }
                @unknown default: break
                }
                self.readLoop()
            case .failure(let err):
                Task { @MainActor in
                    self.errorMessage = err.localizedDescription
                    self.isConnected  = false
                }
            }
        }
    }

    private func send(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        socket?.send(.string(text)) { _ in }
    }

    // MARK: - Event handling

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        print("[WS] event: \(type)")

        switch type {

        case "session.created":
            configureSession()

        case "input_audio_buffer.speech_started":
            let now = Date()
            lastSpeechStartedTime = now
            print("[VAD] speech_started | assistantResponding=\(isAssistantResponding) rms=\(String(format: "%.4f", bargeInAudioRMS))")
            if isAssistantResponding {
                handleSpeechStartedDuringAssistantResponse()
            } else {
                guard now.timeIntervalSince(lastAssistantFinishTime) > bargeinCooldown else {
                    print("[VAD] ↳ dropped (cooldown \(String(format: "%.0f", now.timeIntervalSince(lastAssistantFinishTime) * 1000))ms)")
                    break
                }
                player.stop(); player.play()
                Task { @MainActor in self.isTutorSpeaking = false; self.isStudentSpeaking = true }
            }

        case "input_audio_buffer.speech_stopped":
            let elapsed = Date().timeIntervalSince(lastSpeechStartedTime) * 1_000
            if elapsed < 150 {
                print("[VAD] speech_stopped after \(String(format: "%.0f", elapsed))ms — cancelling barge-in timer (false positive)")
                pendingBargeInTimer?.invalidate()
                pendingBargeInTimer = nil
            }
            Task { @MainActor in self.isStudentSpeaking = false }

        case "response.created":
            isAssistantResponding = true
            Task { @MainActor in self.isTutorSpeaking = true }

        case "response.output_item.added":
            if let item = json["item"] as? [String: Any],
               (item["type"] as? String) == "function_call" {
                pendingCallName = item["name"]    as? String
                pendingCallId   = item["call_id"] as? String
            }

        case "response.audio.delta":
            if let delta = json["delta"] as? String,
               let pcm = Data(base64Encoded: delta) {
                scheduleAudio(pcm)
            }

        case "response.audio.done":
            lastAssistantFinishTime = Date()
            Task { @MainActor in self.isTutorSpeaking = false }

        case "response.function_call_arguments.done":
            let name   = (json["name"]    as? String) ?? pendingCallName ?? ""
            let callId = (json["call_id"] as? String) ?? pendingCallId   ?? ""
            let args   = (json["arguments"] as? String) ?? ""
            print("[Draw] function_call.done received — name=\(name), callId=\(callId), argsLen=\(args.count), argsPreview=\(String(args.prefix(200)))")
            if name == "draw_on_whiteboard" { handleDraw(args: args, callId: callId) }
            pendingCallName = nil; pendingCallId = nil

        case "response.done":
            pendingBargeInTimer?.invalidate()
            pendingBargeInTimer = nil
            isAssistantResponding = false
            Task { @MainActor in self.isTutorSpeaking = false }

        case "error":
            if let e = json["error"] as? [String: Any], let msg = e["message"] as? String {
                Task { @MainActor in self.errorMessage = msg }
            }

        default: break
        }
    }

    // MARK: - Smart barge-in

    private func handleSpeechStartedDuringAssistantResponse() {
        let rms = bargeInAudioRMS
        guard rms >= bargeInRMSThreshold else {
            print("[VAD] ↳ dropped (RMS \(String(format: "%.4f", rms)) < threshold \(bargeInRMSThreshold))")
            return
        }
        print("[VAD] ↳ RMS \(String(format: "%.4f", rms)) passes gate — scheduling barge-in (300ms)")
        pendingBargeInTimer?.invalidate()
        pendingBargeInTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                print("[VAD] ↳ barge-in confirmed — interrupting tutor")
                self.pendingBargeInTimer = nil
                self.player.stop(); self.player.play()
                self.isTutorSpeaking   = false
                self.isStudentSpeaking = true
            }
        }
    }

    private func updateBargeInRMS(buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        var sum: Float = 0
        for i in 0..<n { sum += ch[i] * ch[i] }
        bargeInAudioRMS = sqrt(sum / Float(n))
    }

    // MARK: - Draw tool

    private func handleDraw(args: String, callId: String) {
        print("[Draw] handleDraw called with \(args.count) bytes of args")
        if let d = args.data(using: .utf8) {
            do {
                let block = try JSONDecoder().decode(DrawBlock.self, from: d)
                print("[Draw] decoded \(block.commands.count) commands")
                Task { @MainActor in self.onDraw?(block) }
            } catch {
                print("[Draw] decode FAILED: \(error.localizedDescription)")
            }
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
    }

    // MARK: - Session configuration

    private func configureSession() {
        print("[Session] configuring with mode=\(currentMode.rawValue) — sending session.update")
        print("[Config] instructions length=\(buildInstructions(mode: currentMode).count) chars")
        print("[Config] instructions head: \(String(buildInstructions(mode: currentMode).prefix(300)))")
        send([
            "type": "session.update",
            "session": [
                "modalities": ["text", "audio"],
                "instructions": buildInstructions(mode: currentMode),
                "voice": "sage",
                "temperature": 0.85,
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                "input_audio_transcription": ["model": "whisper-1"],
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.65,
                    "prefix_padding_ms": 300,
                    "silence_duration_ms": 1100,
                    "create_response": true,
                    "interrupt_response": true
                ] as [String: Any],
                "tools": [drawToolSchema()],
                "tool_choice": "auto"
            ] as [String: Any]
        ])
    }

    private func buildInstructions(mode: TutorMode) -> String {
        let base = """
        You are a friendly, upbeat university teaching assistant — think smart older sibling \
        who's just finished their degree and genuinely loves explaining things. Energetic, warm, \
        uses casual phrasing ('gotcha', 'nice one', 'okay so', 'right'), asks quick checking \
        questions ('make sense?'). Never lecture-y. Keep replies SHORT — usually 1-2 sentences, \
        like real conversation. If the student is quiet or unsure, encourage them.

        CRITICAL — USE THE WHITEBOARD: You MUST call draw_on_whiteboard for EVERY explanation \
        that involves anything visual: maths steps, equations, diagrams, graphs, flow charts, \
        labelled figures, code structure, timelines. Do NOT describe drawings in words — DRAW \
        THEM. Call the tool immediately as you start explaining. Never say 'I'll draw' or \
        'let me show you' — just call draw_on_whiteboard and talk simultaneously.
        """
        switch mode {
        case .teach:
            return base + "\n\nMode: TEACH. Walk the student through concepts step-by-step. Draw each step on the whiteboard as you explain it."
        case .quiz:
            return base + "\n\nMode: QUIZ. Ask questions one at a time. After each answer, use the whiteboard to show the correct working or diagram."
        }
    }

    private func drawToolSchema() -> [String: Any] {
        [
            "type": "function",
            "name": "draw_on_whiteboard",
            "description": """
                Draw diagrams, equations, and visual aids on the student's whiteboard.
                Use for maths steps, flow charts, concept maps, labelled figures.
                Canvas is 900 wide x 600 tall, origin top-left. Colors: \
                #1E3A8A navy, #E09C1F amber, #3D9396 teal, #C0392B red.
                """,
            "parameters": [
                "type": "object",
                "properties": [
                    "clear": ["type": "boolean",
                              "description": "true to wipe the board before drawing"],
                    "commands": [
                        "type": "array",
                        "description": "Draw commands. Include 3-8 per call.",
                        "items": [
                            "type": "object",
                            "properties": [
                                "type":  ["type": "string",
                                          "enum": ["text","line","arrow","circle","rect"]],
                                "x":     ["type": "number"], "y":  ["type": "number"],
                                "text":  ["type": "string"],
                                "size":  ["type": "number"], "color": ["type": "string"],
                                "x1": ["type": "number"], "y1": ["type": "number"],
                                "x2": ["type": "number"], "y2": ["type": "number"],
                                "cx": ["type": "number"], "cy": ["type": "number"],
                                "r":  ["type": "number"],
                                "w":  ["type": "number"], "h":  ["type": "number"],
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

    // MARK: - Audio I/O

    private func setupAudio() throws {
        try AVAudioSession.sharedInstance().setCategory(
            .playAndRecord, mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetooth])
        try AVAudioSession.sharedInstance().setActive(true, options: [.notifyOthersOnDeactivation])

        // Build playback graph once — survives stop/start cycles
        let playFmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        if !isEngineGraphBuilt {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: playFmt)
            isEngineGraphBuilt = true
        }

        // Hardware input format (typically 48 kHz Float32, possibly stereo).
        // Install tap at hardware's native format to avoid "format mismatch" crash,
        // then resample to 24 kHz mono Float32 via AVAudioConverter.
        let hwFmt   = engine.inputNode.outputFormat(forBus: 0)
        let monoFmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        guard let conv = AVAudioConverter(from: hwFmt, to: monoFmt) else {
            throw NSError(domain: "RealtimeSession", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Cannot create audio converter " +
                    "(\(Int(hwFmt.sampleRate)) Hz → \(Int(sampleRate)) Hz)"
            ])
        }
        converter = conv

        engine.inputNode.removeTap(onBus: 0)
        engine.inputNode.installTap(onBus: 0, bufferSize: 4_096, format: hwFmt) { [weak self] buf, _ in
            guard let self, !self.isMuted, let conv = self.converter else { return }

            let ratio  = self.sampleRate / hwFmt.sampleRate
            let outLen = AVAudioFrameCount(Double(buf.frameLength) * ratio + 1)
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: monoFmt, frameCapacity: outLen) else { return }

            var convErr: NSError?
            conv.convert(to: outBuf, error: &convErr) { _, outStatus in
                outStatus.pointee = .haveData
                return buf
            }
            guard convErr == nil, outBuf.frameLength > 0,
                  let ch = outBuf.floatChannelData?[0] else { return }

            // Update RMS for smart barge-in detection
            self.updateBargeInRMS(buffer: outBuf)

            // Float32 → Int16 PCM16 with clamping
            let n = Int(outBuf.frameLength)
            var i16 = [Int16](repeating: 0, count: n)
            for i in 0..<n {
                let s = max(-32_767.0, min(32_767.0, ch[i] * 32_767.0))
                i16[i] = Int16(s)
            }
            let bytes = i16.withUnsafeBytes { Data($0) }
            self.send(["type": "input_audio_buffer.append",
                       "audio": bytes.base64EncodedString()])
        }

        engine.prepare()
        try engine.start()
        player.play()
    }

    private func scheduleAudio(_ pcm16: Data) {
        let n = pcm16.count / 2
        guard n > 0,
              let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n))
        else { return }
        buf.frameLength = AVAudioFrameCount(n)
        pcm16.withUnsafeBytes { raw in
            let src = raw.bindMemory(to: Int16.self)
            guard let dst = buf.floatChannelData?[0] else { return }
            for i in 0..<n { dst[i] = Float(src[i]) / 32_768.0 }
        }
        player.scheduleBuffer(buf)
    }
}
