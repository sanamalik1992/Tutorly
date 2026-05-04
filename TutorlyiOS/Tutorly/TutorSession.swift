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

    /// Call when the app returns to foreground — tears down any stale socket and reconnects.
    func reconnectIfNeeded() {
        if realtime.isConnected { return }
        // If socket is stale (isConnected false), clean up and reconnect.
        realtime.disconnect()
        connect()
    }
}
