import Foundation
import SwiftUI

@Observable
final class TutorSession {
    var mode: TutorMode = .teach
    var subject: String = ""
    var messages: [ChatMessage] = []
    var isThinking = false
    var errorMessage: String?
    var handsFree: Bool = false

    // Whiteboard bridge — Views subscribe to these
    var pendingDrawBlock: DrawBlock?
    var drawTick: Int = 0
    var clearBoardTrigger: Int = 0

    // Keep last N turns only, to cap context size
    private let maxHistory = 20

    let recognizer = SpeechRecognizer()
    let synth = SpeechSynthesizer()
    private let client = AnthropicClient()

    // MARK: - Public actions

    @MainActor
    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isThinking else { return }

        messages.append(ChatMessage(role: .user, content: trimmed))
        isThinking = true
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
                synth.speak(reply.spoken) { [weak self] in
                    self?.maybeRestartMic()
                }
            } else {
                maybeRestartMic()
            }
        } catch {
            isThinking = false
            errorMessage = error.localizedDescription
            messages.append(ChatMessage(
                role: .assistant,
                content: "Sorry — \(error.localizedDescription)"
            ))
        }
    }

    func startListening() {
        guard recognizer.isAuthorized else {
            Task { await recognizer.requestAuthorization() }
            return
        }
        synth.stop()
        recognizer.start { [weak self] final in
            guard let self else { return }
            Task { @MainActor in await self.send(final) }
        }
    }

    func stopListening() { recognizer.stop() }

    func stopSpeaking() { synth.stop() }

    func newSession() {
        synth.stop()
        recognizer.stop()
        messages.removeAll()
        clearBoardTrigger &+= 1
    }

    func clearBoard() { clearBoardTrigger &+= 1 }

    func startPresetSession(_ topic: String) {
        subject = topic
        let prompt = mode == .quiz ? "Quiz me on \(topic)." : "Teach me about \(topic)."
        Task { @MainActor in await send(prompt) }
    }

    private func maybeRestartMic() {
        guard handsFree, recognizer.isAuthorized else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            startListening()
        }
    }
}
