import Foundation
import AVFoundation

@Observable
final class RealtimeSession: NSObject, URLSessionWebSocketDelegate {
    // Observable state
    var isConnected = false
    var voiceState: VoiceState = .idle
    var liveCaption: String = ""
    var errorMessage: String?
    var isThinking = false
    var isMuted = false
    var drawTick = 0
    var pendingDrawBlock: DrawBlock?

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
    private var isCancellingResponse = false
    private var transcriptBuffer = ""
    @ObservationIgnored private var pendingStartContinuation: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var responseTimeoutTask: Task<Void, Never>?
    @ObservationIgnored var completedTranscriptTurn: ((TranscriptTurn) -> Void)?

    // MARK: - Init

    override init() {
        super.init()
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }

    // MARK: - Public

    func connect() async {
        guard let key = Keychain.read("openai"), !key.isEmpty else { return }

        do {
            guard let url = URL(string: "wss://api.openai.com/v1/realtime?model=gpt-realtime") else { throw NSError(domain: "Realtime", code: 9, userInfo: [NSLocalizedDescriptionKey: "Realtime URL invalid"]) }
            let status = currentRecordPermission()
            if status == .denied { await MainActor.run { errorMessage = "Enable microphone in Settings" }; return }
            let micOK = status == .granted ? true : await requestMicPermission()
            guard micOK else { await MainActor.run { errorMessage = "Enable microphone in Settings" }; return }

            try setupAudio()

            var req = URLRequest(url: url)
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            req.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
            print("[WS] connect -> \(req.url?.absoluteString ?? "nil") auth=Bearer ***")
            socket = urlSession.webSocketTask(with: req)
            socket?.resume()
            receive()
        } catch {
            await MainActor.run { errorMessage = "Connect failed: \(error.localizedDescription)" }
        }
    }

    func toggleMute() {
        isMuted.toggle()
        if isMuted {
            isTalking = false
            voiceState = .idle
        }
    }

