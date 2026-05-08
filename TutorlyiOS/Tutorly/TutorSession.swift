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

    /// Full disconnect — resets all session state including the greeting flag.
    /// Use this for sign-out and explicit session termination.
    func disconnect() { realtime.disconnect() }

    /// Disconnect that preserves the greeting flag so returning from background
    /// doesn't re-introduce Hoot and gate the mic for 5 seconds.
    func backgroundDisconnect() { realtime.disconnect(resetGreeting: false) }

    func cancelResponse() { realtime.cancelResponse() }

    func autoConnect() {
        guard !realtime.isConnected else { return }
        connect()
    }
}

