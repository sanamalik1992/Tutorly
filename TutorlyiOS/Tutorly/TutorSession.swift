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

    func autoConnect() {
        guard !realtime.isConnected else { return }
        connect()
    }

    /// Call when the app returns to foreground. Pings the live socket to verify
    /// it's truly alive; if the ping fails (or there's no connection), reconnects.
    func reconnectIfNeeded() {
        realtime.validateConnection()
    }
}
