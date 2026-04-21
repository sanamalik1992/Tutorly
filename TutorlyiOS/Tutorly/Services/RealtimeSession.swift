import Foundation
import AVFoundation

// RealtimeSession — OpenAI Realtime API over WebSocket.
// Self-interruption fix: mic gated by isAssistantResponding, cleared only when
// the last audio sample plays out (marker buffer completion), not on response.done.
// Barge-in: RMS gate in mic tap, timer created on MAIN RunLoop (audio thread
// RunLoop does not process timers — previous bug that silenced all interruption).
// Generation counter: when AI draws+speaks (2 responses), Response 1's marker must
// not open the mic during Response 2. responseGeneration invalidates stale markers.

private let bargeInRMSThreshold: Float = 0.018

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

    @ObservationIgnored private var isAssistantResponding   = false
    @ObservationIgnored private var lastAssistantFinishTime: Date = .distantPast
    @ObservationIgnored private var pendingBargeInTimer:    Timer?
    @ObservationIgnored private var safetyTimeoutItem:      DispatchWorkItem?
    @ObservationIgnored private var bargeInAudioRMS:        Float = 0.0
    @ObservationIgnored private var audioScheduledThisResponse = false
    @ObservationIgnored private var responseGeneration: Int = 0
    private let postPlaybackCooldown: TimeInterval = 0.35

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
        cancelSafetyTimeout()
        pendingBargeInTimer?.invalidate(); pendingBargeInTimer = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        if engine.isRunning { engine.inputNode.removeTap(onBus: 0); engine.stop() }
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
            print("[VAD] speech_started suppressed=\(isAssistantResponding)")
            guard !isAssistantResponding else { print("[VAD] ↳ race drop"); break }
            guard Date().timeIntervalSince(lastAssistantFinishTime) > postPlaybackCooldown else {
                print("[VAD] ↳ cooldown drop"); break
            }
            player.stop(); player.play()
            Task { @MainActor in self.isTutorSpeaking = false; self.isStudentSpeaking = true }

        case "input_audio_buffer.speech_stopped":
            Task { @MainActor in self.isStudentSpeaking = false }

        // Whisper transcript is ready — only respond if the user actually said something.
        // Gate 1: empty transcript (silence / ambient noise).
        // Gate 2: filler-only transcript — Whisper hallucinates "um", "hmm" etc. during
        //         pauses; the AI must not evaluate these as a real answer in quiz mode.
        case "conversation.item.input_audio_transcription.completed":
            let transcript = (json["transcript"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            print("[ASR] '\(transcript)'")
            guard !transcript.isEmpty else {
                print("[ASR] empty transcript — skipping")
                break
            }
            let fillers: Set<String> = ["um","uh","mm","hmm","hm","ah","oh","er","erm","mhm","ugh","huh"]
            let words = transcript.lowercased()
                .components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            let meaningful = words.filter { !fillers.contains($0) }
            guard !meaningful.isEmpty else {
                print("[ASR] filler-only '\(transcript)' — skipping")
                break
            }
            send(["type": "response.create"])

        case "conversation.item.input_audio_transcription.failed":
            print("[ASR] transcription failed — skipping response")

        case "response.created":
            isAssistantResponding = true
            audioScheduledThisResponse = false
            responseGeneration += 1
            send(["type": "input_audio_buffer.clear"])
            scheduleSafetyTimeout()
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
            Task { @MainActor in self.isTutorSpeaking = false }
            if audioScheduledThisResponse {
                schedulePlaybackEndMarker()
            } else {
                openMic()
            }

        case "response.function_call_arguments.done":
            let name   = (json["name"]    as? String) ?? pendingCallName ?? ""
            let callId = (json["call_id"] as? String) ?? pendingCallId   ?? ""
            let args   = (json["arguments"] as? String) ?? ""
            print("[Tool] \(name)")
            if name == "draw_on_whiteboard" { handleDraw(args: args, callId: callId) }
            pendingCallName = nil; pendingCallId = nil

        case "response.done":
            cancelSafetyTimeout()
            pendingBargeInTimer?.invalidate(); pendingBargeInTimer = nil
            if !audioScheduledThisResponse { openMic() }
            Task { @MainActor in self.isTutorSpeaking = false }

        case "response.cancelled":
            cancelSafetyTimeout()
            pendingBargeInTimer?.invalidate(); pendingBargeInTimer = nil
            openMic()
            Task { @MainActor in self.isTutorSpeaking = false }

        case "error":
            if let e = json["error"] as? [String: Any], let msg = e["message"] as? String {
                Task { @MainActor in self.errorMessage = msg }
            }

        default: break
        }
    }

    // MARK: - Mic gate

    private func openMic() {
        cancelSafetyTimeout()
        isAssistantResponding   = false
        lastAssistantFinishTime = Date()
        print("[Mic] opened")
    }

    private func schedulePlaybackEndMarker() {
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let marker = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 1) else {
            openMic(); return
        }
        marker.frameLength = 1
        marker.floatChannelData?[0][0] = 0
        // Capture generation so a later response's response.created can't be mistakenly opened by this marker.
        // Happens when AI draws+speaks: Response 1's marker must not fire during Response 2.
        let gen = responseGeneration
        player.scheduleBuffer(marker, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self, self.isAssistantResponding, self.responseGeneration == gen else { return }
            DispatchQueue.main.async { self.openMic() }
        }
    }

    // 45-second failsafe — clears stuck suppression if marker/cancel never arrives
    private func scheduleSafetyTimeout() {
        cancelSafetyTimeout()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isAssistantResponding else { return }
            print("[Session] safety timeout — force-opening mic")
            self.openMic()
        }
        safetyTimeoutItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: item)
    }

    private func cancelSafetyTimeout() {
        safetyTimeoutItem?.cancel(); safetyTimeoutItem = nil
    }

    // MARK: - Barge-in (called from audio tap — timer MUST be created on main RunLoop)

    private func checkBargeInFromTap() {
        if bargeInAudioRMS < bargeInRMSThreshold {
            guard pendingBargeInTimer != nil else { return }
            DispatchQueue.main.async { [weak self] in
                self?.pendingBargeInTimer?.invalidate()
                self?.pendingBargeInTimer = nil
            }
            return
        }
        guard pendingBargeInTimer == nil else { return }
        // ── CRITICAL FIX ─────────────────────────────────────────────────────
        // Timer.scheduledTimer on the audio thread's RunLoop never fires.
        // Must dispatch to main so the timer is added to the main RunLoop.
        // ─────────────────────────────────────────────────────────────────────
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isAssistantResponding, self.pendingBargeInTimer == nil else { return }
            print("[VAD] barge-in gate (RMS \(String(format: "%.4f", self.bargeInAudioRMS)))")
            self.pendingBargeInTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
                guard let self else { return }
                print("[VAD] barge-in confirmed — interrupting")
                self.pendingBargeInTimer = nil
                self.player.stop(); self.player.play()
                // Bump generation: player.stop() cancels marker callbacks, but the guard
                // here ensures any that somehow fire after stop() are also ignored.
                self.responseGeneration += 1
                self.isAssistantResponding   = false
                self.lastAssistantFinishTime = .distantPast  // bypass post-playback cooldown
                self.cancelSafetyTimeout()
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
        print("[Draw] \(args.count) chars: \(args.prefix(120))")
        if let d = args.data(using: .utf8) {
            do {
                let block = try JSONDecoder().decode(DrawBlock.self, from: d)
                print("[Draw] decoded \(block.commands.count) commands")
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
        print("[Session] configure mode=\(currentMode.rawValue)")
        send([
            "type": "session.update",
            "session": [
                "modalities": ["text", "audio"],
                "instructions": buildInstructions(mode: currentMode),
                "voice": "sage",
                "temperature": 0.8,
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                "input_audio_transcription": ["model": "whisper-1"],
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.55,        // less sensitive — avoids echo false-positives
                    "prefix_padding_ms": 300,
                    "silence_duration_ms": 800, // enough time to pause and think
                    "create_response": false,   // WE create responses, only after Whisper confirms non-empty speech
                    "interrupt_response": true
                ] as [String: Any],
                "tools": [drawToolSchema()],
                "tool_choice": "auto"
            ] as [String: Any]
        ])
    }

    private func buildInstructions(mode: TutorMode) -> String {
        let base = """
        You are a live visual tutor — like a great teacher with a whiteboard. Your style: \
        warm, casual, energetic. Use phrases like 'right so', 'okay', 'gotcha', 'nice'. \
        Ask 'make sense?' after each idea.

        RESPONSE LENGTH — CRITICAL: Speak in SHORT bursts only. Maximum 1-2 sentences \
        per turn. Stop and let the student respond. Do NOT lecture. Do NOT keep talking \
        after making a point. Say one thing, then wait.

        WHITEBOARD — MANDATORY: You MUST call draw_on_whiteboard for every explanation. \
        Call it BEFORE you speak the explanation so drawing appears as you talk. \
        For equations: draw the equation as text. For processes: draw steps with arrows. \
        For concepts: write the key word with a circle or underline. \
        Even for a simple definition, write the key term on the board. \
        Never skip the whiteboard. The student learns visually.
        """
        switch mode {
        case .teach:
            return base + "\n\nMode: TEACH. Call draw_on_whiteboard first, then explain in 1-2 sentences, then pause."
        case .quiz:
            return base + "\n\nMode: QUIZ. Ask one short question. After their answer, draw the correct solution on the board."
        }
    }

    private func drawToolSchema() -> [String: Any] {
        [
            "type": "function",
            "name": "draw_on_whiteboard",
            "description": """
                Write notes and draw diagrams on the student's whiteboard. \
                Call this BEFORE speaking your explanation. \
                Use for: equations, key terms, step-by-step working, diagrams, labels. \
                Canvas 900×600, origin top-left. Colors: #1E3A8A navy, #E09C1F amber, \
                #3D9396 teal, #C0392B red. Start new topics with clear:true.
                """,
            "parameters": [
                "type": "object",
                "properties": [
                    "clear": ["type": "boolean", "description": "Wipe board for a new topic"],
                    "commands": [
                        "type": "array",
                        "description": "1-8 draw commands, rendered in order.",
                        "items": [
                            "type": "object",
                            "properties": [
                                "type":  ["type": "string",
                                          "enum": ["text", "line", "arrow", "circle", "rect"]],
                                "x":    ["type": "number", "description": "anchor x (text/rect)"],
                                "y":    ["type": "number", "description": "anchor y (text/rect)"],
                                "text": ["type": "string", "description": "content for text type"],
                                "size": ["type": "number", "description": "font pt, default 28"],
                                "color":["type": "string", "description": "hex, default #1E3A8A"],
                                "x1":  ["type": "number"], "y1": ["type": "number"],
                                "x2":  ["type": "number"], "y2": ["type": "number"],
                                "cx":  ["type": "number"], "cy": ["type": "number"],
                                "r":   ["type": "number"],
                                "w":   ["type": "number"], "h":  ["type": "number"],
                                "fill":["type": "boolean"],
                                "width":["type": "number", "description": "stroke width, default 2"]
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
            options: [.defaultToSpeaker, .allowBluetoothHFP])
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
                NSLocalizedDescriptionKey: "Cannot create audio converter \(Int(hwFmt.sampleRate))→\(Int(sampleRate)) Hz"
            ])
        }
        converter = conv

        engine.inputNode.removeTap(onBus: 0)
        engine.inputNode.installTap(onBus: 0, bufferSize: 4_096, format: hwFmt) { [weak self] buf, _ in
            guard let self, !self.isMuted, let conv = self.converter else { return }

            let ratio  = self.sampleRate / hwFmt.sampleRate
            let outLen = AVAudioFrameCount(Double(buf.frameLength) * ratio + 1)
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: monoFmt, frameCapacity: outLen) else { return }

            var err: NSError?
            conv.convert(to: outBuf, error: &err) { _, status in status.pointee = .haveData; return buf }
            guard err == nil, outBuf.frameLength > 0,
                  let ch = outBuf.floatChannelData?[0] else { return }

            self.updateBargeInRMS(buffer: outBuf)

            // Mic gate: no audio to server while assistant is speaking
            if self.isAssistantResponding {
                self.checkBargeInFromTap()
                return
            }
            guard Date().timeIntervalSince(self.lastAssistantFinishTime) > self.postPlaybackCooldown
            else { return }

            let n = Int(outBuf.frameLength)
            var i16 = [Int16](repeating: 0, count: n)
            for i in 0..<n { i16[i] = Int16(max(-32_767, min(32_767, ch[i] * 32_767))) }
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
