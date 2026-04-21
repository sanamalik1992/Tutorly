import Foundation
import SwiftUI

// MARK: - Modes

enum TutorMode: String, CaseIterable, Identifiable, Codable {
    case teach, quiz
    var id: String { rawValue }
    var label: String { self == .teach ? "Teach me" : "Quiz me" }
}

// MARK: - Messages

enum MessageRole: String, Codable { case user, assistant }

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID; let role: MessageRole; let content: String; let timestamp: Date
    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date()) {
        self.id = id; self.role = role; self.content = content; self.timestamp = timestamp
    }
}

// MARK: - AI whiteboard commands

struct DrawBlock: Decodable {
    let clear: Bool?
    let commands: [DrawCommand]

    enum CodingKeys: String, CodingKey { case clear, commands }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clear = try? c.decode(Bool.self, forKey: .clear)

        // Decode commands leniently: skip any element that fails rather than
        // crashing the entire block on a single bad command from the model.
        var raw = try c.nestedUnkeyedContainer(forKey: .commands)
        var cmds: [DrawCommand] = []
        while !raw.isAtEnd {
            if let cmd = try? raw.decode(DrawCommand.self) {
                cmds.append(cmd)
            } else {
                // Consume the bad element so the cursor advances
                _ = try? raw.decode(SkippedElement.self)
            }
        }
        commands = cmds
    }

    // Used to consume undecodable array elements without failing
    private struct SkippedElement: Decodable {}
}

enum DrawCommand: Identifiable {
    case text(Text)
    case line(Line)
    case arrow(Arrow)
    case circle(Circle)
    case rect(Rect)
    case path(Path)

    var id: UUID { UUID() }

    // All coordinate / content fields use try? + sensible defaults so a missing
    // field never fails the whole command. The model sometimes omits optional
    // coordinates and we'd rather render a slightly-off shape than nothing.

    struct Text: Decodable {
        let x, y: Double; let text: String; let size: Double?; let color: String?
        enum CodingKeys: String, CodingKey { case x, y, text, size, color }
        init(x: Double = 80, y: Double = 80, text: String = "", size: Double? = nil, color: String? = nil) {
            self.x = x; self.y = y; self.text = text; self.size = size; self.color = color
        }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            x    = (try? c.decode(Double.self, forKey: .x))    ?? 80
            y    = (try? c.decode(Double.self, forKey: .y))    ?? 80
            text = (try? c.decode(String.self, forKey: .text)) ?? ""
            size  = try? c.decode(Double.self, forKey: .size)
            color = try? c.decode(String.self, forKey: .color)
        }
    }

    struct Line: Decodable {
        let x1, y1, x2, y2: Double; let color: String?; let width: Double?
        enum CodingKeys: String, CodingKey { case x1, y1, x2, y2, color, width }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            x1 = (try? c.decode(Double.self, forKey: .x1)) ?? 100
            y1 = (try? c.decode(Double.self, forKey: .y1)) ?? 100
            x2 = (try? c.decode(Double.self, forKey: .x2)) ?? 300
            y2 = (try? c.decode(Double.self, forKey: .y2)) ?? 100
            color = try? c.decode(String.self, forKey: .color)
            width = try? c.decode(Double.self, forKey: .width)
        }
    }

    struct Arrow: Decodable {
        let x1, y1, x2, y2: Double; let color: String?; let width: Double?
        enum CodingKeys: String, CodingKey { case x1, y1, x2, y2, color, width }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            x1 = (try? c.decode(Double.self, forKey: .x1)) ?? 100
            y1 = (try? c.decode(Double.self, forKey: .y1)) ?? 200
            x2 = (try? c.decode(Double.self, forKey: .x2)) ?? 300
            y2 = (try? c.decode(Double.self, forKey: .y2)) ?? 200
            color = try? c.decode(String.self, forKey: .color)
            width = try? c.decode(Double.self, forKey: .width)
        }
    }

    struct Circle: Decodable {
        let cx, cy, r: Double; let color: String?; let fill: Bool?; let width: Double?
        enum CodingKeys: String, CodingKey { case cx, cy, r, color, fill, width }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            cx = (try? c.decode(Double.self, forKey: .cx)) ?? 450
            cy = (try? c.decode(Double.self, forKey: .cy)) ?? 300
            r  = (try? c.decode(Double.self, forKey: .r))  ?? 60
            color = try? c.decode(String.self, forKey: .color)
            fill  = try? c.decode(Bool.self,   forKey: .fill)
            width = try? c.decode(Double.self, forKey: .width)
        }
    }

    struct Rect: Decodable {
        let x, y, w, h: Double; let color: String?; let fill: Bool?; let width: Double?
        enum CodingKeys: String, CodingKey { case x, y, w, h, color, fill, width }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            x = (try? c.decode(Double.self, forKey: .x)) ?? 100
            y = (try? c.decode(Double.self, forKey: .y)) ?? 100
            w = (try? c.decode(Double.self, forKey: .w)) ?? 200
            h = (try? c.decode(Double.self, forKey: .h)) ?? 100
            color = try? c.decode(String.self, forKey: .color)
            fill  = try? c.decode(Bool.self,   forKey: .fill)
            width = try? c.decode(Double.self, forKey: .width)
        }
    }

    struct Path: Decodable {
        let points: [[Double]]; let color: String?; let width: Double?
        enum CodingKeys: String, CodingKey { case points, color, width }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            points = (try? c.decode([[Double]].self, forKey: .points)) ?? []
            color  = try? c.decode(String.self, forKey: .color)
            width  = try? c.decode(Double.self, forKey: .width)
        }
    }
}

// Discriminated union decoder — unknown types produce an invisible no-op text command
// rather than failing the whole block.
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
            // Unknown type — render as invisible text so the block still succeeds
            self = .text(Text())
        }
    }
}

// MARK: - Canvas

enum CanvasSize {
    static let logicalWidth:  Double = 900
    static let logicalHeight: Double = 600
}

// MARK: - Color helpers

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b, a: Double
        switch s.count {
        case 6:
            r = Double((v >> 16) & 0xFF) / 255; g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255; a = 1
        case 8:
            r = Double((v >> 24) & 0xFF) / 255; g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8)  & 0xFF) / 255; a = Double(v & 0xFF) / 255
        default: r = 0; g = 0; b = 0; a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