    func disconnect() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        if engine.isRunning { engine.stop() }
        player.stop()
        isTalking = false
        isConnected = false
        voiceState = .idle
    }

    func startTalking() {
        guard isConnected, !isMuted else { return }
        Task { @MainActor in
            if !engine.isRunning {
                print("[Audio] engine not running when startTalking called — restarting")
                do { try engine.start() } catch {
                    print("[Audio] engine restart FAILED: \(error)")
                    self.errorMessage = "Mic not ready — try again"
                    return
                }
            }
            // Start recording immediately so the first words are never dropped
            bytesAppendedThisTurn = 0
            isTalking = true
            voiceState = .listening

            if isAssistantResponding {
                // Mute playback so server audio that arrives before cancel-ack is swallowed
                isCancellingResponse = true
                player.stop()
                send(["type": "response.cancel"])
                // Wait up to 600ms for response.done; force-clear state on timeout
                await withCheckedContinuation { cont in
                    self.pendingStartContinuation = cont
                    Task {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        if let c = self.pendingStartContinuation {
                            self.pendingStartContinuation = nil
                            c.resume()
                        }
                    }
                }
                isAssistantResponding = false
                isCancellingResponse = false
            }
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
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: [.notifyOthersOnDeactivation])
        try? session.overrideOutputAudioPort(.speaker)

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
        isCancellingResponse = false
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

    private func requestMicPermission() async -> Bool {
        await withCheckedContinuation { cont in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        }
    }

    private func currentRecordPermission() -> AVAudioSession.RecordPermission {
        if #available(iOS 17.0, *) {
            let p = AVAudioApplication.shared.recordPermission
            switch p {
            case .granted: return .granted
            case .denied: return .denied
            default: return .undetermined
            }
        }
        return AVAudioSession.sharedInstance().recordPermission
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
            Task { @MainActor in
                self.isConnected = true
                self.voiceState = .listening
            }
            isTalking = true
            configureSession()

        case "response.created":
            isAssistantResponding = true
            transcriptBuffer = ""
            responseTimeoutTask?.cancel()
            responseTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                guard let self, !Task.isCancelled else { return }
                await MainActor.run {
                    self.isAssistantResponding = false
                    self.voiceState = .idle
                    self.errorMessage = "Tutor took too long — try again"
                }
            }
            Task { @MainActor in self.voiceState = .speaking; self.isThinking = true }

        case "input_audio_buffer.speech_started":
            if isAssistantResponding {
                isCancellingResponse = true
                player.stop()
                send(["type": "response.cancel"])
            }
            Task { @MainActor in
                self.voiceState = .listening
                self.isThinking = false
            }

        case "input_audio_buffer.speech_stopped":
            Task { @MainActor in
                if self.isConnected { self.voiceState = .listening }
            }

        case "response.audio.delta", "response.output_audio.delta":
            if let delta = json["delta"] as? String, let pcm = Data(base64Encoded: delta) {
                scheduleAudio(pcm)
            }

        case "response.audio_transcript.delta", "response.output_audio_transcript.delta":
            if let d = json["delta"] as? String {
                transcriptBuffer += d
                Task { @MainActor in self.liveCaption = self.transcriptBuffer }
            }

        case "response.audio_transcript.done", "response.output_audio_transcript.done":
            let finalText = (json["transcript"] as? String) ?? transcriptBuffer
            if !finalText.isEmpty {
                let turn = TranscriptTurn(role: "assistant", text: finalText)
                completedTranscriptTurn?(turn)
            }
            Task { @MainActor in self.liveCaption = "" }

        case "response.audio.done", "response.output_audio.done":
            Task { @MainActor in self.voiceState = .idle; self.isThinking = false }

        case "response.done":
            responseTimeoutTask?.cancel()
            responseTimeoutTask = nil
            isAssistantResponding = false
            isCancellingResponse = false
            pendingStartContinuation?.resume()
            pendingStartContinuation = nil
            Task { @MainActor in self.isThinking = false; if !self.isTalking { self.voiceState = .idle } }

        case "session.updated":
            print("[Config] session.update ACCEPTED")
            if !isAssistantResponding {
                send([
                    "type": "response.create",
                    "response": [
                        "instructions": "Greet the student warmly in ONE short English sentence. Ask what they'd like to learn today."
                    ] as [String: Any]
                ])
            }

        case "error":
            responseTimeoutTask?.cancel()
            responseTimeoutTask = nil
            isAssistantResponding = false
            isCancellingResponse = false
            if let e = json["error"] as? [String: Any] {
                let code = e["code"] as? String ?? ""
                let msg  = e["message"] as? String ?? "Unknown error"
                let short = String(msg.prefix(80)) + (msg.count > 80 ? "…" : "")
                print("[WS] ERROR code=\(code): \(msg)")
                let noise = ["input_audio_buffer_too_short", "buffer_too_small", "concurrent_response"]
                if !noise.contains(code) {
                    Task { @MainActor in self.errorMessage = short }
                }
            }
            Task { @MainActor in self.voiceState = .idle; self.isThinking = false }

        default: break
        }
    }

    // MARK: - Session configuration

    private func configureSession() {
        transcriptBuffer = ""
        Task { @MainActor in self.liveCaption = "" }

        let instructions = """
        You are Hoot — a warm, encouraging AI tutor for one-on-one voice sessions.

        LANGUAGE: English only, always. Never switch to any other language regardless of what the student says.

        STYLE: Short responses — one or two sentences maximum. Warm, casual, conversational. End each response with a quick checking question to invite the student to reply.

        ROLE: You explain concepts clearly, ask questions to check understanding, and adjust your pace to the student. Keep the energy upbeat and encouraging.
        """

        send([
            "type": "session.update",
            "session": [
                "modalities": ["audio", "text"],
                "instructions": instructions,
                "voice": "marin",
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                "input_audio_transcription": ["model": "whisper-1", "language": "en"] as [String: Any],
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": NSNumber(value: 0.45),
                    "prefix_padding_ms": NSNumber(value: 300),
                    "silence_duration_ms": NSNumber(value: 550),
                    "create_response": true
                ] as [String: Any],
                "temperature": NSNumber(value: 0.8),
                "max_response_output_tokens": NSNumber(value: 300)
            ] as [String: Any]
        ])
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
