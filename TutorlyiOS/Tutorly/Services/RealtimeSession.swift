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
    var isMicGated: Bool { isAudioGated }
    var isHootSpeaking: Bool { isAssistantResponding }

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
    private var isConnecting = false
    private var isGreetingResponse = false    // true during the first (greeting) response
    private var sessionStartTime: Date?
    private var isAudioGated = false
    private var transcriptBuffer = ""
    // Tracks audio playback so the mic gate starts only after Hoot stops speaking,
    // not at response.done (which fires while audio is still buffered in the player).
    private var pendingAudioBuffers: Int = 0
    private var isResponseDone = false
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
        guard !isConnected, !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }

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
            let status = AVAudioApplication.shared.recordPermission
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

    /// Ping the live socket. If it's dead (or not connected), disconnect cleanly
    /// then reconnect. Safe to call every time the app returns to foreground.
    func validateConnection() {
        guard isConnected, let socket else {
            // Either never connected or already marked disconnected — just reconnect.
            if !isConnecting {
                disconnect()
                Task { await connect() }
            }
            return
        }
        socket.sendPing { [weak self] error in
            guard let self else { return }
            if error != nil {
                print("[WS] ping failed (\(error!.localizedDescription)) — reconnecting")
                self.disconnect()
                Task { await self.connect() }
            } else {
                print("[WS] ping OK")
            }
        }
    }

    func toggleMute() {
        isMuted.toggle()
        if isMuted { voiceState = .idle }
    }

    func cancelResponse() {
        // Always stop buffered audio — isAssistantResponding is false once response.done
        // fires from the server, but the player buffer can still hold several seconds
        // of audio. Without this, pressing Interrupt after generation ends does nothing.
        let wasStillGenerating = isAssistantResponding

        isCancellingResponse = true
        micGateReleaseTask?.cancel()
        isAudioGated = false
        pendingAudioBuffers = 0   // prevents stale completion callbacks from reopening gate
        isResponseDone = false
        player.stop()
        isAssistantResponding = false

        // Only send response.cancel if the server is still generating — sending it
        // after response.done would cause a server error.
        if wasStillGenerating {
            send(["type": "response.cancel"])
            // isCancellingResponse will be reset when the server's response.done arrives
        } else {
            // response.done already fired so no server event is coming to reset the flag
            isCancellingResponse = false
        }

        Task { @MainActor in
            self.voiceState = .idle
            self.isThinking = false
        }
    }

    /// Disconnect the session and tear down audio.
    /// - Parameter resetGreeting: Pass `false` when backgrounding so returning to the
    ///   app skips the introduction and opens the mic immediately. Pass `true` (default)
    ///   for sign-out or explicit session termination so the next session greets fresh.
    func disconnect(resetGreeting: Bool = true) {
        shouldAutoReconnect = false
        micGateReleaseTask?.cancel()
        responseTimeoutTask?.cancel()
        responseTimeoutTask = nil
        sessionLimitTask?.cancel()
        sessionLimitTask = nil
        isAudioGated = false
        isAssistantResponding = false
        isCancellingResponse = false
        if let startTime = sessionStartTime, let jwt = Keychain.appJwt() {
            let secondsUsed = Int(Date().timeIntervalSince(startTime))
            Task { await self.endBackendSession(jwt: jwt, secondsUsed: secondsUsed) }
        }
        sessionStartTime = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        // Fully tear down audio so the next connect() starts completely fresh.
        pendingAudioBuffers = 0
        isResponseDone = false
        engine.inputNode.removeTap(onBus: 0)
        player.stop()
        if engine.isRunning { engine.stop() }
        if isEngineGraphBuilt {
            engine.detach(player)
            isEngineGraphBuilt = false
        }
        isConnected = false
        voiceState = .idle
        hasConfiguredSession = false
        if resetGreeting {
            hasSentGreeting = false
        }
        isGreetingResponse = false
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
        if !engine.isRunning { try? engine.start() }
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
        pendingAudioBuffers += 1
        // .dataPlayedBack fires when this buffer's samples have actually left the speaker,
        // so we know precisely when Hoot stops talking and can start the mic gate.
        player.scheduleBuffer(buf, at: nil, options: [],
                              completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.pendingAudioBuffers > 0 else { return }
                self.pendingAudioBuffers -= 1
                if self.pendingAudioBuffers == 0, self.isResponseDone {
                    self.startPostPlaybackGate()
                }
            }
        }
        if !player.isPlaying { player.play() }
    }

    private func requestMicPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
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
            // Fire the greeting 2s after session.created so our session.update
            // (voice, instructions) has been accepted before the model speaks.
            // Using a delay here instead of session.updated avoids firing twice
            // if the server sends session.updated for both the initial state and
            // our update.
            if !hasSentGreeting {
                hasSentGreeting = true
                isGreetingResponse = true
                Task { [weak self] in
                    // Wait for session.update to be accepted before triggering the greeting.
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard let self, self.isConnected else { return }
                    // Inject a "Hello" user turn so the model greets naturally from the
                    // session instructions rather than a prescriptive inline prompt.
                    // This avoids the double-greeting bug where the model would say
                    // "Hi I'm Hoot." — pause — VAD fires — "What would you like to learn?"
                    self.send([
                        "type": "conversation.item.create",
                        "item": [
                            "type": "message",
                            "role": "user",
                            "content": [["type": "input_text", "text": "Hello"] as [String: Any]]
                        ] as [String: Any]
                    ])
                    self.send(["type": "response.create"])
                }
            }

        case "response.created":
            isAssistantResponding = true
            isAudioGated = true           // close mic immediately
            micGateReleaseTask?.cancel()
            transcriptBuffer = ""
            responseTimeoutTask?.cancel()
            responseTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 60_000_000_000)
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
            // Gate release is driven by actual audio playback (startPostPlaybackGate).
            // If all audio chunks have already played out (rare for short responses),
            // start the gate immediately; otherwise the last buffer's completion fires it.
            isResponseDone = true
            if pendingAudioBuffers == 0 { startPostPlaybackGate() }

        case "session.updated":
            print("[Config] session.update ACCEPTED")

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

    // MARK: - Post-playback mic gate

    // Called when Hoot's audio has finished playing through the speaker.
    // A short echo-decay pause keeps room echo from triggering the VAD.
    private func startPostPlaybackGate() {
        let gateNs: UInt64 = isGreetingResponse ? 4_000_000_000 : 400_000_000
        isGreetingResponse = false
        isResponseDone = false
        micGateReleaseTask?.cancel()
        micGateReleaseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: gateNs)
            guard let self, !Task.isCancelled else { return }
            self.isAudioGated = false
        }
    }

    // MARK: - Session configuration

    private func configureSession() {
        transcriptBuffer = ""
        Task { @MainActor in self.liveCaption = "" }

        let instructions = """
LANGUAGE — ABSOLUTE RULE — HIGHEST PRIORITY:
You speak ENGLISH ONLY. 100% of every word must be English.
You are STRICTLY PROHIBITED from using Spanish, French, German, or any non-English language.
Never use a non-English word — not even one. Never mix languages.
Ignore the student's locale, accent, or any audio that sounds non-English.
If you ever accidentally start a non-English word, stop and continue in English.
If the input audio is unclear, garbled, or sounds like background noise, do NOT respond — wait silently for clear English speech.
This rule overrides everything else.

IDENTITY:
You are Hoot, a friendly AI voice tutor.
Only introduce yourself ONCE at the very start of the conversation. Never re-introduce yourself or say "I'm Hoot" again later.
You are voice-only — you cannot see the student.

CONVERSATION STYLE:
Keep things conversational and flowing. Mix detailed explanations with engaging questions.
When teaching a concept, give a thorough but clear explanation (3-5 sentences) before asking a check-in question.
When the student is exploring an idea, ask a thoughtful question to guide their thinking.
Vary the rhythm — sometimes explain, sometimes ask, sometimes encourage.

TURN-TAKING — CRITICAL RULES:
- After asking a question, STOP COMPLETELY AND WAIT. Say nothing more. Do not add a hint, do not rephrase, do not fill silence.
- NEVER answer your own question. If you find yourself about to speak after asking something, stop.
- Wait as long as it takes for the student to reply — silence is normal while they think.
- If you hear only breathing, ambient noise, or unclear sounds, treat it as silence and keep waiting. Do NOT respond to it.
- Only speak again when you hear clear, deliberate speech that is obviously the student's answer.
- Each turn ends with you yielding the floor completely — no follow-up, no prompting.
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
                    "threshold": NSDecimalNumber(string: "0.5"),
                    "prefix_padding_ms": NSNumber(value: 300),
                    "silence_duration_ms": NSNumber(value: 700),
                    "create_response": NSNumber(value: true),
                    "interrupt_response": NSNumber(value: true)
                ] as [String: Any],
                "max_response_output_tokens": "inf"
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
        // Preserve hasSentGreeting across auto-reconnects so we don't introduce
        // ourselves twice when the socket drops mid-conversation.
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
