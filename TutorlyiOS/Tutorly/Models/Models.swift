import Foundation
import SwiftUI

// MARK: - Modes

enum TutorMode: String, CaseIterable, Identifiable, Codable {
    case teach, quiz
    var id: String { rawValue }
    var label: String { self == .teach ? "Teach me" : "Quiz me" }
}

// MARK: - Messages

enum MessageRole: String, Codable {
    case user, assistant
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

// MARK: - AI whiteboard commands
// The model emits a JSON block matching this shape; we decode and render.

struct DrawBlock: Decodable {
    let clear: Bool?
    let commands: [DrawCommand]
}

enum DrawCommand: Identifiable {
    case text(Text)
    case line(Line)
    case arrow(Arrow)
    case circle(Circle)
    case rect(Rect)
    case path(Path)

    var id: UUID { UUID() }

    struct Text: Decodable {
        let x: Double; let y: Double
        let text: String
        let size: Double?
        let color: String?
    }
    struct Line: Decodable {
        let x1: Double; let y1: Double; let x2: Double; let y2: Double
        let color: String?; let width: Double?
    }
    struct Arrow: Decodable {
        let x1: Double; let y1: Double; let x2: Double; let y2: Double
        let color: String?; let width: Double?
    }
    struct Circle: Decodable {
        let cx: Double; let cy: Double; let r: Double
        let color: String?; let fill: Bool?; let width: Double?
    }
    struct Rect: Decodable {
        let x: Double; let y: Double; let w: Double; let h: Double
        let color: String?; let fill: Bool?; let width: Double?
    }
    struct Path: Decodable {
        let points: [[Double]]
        let color: String?; let width: Double?
    }
}

// Custom decoder — discriminated by "type"
extension DrawCommand: Decodable {
    enum CodingKeys: String, CodingKey { case type }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let single = try decoder.singleValueContainer()
        switch type {
        case "text":   self = .text(try single.decode(Text.self))
        case "line":   self = .line(try single.decode(Line.self))
        case "arrow":  self = .arrow(try single.decode(Arrow.self))
        case "circle": self = .circle(try single.decode(Circle.self))
        case "rect":   self = .rect(try single.decode(Rect.self))
        case "path":   self = .path(try single.decode(Path.self))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown draw command type: \(type)"
            )
        }
    }
}

// Logical canvas size the AI targets — UI scales to fit.
enum CanvasSize {
    static let logicalWidth: Double = 900
    static let logicalHeight: Double = 600
}

// MARK: - Color helpers

extension Color {
    /// Parse hex like "#1e3a8a" or "1e3a8a"
    init(hex: String) {
        let s = hex.trimmingCharacters(in: .whitespaces)
                   .replacingOccurrences(of: "#", with: "")
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b, a: Double
        switch s.count {
        case 6:
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8)  & 0xFF) / 255
            b = Double( v        & 0xFF) / 255
            a = 1
        case 8:
            r = Double((v >> 24) & 0xFF) / 255
            g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8)  & 0xFF) / 255
            a = Double( v        & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0; a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
