import Foundation
import SwiftUI

@Observable
final class TutorSession {

    // MARK: - UI state

    var mode: TutorMode = .teach
    var subject: String = ""
    var messages: [ChatMessage] = []
    var isThinking  = false
    var errorMessage: String?

    // Whiteboard bridge — shared by both the Anthropic and Realtime paths
    var pendingDrawBlock: DrawBlock?
    var drawTick: Int = 0
    var clearBoardTrigger: Int = 0

    // MARK: - Services

    let realtimeSession = RealtimeSession()

    // Anthropic pipeline — kept for reference / fallback, not used when Realtime is connected
    let recognizer = SpeechRecognizer()
    let synth       = SpeechSynthesizer()
    private let client = AnthropicClient()
    private let maxHistory = 20

    // MARK: - Init

    init() {
        // Wire realtime draw calls into the shared whiteboard bridge
        realtimeSession.onDraw = { [weak self] block in
            guard let self else { return }
            Task { @MainActor in
                self.pendingDrawBlock = block
                self.drawTick &+= 1
            }
        }
        // connect() is NOT called here — user taps "Connect Voice" on the main screen
    }

    // MARK: - Preset sessions

    func startPresetSession(_ topic: String) {
        subject = topic
        let prompt = mode == .quiz ? "Quiz me on \(topic)." : "Teach me about \(topic)."
        if realtimeSession.isConnected {
            realtimeSession.sendText(prompt)
        } else {
            Task { @MainActor in await sendViaAnthropic(prompt) }
        }
    }

    // MARK: - Anthropic fallback path (kept but unused when Realtime is connected)

    @MainActor
    func sendViaAnthropic(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isThinking else { return }

        messages.append(ChatMessage(role: .user, content: trimmed))
        isThinking   = true
        errorMessage = nil

        do {
            let history = Array(messages.suffix(maxHistory))
            let reply = try await client.chat(messages: history, mode: mode, subject: subject)
            let spoken = reply.spoken.isEmpty ? "(no reply)" : reply.spoken
            messages.append(ChatMessage(role: .assistant, content: spoken))
            isThinking = false

            if let draw = reply.drawBlock {
                pendingDrawBlock = draw
                drawTick &+= 1
            }
            if !reply.spoken.isEmpty {
                synth.speak(cleanForSpeech(spoken))
            }
        } catch {
            isThinking = false
            errorMessage = error.localizedDescription
            messages.append(ChatMessage(role: .assistant, content: "Sorry — \(error.localizedDescription)"))
        }
    }

    func startListening() {
        guard recognizer.isAuthorized else { Task { await recognizer.requestAuthorization() }; return }
        synth.stop()
        recognizer.start { [weak self] final in
            guard let self else { return }
            Task { @MainActor in await self.sendViaAnthropic(final) }
        }
    }

    func stopListening()  { recognizer.stop() }
    func stopSpeaking()   { synth.stop() }

    func newSession() {
        synth.stop(); recognizer.stop()
        messages.removeAll()
        clearBoardTrigger &+= 1
    }

    func clearBoard() { clearBoardTrigger &+= 1 }

    private func cleanForSpeech(_ text: String) -> String {
        var r = text
        if let s = r.range(of: "<draw>"), let e = r.range(of: "</draw>", range: s.upperBound..<r.endIndex) {
            r = String(r[r.startIndex..<s.lowerBound]) + String(r[e.upperBound..<r.endIndex])
        }
        r = String(r.unicodeScalars.filter { !$0.properties.isEmojiPresentation })
        return r
            .replacingOccurrences(of: #"\*+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"#+\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
