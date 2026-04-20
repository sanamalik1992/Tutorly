import Foundation
import AVFoundation

// RealtimeSession connects to the OpenAI Realtime API over WebSocket.
// Audio: hardware mic (48 kHz Float32) → AVAudioConverter → 24 kHz Float32 → Int16 PCM.
// connect() is NOT called automatically — the user must tap "Connect Voice".
//
// Self-interruption fix: mic is gated by isAssistantResponding, which is cleared only
// when the last audio buffer has actually played out (via a 1-frame marker buffer),
// not when response.done fires (server-side signal, audio still playing).

private let bargeInRMSThreshold: Float = 0.02   // 0.02+ = real speech, <0.008 = room noise

@Observable
final class RealtimeSession {

    // MARK: - Observable state

    var isConnected       = false
    var isMuted           = false
    var isTutorSpeaking   = false
    var isStudentSpeaking = false
    var errorMessage: String?
    var onDraw: ((DrawBlock) -> Void)?

    // MARK: - Private

    private var socket: URLSessionWebSocketTask?
    private let urlSession = URLSession(configuration: .default)

    private let engine     = AVAudioEngine()
    private let player     = AVAudioPlayerNode()
    private var converter: AVAudioConverter?
    private var isEngineGraphBuilt = false

    private let sampleRate: Double = 24_000
    private var pendingCallName: String?
    private var pendingCallId:   String?

