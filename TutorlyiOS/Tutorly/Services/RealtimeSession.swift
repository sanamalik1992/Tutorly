import Foundation
import AVFoundation

// RealtimeSession — OpenAI Realtime API over WebSocket.
//
// Mic gate:       isAssistantResponding blocks mic-to-server while AI speaks.
// Barge-in:       2 consecutive tap frames above RMS threshold → interrupt.
//                 No timer needed — each frame is ~170 ms, so 2 frames ≈ 340 ms of speech.
// Marker buffer:  1-frame silence scheduled after last audio chunk; its .dataPlayedBack
//                 completion is the only correct moment to re-open the mic.
// Generation:     responseGeneration ensures a stale marker from Response 1 can't open
//                 the mic while Response 2 (post-draw speak) is playing.
// Draw gate:      hasPendingDrawResponse prevents response.done from opening the mic in
//                 the gap between the draw-only response and the follow-up speaking one.
// tool_choice:    "required" on user-triggered response.create forces the model to always
//                 call draw_on_whiteboard; "none" on the post-draw speaking response so
//                 it doesn't attempt to draw a second time.

private let bargeInRMSThreshold: Float = 0.012   // lowered — easier to interrupt
private let bargeInFramesNeeded: Int   = 2        // ~340 ms of continuous speech

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
    @ObservationIgnored private var safetyTimeoutItem:      DispatchWorkItem?
    @ObservationIgnored private var bargeInAudioRMS:        Float = 0.0
    @ObservationIgnored private var bargeInHighFrames:      Int   = 0
    @ObservationIgnored private var audioScheduledThisResponse = false
    @ObservationIgnored private var responseGeneration: Int = 0
    @ObservationIgnored private var hasPendingDrawResponse  = false
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
        sendResponseCreate(toolChoice: "required")
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

    // Sends response.create with an optional per-response tool_choice override.
    // "required" → model MUST call draw_on_whiteboard.
    // "none"     → model speaks only, no tool call (used for the post-draw speaking turn).
    private func sendResponseCreate(toolChoice: String) {
        if toolChoice == "auto" {
            send(["type": "response.create"])
        } else {
            send(["type": "response.create",
                  "response": ["tool_choice": toolChoice] as [String: Any]])
        }
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

        // Whisper transcript gate: only respond when the user actually said something real.
        // Gate 1: empty string (silence / ambient noise).
        // Gate 2: filler-only — Whisper hallucinates "um"/"hmm" during thinking pauses.
        case "conversation.item.input_audio_transcription.completed":
            let transcript = (json["transcript"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            print("[ASR] '\(transcript)'")
            guard !transcript.isEmpty else {
                print("[ASR] empty — skipping"); break
            }
            let fillers: Set<String> = ["um","uh","mm","hmm","hm","ah","oh","er","erm","mhm","ugh","huh"]
            let words = transcript.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard !words.filter({ !fillers.contains($0) }).isEmpty else {
                print("[ASR] filler-only '\(transcript)' — skipping"); break
            }
            // Force model to draw before speaking on every user turn.
            sendResponseCreate(toolChoice: "required")

        case "conversation.item.input_audio_transcription.failed":
            print("[ASR] transcription failed — skipping")

        case "response.created":
            isAssistantResponding = true
            audioScheduledThisResponse = false
            hasPendingDrawResponse = false
            responseGeneration += 1
            bargeInHighFrames = 0
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
            // Don't open mic when a draw-triggered speaking response is about to start.
            if !audioScheduledThisResponse && !hasPendingDrawResponse { openMic() }
            Task { @MainActor in self.isTutorSpeaking = false }

        case "response.cancelled":
            cancelSafetyTimeout()
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
        bargeInHighFrames       = 0
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
        let gen = responseGeneration
        player.scheduleBuffer(marker, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self, self.isAssistantResponding, self.responseGeneration == gen else { return }
            DispatchQueue.main.async { self.openMic() }
        }
    }

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

    // MARK: - Barge-in
    // Called from the audio tap (background thread). Counts consecutive frames above
    // the RMS threshold. No timer or main-thread dispatch needed for counting —
    // only the actual interrupt is dispatched to main.

    private func checkBargeInFromTap() {
        if bargeInAudioRMS >= bargeInRMSThreshold {
            bargeInHighFrames += 1
            print("[Barge] frame \(bargeInHighFrames) RMS \(String(format:"%.4f", bargeInAudioRMS))")
        } else {
            bargeInHighFrames = 0
            return
        }
        guard bargeInHighFrames >= bargeInFramesNeeded else { return }
        bargeInHighFrames = 0
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isAssistantResponding else { return }
            print("[Barge] confirmed — interrupting")
            self.player.stop(); self.player.play()
            self.responseGeneration += 1
            self.isAssistantResponding   = false
            self.lastAssistantFinishTime = .distantPast
            self.cancelSafetyTimeout()
            self.isTutorSpeaking   = false
            self.isStudentSpeaking = true
            self.send(["type": "response.cancel"])
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
        hasPendingDrawResponse = true
        // Speaking turn: no tool call needed, just voice.
        sendResponseCreate(toolChoice: "none")
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
                    "threshold": 0.55,
                    "prefix_padding_ms": 300,
                    "silence_duration_ms": 800,
                    "create_response": false,
                    "interrupt_response": true
                ] as [String: Any],
                "tools": [drawToolSchema()],
                "tool_choice": "auto"
            ] as [String: Any]
        ])
    }

    private func buildInstructions(mode: TutorMode) -> String {
        let base = """
        LANGUAGE: English only. Always respond in English regardless of the user's \
        device locale, accent, or any language they speak.

        You are a live visual tutor — warm, casual, energetic, like a brilliant teacher \
        with a whiteboard. Use phrases like 'right so', 'okay', 'gotcha', 'nice one'. \
        Ask 'make sense?' after each idea.

        BREVITY — CRITICAL: Maximum 1-2 sentences per turn. Say one thing, then stop \
        and wait for the student. Never lecture. Never keep talking after making a point.

        WHITEBOARD — YOU WILL BE FORCED TO CALL draw_on_whiteboard ON EVERY RESPONSE. \
        This is enforced by the API. When you receive a user message, your first action \
        MUST be to call draw_on_whiteboard before any speech output: \
        • New topic → clear:true + write the topic title large \
        • Equation → write it as text \
        • Concept → write the key word, circle it \
        • Process → numbered steps with arrows \
        • Even for a simple yes/no — write the key word on the board.
        """
        switch mode {
        case .teach:
            return base + "\n\nMode: TEACH. draw_on_whiteboard → explain in 1-2 sentences → ask 'make sense?' → wait."
        case .quiz:
            return base + "\n\nMode: QUIZ. draw_on_whiteboard the concept → ask one short question → wait → draw correct solution."
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

            // Mic gate: while AI is speaking, only check for barge-in — send nothing to server.
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
