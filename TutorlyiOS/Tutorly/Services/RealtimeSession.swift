import Foundation
import AVFoundation

private let backendBase = "https://tutorly-backend-omega.vercel.app"

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
    var sessionsRemaining: Int = -1
    var isFreeLimitReached: Bool = false
    var sessionLimitSeconds: Int = 0

    // Private
    private var socket: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var converter: AVAudioConverter?
    private var isEngineGraphBuilt = false
    private let sampleRate: Double = 24_000

    private var isAssistantResponding = false
    private var hasConfiguredSession = false
    private var hasSentGreeting = false
    private var isCancellingResponse = false
    private var shouldAutoReconnect = false
    private var sessionStartTime: Date?
    private var isAudioGated = false       // true while AI speaks + 2s after, blocks mic sends
    private var transcriptBuffer = ""
    @ObservationIgnored private var pendingStartContinuation: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var responseTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var micGateReleaseTask: Task<Void, Never>?
    @ObservationIgnored private var sessionLimitTask: Task<Void, Never>?
    @ObservationIgnored var completedTranscriptTurn: ((TranscriptTurn) -> Void)?

    // MARK: - Init

    override init() {
        super.init()
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }

    // MARK: - Public

    func connect() async {
        // Dev/test bypass: in DEBUG or TestFlight (sandbox), if a dev OpenAI key is
        // in Keychain, skip the backend session-start (and its free-limit gate) and
        // connect to OpenAI directly. Set the key from Settings → "Dev OpenAI Key".
        // Production App Store builds always skip this branch.
        if Keychain.allowDevBypass,
           let devKey = Keychain.read("openai"), !devKey.isEmpty {
            await MainActor.run {
                self.sessionLimitSeconds = 0
                self.sessionsRemaining = -1
                self.isFreeLimitReached = false
            }
            sessionStartTime = Date()
            print("[Auth] dev bypass: using stored OpenAI key, skipping backend")
            await connectWithToken(devKey)
            return
        }

        guard let jwt = Keychain.appJwt() else {
            await MainActor.run { errorMessage = "Not signed in" }
            return
        }
        do {
            let (ephemeralToken, limitSecs, sessionsLeft) = try await startBackendSession(jwt: jwt)
            await MainActor.run {
                self.sessionLimitSeconds = limitSecs
                self.sessionsRemaining = sessionsLeft
                self.isFreeLimitReached = false
            }
            sessionStartTime = Date()
            armSessionLimitTimer(seconds: limitSecs)
            await connectWithToken(ephemeralToken)
        } catch let e as FreeLimitError {
            await MainActor.run { self.isFreeLimitReached = true; self.errorMessage = e.message }
        } catch {
            await MainActor.run { errorMessage = "Connect failed: \(error.localizedDescription)" }
        }
    }

    private func connectWithToken(_ token: String) async {
        do {
            guard let url = URL(string: "wss://api.openai.com/v1/realtime?model=gpt-realtime") else {
                throw NSError(domain: "Realtime", code: 9, userInfo: [NSLocalizedDescriptionKey: "Realtime URL invalid"])
            }
            let status: AVAudioSession.RecordPermission
            if #available(iOS 17.0, *) {
                switch AVAudioApplication.shared.recordPermission {
                case .undetermined: status = .undetermined
                case .denied: status = .denied
                case .granted: status = .granted
                @unknown default: status = .undetermined
                }
            } else {
                status = AVAudioSession.sharedInstance().recordPermission
            }
            if status == .denied { await MainActor.run { errorMessage = "Enable microphone in Settings" }; return }
            let micOK = status == .granted ? true : await requestMicPermission()
            guard micOK else { await MainActor.run { errorMessage = "Enable microphone in Settings" }; return }

            try setupAudio()

            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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
        if isMuted { voiceState = .idle }
    }

    func cancelResponse() {
        guard isAssistantResponding else { return }
        isCancellingResponse = true
        micGateReleaseTask?.cancel()
        isAudioGated = false             // user is interrupting — open mic right away
        send(["type": "response.cancel"])
        player.stop()
        isAssistantResponding = false
        Task { @MainActor in
            self.voiceState = .idle
            self.isThinking = false
        }
    }

    func disconnect() {
        shouldAutoReconnect = false
        micGateReleaseTask?.cancel()
        sessionLimitTask?.cancel()
        sessionLimitTask = nil
        isAudioGated = false
        if let startTime = sessionStartTime, let jwt = Keychain.appJwt() {
            let secondsUsed = Int(Date().timeIntervalSince(startTime))
            Task { await self.endBackendSession(jwt: jwt, secondsUsed: secondsUsed) }
        }
        sessionStartTime = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        if engine.isRunning { engine.stop() }
        isConnected = false
        voiceState = .idle
        hasConfiguredSession = false
        hasSentGreeting = false
    }

    // MARK: - Backend session

    private func startBackendSession(jwt: String) async throws -> (ephemeralToken: String, limitSeconds: Int, sessionsRemaining: Int) {
        guard let url = URL(string: "\(backendBase)/api/session/start") else {
            throw NSError(domain: "Realtime", code: 10, userInfo: [NSLocalizedDescriptionKey: "Invalid session start URL"])
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Realtime", code: 11, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        if http.statusCode == 402 {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["message"] as? String }
                ?? "Session limit reached. Upgrade to Pro for unlimited access."
            throw FreeLimitError(message: msg)
        }

        guard http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["ephemeralToken"] as? String else {
            throw NSError(domain: "Realtime", code: 12, userInfo: [NSLocalizedDescriptionKey: "Failed to start session"])
        }

        let limitSeconds = json["sessionLimitSeconds"] as? Int ?? 0
        let sessionsLeft = json["sessionsRemaining"] as? Int ?? -1
        return (token, limitSeconds, sessionsLeft)
    }

    private func endBackendSession(jwt: String, secondsUsed: Int) async {
        guard let url = URL(string: "\(backendBase)/api/session/end") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["secondsUsed": secondsUsed])
        _ = try? await URLSession.shared.data(for: req)
        print("[Session] reported \(secondsUsed)s to backend")
    }

    private func armSessionLimitTimer(seconds: Int) {
        sessionLimitTask?.cancel()
        guard seconds > 0 else { return }
        sessionLimitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            print("[Session] per-session time limit (\(seconds)s) reached — disconnecting")
            await MainActor.run {
                self.errorMessage = "Time's up for this session — start another or upgrade for longer."
            }
            self.disconnect()
        }
    }

    // MARK: - Audio setup

    private func setupAudio() throws {
        let avs = AVAudioSession.sharedInstance()
        // .default mode (not .voiceChat) avoids earpiece-first routing that voiceChat enforces.
        // overrideOutputAudioPort after engine.start() explicitly forces the speaker.
        try avs.setCategory(.playAndRecord, mode: .default,
                            options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try avs.setActive(true)

        do {
            try engine.inputNode.setVoiceProcessingEnabled(true)
            print("[Audio] AEC enabled")
        } catch {
            print("[Audio] AEC unavailable: \(error.localizedDescription)")
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
            // Gate mic while AI is speaking AND for 2s after it finishes.
            // This prevents room echo from triggering the server VAD after playback ends.
            guard let self, self.isConnected, !self.isMuted, !self.isAudioGated,
                  let conv = self.converter else { return }
            if buf.frameLength > 0, Int.random(in: 0..<20) == 0 {
                print("[Audio] mic flowing \(buf.frameLength) frames")
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
        }

        try engine.start()
        // Force speaker AFTER engine starts — voice processing may reset the route
        try? avs.overrideOutputAudioPort(.speaker)
        print("[Audio] engine started, output: \(avs.currentRoute.outputs.map { $0.portType.rawValue })")
        player.play()
        print("[Audio] player.isPlaying=\(player.isPlaying)")
    }

    private func scheduleAudio(_ pcm: Data) {
        guard pcm.count >= 2, !isCancellingResponse else { return }
        print("[Audio] scheduleAudio \(pcm.count)B engine=\(engine.isRunning) playing=\(player.isPlaying)")
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

    // MARK: - WebSocket

    private func receive() {
        socket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                if case .string(let s) = msg { self.handle(s) }
                self.receive()
            case .failure(let e):
                print("[WS] receive ended: \(e.localizedDescription)")
                Task { @MainActor in self.isConnected = false }
                // If the socket drops mid-session, trigger reconnect here too
                // (didCloseWith handles clean closes; network drops come through failure)
                guard self.shouldAutoReconnect else { return }
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !self.isConnected else { return }
                    await self.connect()
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
            shouldAutoReconnect = true
            Task { @MainActor in self.isConnected = true }
            if !hasConfiguredSession {
                configureSession()
                hasConfiguredSession = true
            }

        case "response.created":
            isAssistantResponding = true
            isAudioGated = true           // close mic immediately
            micGateReleaseTask?.cancel()
            transcriptBuffer = ""
            responseTimeoutTask?.cancel()
            responseTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                guard let self, !Task.isCancelled else { return }
                await MainActor.run {
                    self.isAssistantResponding = false
                    self.isAudioGated = false
                    self.voiceState = .idle
                    self.errorMessage = "Tutor took too long — try again"
                }
            }
            Task { @MainActor in self.voiceState = .speaking; self.isThinking = true }

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
            Task { @MainActor in self.isThinking = false; self.voiceState = .idle }
            // Keep mic gated for 2 more seconds so room echo from the speaker fades
            // before the server VAD can pick up audio again.
            micGateReleaseTask?.cancel()
            micGateReleaseTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                guard let self, !Task.isCancelled else { return }
                self.isAudioGated = false
            }

        case "session.updated":
            print("[Config] session.update ACCEPTED")
            if !hasSentGreeting {
                hasSentGreeting = true
                send([
                    "type": "response.create",
                    "response": [
                        "instructions": "ENGLISH ONLY. Introduce yourself as Hoot, an AI tutor. Say: 'Hi! I'm Hoot, your AI tutor. What would you like to learn today?' Exactly that. English only."
                    ] as [String: Any]
                ])
            }

        case "input_audio_buffer.speech_started":
            Task { @MainActor in self.voiceState = .listening }

        case "input_audio_buffer.speech_stopped":
            Task { @MainActor in self.voiceState = .idle }

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
                switch code {
                case "input_audio_buffer_commit_empty",
                     "input_audio_buffer_too_small",
                     "conversation_already_has_active_response",
                     "session_not_connected":
                    print("[WS] swallowed noise error: \(code)")
                    return
                default:
                    break
                }
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
LANGUAGE — ABSOLUTE RULE — HIGHEST PRIORITY:
You MUST speak and respond in ENGLISH ONLY. 100% of every word must be English.
You are STRICTLY PROHIBITED from using Spanish, French, or any other language.
Do NOT use Spanish even for a single word. Do NOT mix languages.
Regardless of the student's language, locale, or device settings — English ONLY.
If the student writes or speaks in another language, respond to them in English anyway.
Violating this rule is never acceptable under any circumstances.

You are Hoot, a friendly AI voice tutor. Your goal is to help students learn effectively through clear, encouraging explanation and guided questioning.

TURN-TAKING — CRITICAL RULES:
- Give a clear, helpful explanation of 2-4 sentences per turn, then STOP.
- After asking a question, STOP IMMEDIATELY. Do NOT answer your own question.
- NEVER guess or assume what the student would say. Wait for their real reply.
- Do NOT continue past a question with an answer, explanation, or follow-up.
- Each of your turns must end and yield the floor to the student.
- Provide enough detail that the student actually understands, but keep it conversational.

You are voice-only — you cannot see the student.
"""

        send([
            "type": "session.update",
            "session": [
                "modalities": ["audio", "text"],
                "instructions": instructions,
                "voice": "echo",
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                "input_audio_transcription": ["model": "whisper-1", "language": "en"] as [String: Any],
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": NSDecimalNumber(string: "0.8"),
                    "prefix_padding_ms": NSNumber(value: 300),
                    "silence_duration_ms": NSNumber(value: 800)
                ] as [String: Any],
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
        hasConfiguredSession = false
        hasSentGreeting = false
        Task { @MainActor in self.isConnected = false; self.voiceState = .idle }
        guard shouldAutoReconnect else { return }
        // Server closed the socket (timeout / network change) — reconnect automatically
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await connect()
        }
    }
}

private struct FreeLimitError: Error {
    let message: String
}