    // Mic gate: stays true until the last audio frame plays out (marker completion).
    // Cleared early only on barge-in or cancelled response.
    @ObservationIgnored private var isAssistantResponding = false
    @ObservationIgnored private var lastAssistantFinishTime: Date = .distantPast
    @ObservationIgnored private var pendingBargeInTimer: Timer?
    @ObservationIgnored private var bargeInAudioRMS: Float = 0.0
    @ObservationIgnored private var audioScheduledThisResponse = false
    private let postPlaybackCooldown: TimeInterval = 0.2   // room echo fade

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
        pendingBargeInTimer?.invalidate(); pendingBargeInTimer = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        converter = nil; isConnected = false; isTutorSpeaking = false; isStudentSpeaking = false
    }

    func toggleMute() { isMuted.toggle() }

    func sendText(_ text: String) {
        guard isConnected else { return }
        send(["type": "conversation.item.create",
              "item": ["type": "message", "role": "user",
                       "content": [["type": "input_text", "text": text]]] as [String: Any]])
        send(["type": "response.create"])
    }

    func updateMode(_ mode: TutorMode) {
        currentMode = mode
        guard isConnected else { return }
        print("[Session] updateMode → \(mode.rawValue)")
        send(["type": "session.update",
              "session": ["instructions": buildInstructions(mode: mode)] as [String: Any]])
    }

    // MARK: - WebSocket

    private func openSocket(key: String) {
        var req = URLRequest(url: URL(string:
            "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview")!)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("realtime=v1",   forHTTPHeaderField: "OpenAI-Beta")
        socket = urlSession.webSocketTask(with: req)
        socket?.resume(); isConnected = true; readLoop()
    }

    private func readLoop() {
        socket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                if case .string(let s) = msg { self.handle(s) }
                else if case .data(let d) = msg, let s = String(data: d, encoding: .utf8) { self.handle(s) }
                self.readLoop()
            case .failure(let err):
                Task { @MainActor in self.errorMessage = err.localizedDescription; self.isConnected = false }
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

        switch type {

        case "session.created":
            configureSession()

        case "input_audio_buffer.speech_started":
            // Mic is suppressed while isAssistantResponding, so this should only arrive
            // for genuine student speech. Drop any rare race-condition event.
            print("[VAD] speech_started | suppressed=\(isAssistantResponding)")
            guard !isAssistantResponding else { print("[VAD] ↳ dropped (race)"); break }
            guard Date().timeIntervalSince(lastAssistantFinishTime) > postPlaybackCooldown else {
                print("[VAD] ↳ dropped (cooldown)"); break
            }
            player.stop(); player.play()
            Task { @MainActor in self.isTutorSpeaking = false; self.isStudentSpeaking = true }

        case "input_audio_buffer.speech_stopped":
            Task { @MainActor in self.isStudentSpeaking = false }

        case "response.created":
            isAssistantResponding = true
            audioScheduledThisResponse = false
            // Flush any echo that entered the buffer before suppression kicked in
            send(["type": "input_audio_buffer.clear"])
            Task { @MainActor in self.isTutorSpeaking = true }

        case "response.output_item.added":
            if let item = json["item"] as? [String: Any],
               (item["type"] as? String) == "function_call" {
                pendingCallName = item["name"]    as? String
                pendingCallId   = item["call_id"] as? String
            }

        case "response.audio.delta":
            if let delta = json["delta"] as? String, let pcm = Data(base64Encoded: delta) {
                audioScheduledThisResponse = true
                scheduleAudio(pcm)
            }

        case "response.audio.done":
            // All audio deltas received. Schedule a 1-frame silent marker buffer;
            // its completion handler fires when the LAST audio sample has played out.
            // This is the only correct moment to re-open the mic — not response.done,
            // which fires while the audio queue is still draining.
            Task { @MainActor in self.isTutorSpeaking = false }
            if audioScheduledThisResponse {
                schedulePlaybackEndMarker()
            } else {
                openMicAfterPlayback()
            }

        case "response.function_call_arguments.done":
            let name   = (json["name"]    as? String) ?? pendingCallName ?? ""
            let callId = (json["call_id"] as? String) ?? pendingCallId   ?? ""
            let args   = (json["arguments"] as? String) ?? ""
            print("[Tool] function call: \(name)")
            if name == "draw_on_whiteboard" { handleDraw(args: args, callId: callId) }
            pendingCallName = nil; pendingCallId = nil

        case "response.done":
            pendingBargeInTimer?.invalidate(); pendingBargeInTimer = nil
            // If no audio was in this response (function-call-only), re-open mic now.
            // If audio was scheduled, the playback marker handles it.
            if !audioScheduledThisResponse { openMicAfterPlayback() }
            Task { @MainActor in self.isTutorSpeaking = false }

        case "response.cancelled":
            // Barge-in already cleared state; ensure clean regardless.
            pendingBargeInTimer?.invalidate(); pendingBargeInTimer = nil
            openMicAfterPlayback()
            Task { @MainActor in self.isTutorSpeaking = false }

        case "error":
            if let e = json["error"] as? [String: Any], let msg = e["message"] as? String {
                Task { @MainActor in self.errorMessage = msg }
            }

        default: break
        }
    }

    // Re-opens the mic (clears the suppression flag + sets cooldown start).
    // Called from: playback marker completion, barge-in, cancelled, no-audio response.done.
    private func openMicAfterPlayback() {
        isAssistantResponding  = false
        lastAssistantFinishTime = Date()
        print("[Audio] mic reopened")
    }

    // Schedule a 1-frame silence buffer whose completion fires when the audio queue drains.
    private func schedulePlaybackEndMarker() {
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let marker = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 1) else {
            openMicAfterPlayback(); return
        }
        marker.frameLength = 1
        marker.floatChannelData?[0][0] = 0
        player.scheduleBuffer(marker, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            // Fires on audio thread when the marker (and all prior buffers) have played out.
            guard let self, self.isAssistantResponding else { return }
            DispatchQueue.main.async { self.openMicAfterPlayback() }
        }
    }

    // MARK: - Barge-in from mic tap

    private func checkBargeInFromTap() {
        guard bargeInAudioRMS >= bargeInRMSThreshold else {
            if pendingBargeInTimer != nil { pendingBargeInTimer?.invalidate(); pendingBargeInTimer = nil }
            return
        }
        guard pendingBargeInTimer == nil else { return }
        print("[VAD] barge-in gate open (RMS \(String(format: "%.4f", bargeInAudioRMS)))")
        pendingBargeInTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                print("[VAD] barge-in confirmed — cancelling response")
                self.pendingBargeInTimer = nil
                self.player.stop(); self.player.play()
                // Explicitly clear — marker completion won't fire after player.stop()
                self.openMicAfterPlayback()
                self.isTutorSpeaking   = false
                self.isStudentSpeaking = true
                self.send(["type": "response.cancel"])
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
        print("[Draw] args (\(args.count)c): \(args.prefix(200))")
        if let d = args.data(using: .utf8) {
            do {
                let block = try JSONDecoder().decode(DrawBlock.self, from: d)
                print("[Draw] decoded \(block.commands.count) commands, clear=\(block.clear ?? false)")
                Task { @MainActor in self.onDraw?(block) }
            } catch {
                print("[Draw] decode error: \(error)")
            }
        }
        send(["type": "conversation.item.create",
              "item": ["type": "function_call_output", "call_id": callId,
                       "output": "{\"ok\":true}"] as [String: Any]])
        send(["type": "response.create"])
    }

    // MARK: - Session configuration

    private func configureSession() {
        print("[Session] configuring mode=\(currentMode.rawValue)")
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
                    "threshold": 0.5,         // more sensitive — ChatGPT-like responsiveness
                    "prefix_padding_ms": 300,
                    "silence_duration_ms": 600, // 600ms feels natural; 1100ms was too sluggish
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

        WHITEBOARD RULE — NO EXCEPTIONS: Every time you explain anything visual — an equation, \
        a diagram, a process, a graph, code, a timeline, steps, a formula — call \
        draw_on_whiteboard immediately. Do not say 'I'll draw' or 'let me show you' — just call \
        the tool mid-sentence. Even a simple equation like x=2 deserves a draw call. \
        The student learns visually. Draw first, talk second.
        """
        switch mode {
        case .teach:
            return base + "\n\nMode: TEACH. Explain step-by-step and draw EVERY step on the whiteboard as you go."
        case .quiz:
            return base + "\n\nMode: QUIZ. Ask one question at a time. After each answer, draw the correct working on the whiteboard."
        }
    }

    private func drawToolSchema() -> [String: Any] {
        [
            "type": "function",
            "name": "draw_on_whiteboard",
            "description": """
                Annotate the student's whiteboard. Call for any explanation with a visual \
                element — equations, steps, diagrams, graphs, code. Canvas 900×600, origin \
                top-left. Colors: #1E3A8A navy, #E09C1F amber, #3D9396 teal, #C0392B red.
                """,
            "parameters": [
                "type": "object",
                "properties": [
                    "clear": ["type": "boolean", "description": "Wipe board before drawing"],
                    "commands": [
                        "type": "array",
                        "description": "1-10 ordered draw commands.",
                        "minItems": 1,
                        "items": [
                            "type": "object",
                            "properties": [
                                "type":  ["type": "string",
                                          "enum": ["text", "line", "arrow", "circle", "rect"]],
                                "x": ["type": "number"], "y": ["type": "number"],
                                "text": ["type": "string"],
                                "size": ["type": "number", "description": "font size, default 18"],
                                "color": ["type": "string", "description": "hex color"],
                                "x1": ["type": "number"], "y1": ["type": "number"],
                                "x2": ["type": "number"], "y2": ["type": "number"],
                                "cx": ["type": "number"], "cy": ["type": "number"],
                                "r":  ["type": "number"],
                                "w":  ["type": "number"], "h": ["type": "number"],
                                "fill": ["type": "boolean"],
                                "width": ["type": "number", "description": "stroke width, default 2"]
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

        let playFmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        if !isEngineGraphBuilt {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: playFmt)
            isEngineGraphBuilt = true
        }

        let hwFmt   = engine.inputNode.outputFormat(forBus: 0)
        let monoFmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        guard let conv = AVAudioConverter(from: hwFmt, to: monoFmt) else {
            throw NSError(domain: "RealtimeSession", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Cannot create audio converter " +
                "\(Int(hwFmt.sampleRate)) Hz → \(Int(sampleRate)) Hz"
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
            conv.convert(to: outBuf, error: &convErr) { _, status in status.pointee = .haveData; return buf }
            guard convErr == nil, outBuf.frameLength > 0,
                  let ch = outBuf.floatChannelData?[0] else { return }

            self.updateBargeInRMS(buffer: outBuf)

            // ── MIC GATE ─────────────────────────────────────────────────────────
            // Do NOT send audio to the server while the assistant is speaking.
            // isAssistantResponding stays true until the LAST audio frame plays out
            // (via playback end marker), preventing echo from reaching the server VAD.
            // ─────────────────────────────────────────────────────────────────────
            if self.isAssistantResponding {
                self.checkBargeInFromTap()
                return
            }
            // Short post-playback cooldown for room echo fade
            guard Date().timeIntervalSince(self.lastAssistantFinishTime) > self.postPlaybackCooldown
            else { return }

            let n = Int(outBuf.frameLength)
            var i16 = [Int16](repeating: 0, count: n)
            for i in 0..<n {
                i16[i] = Int16(max(-32_767.0, min(32_767.0, ch[i] * 32_767.0)))
            }
            let bytes = i16.withUnsafeBytes { Data($0) }
            self.send(["type": "input_audio_buffer.append", "audio": bytes.base64EncodedString()])
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
