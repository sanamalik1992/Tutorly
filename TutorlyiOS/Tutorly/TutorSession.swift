import Foundation
import SwiftUI

@Observable
final class TutorSession {
    let realtime = RealtimeSession()
    var topic: String = "Calculus · Quadratics"

    func connect() { Task { await realtime.connect() } }
    func disconnect() { realtime.disconnect() }
}
