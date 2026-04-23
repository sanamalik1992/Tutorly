import Foundation

enum VoiceState { case idle, listening, speaking }

struct DrawBlock: Decodable {
    let clear: Bool?
    let commands: [DrawCommand]
}

enum DrawCommand {
    case text(TextCmd)
    case line(LineCmd)
    case arrow(ArrowCmd)
    case circle(CircleCmd)
    case rect(RectCmd)

    struct TextCmd: Decodable { let x: Double; let y: Double; let text: String; let size: Double?; let color: String? }
    struct LineCmd: Decodable { let x1, y1, x2, y2: Double; let color: String?; let width: Double? }
    struct ArrowCmd: Decodable { let x1, y1, x2, y2: Double; let color: String?; let width: Double? }
    struct CircleCmd: Decodable { let cx, cy, r: Double; let color: String?; let fill: Bool?; let width: Double? }
    struct RectCmd: Decodable { let x, y, w, h: Double; let color: String?; let fill: Bool?; let width: Double? }
}

extension DrawCommand: Decodable {
    enum K: String, CodingKey { case type }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let t = try c.decode(String.self, forKey: .type)
        let s = try decoder.singleValueContainer()
        switch t {
        case "text":   self = .text(try s.decode(TextCmd.self))
        case "line":   self = .line(try s.decode(LineCmd.self))
        case "arrow":  self = .arrow(try s.decode(ArrowCmd.self))
        case "circle": self = .circle(try s.decode(CircleCmd.self))
        case "rect":   self = .rect(try s.decode(RectCmd.self))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown draw type: \(t)")
        }
    }
}

enum CanvasSize {
    static let width: Double = 900
    static let height: Double = 600
}
