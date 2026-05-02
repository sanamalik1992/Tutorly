import Foundation
import SwiftUI

@Observable
final class TutorSession {
    let realtime = RealtimeSession()
    var topic: String = "Calculus · Quadratics"
    var transcriptTurns: [TranscriptTurn] = []

    init() {
        realtime.completedTranscriptTurn = { [weak self] turn in
            self?.transcriptTurns.append(turn)
        }
    }

    func connect() { Task { await realtime.connect() } }
    func disconnect() { realtime.disconnect() }
    func cancelResponse() { realtime.cancelResponse() }

    func autoConnectIfKeyAvailable() {
        guard !realtime.isConnected, Keychain.read("openai") != nil else { return }
        connect()
    }
}
