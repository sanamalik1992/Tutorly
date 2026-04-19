import SwiftUI

enum Theme {
    // Brand colors from the Tutorly logo
    static let navy = Color(red: 0.118, green: 0.227, blue: 0.541)        // #1E3A8A
    static let navyDeep = Color(red: 0.086, green: 0.165, blue: 0.388)   // #162A63
    static let teal = Color(red: 0.357, green: 0.710, blue: 0.722)        // #5BB5B8
    static let tealDeep = Color(red: 0.239, green: 0.576, blue: 0.588)   // #3D9396
    static let amber = Color(red: 0.961, green: 0.725, blue: 0.259)      // #F5B942
    static let amberDeep = Color(red: 0.878, green: 0.612, blue: 0.122)  // #E09C1F

    static let ink = Color(red: 0.059, green: 0.102, blue: 0.180)         // #0F1A2E
    static let inkSoft = Color(red: 0.176, green: 0.243, blue: 0.353)    // #2D3E5A
    static let inkFaint = Color(red: 0.420, green: 0.478, blue: 0.561)   // #6B7A8F
    static let line = Color(red: 0.859, green: 0.894, blue: 0.925)       // #DBE4EC
    static let bg = Color(red: 0.980, green: 0.984, blue: 0.988)          // #FAFBFC
    static let bgDeep = Color(red: 0.933, green: 0.953, blue: 0.961)     // #EEF3F5
    static let paper = Color.white

    static let brandGradient = LinearGradient(
        colors: [navy, Color(red: 0.231, green: 0.416, blue: 0.722), teal],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Drawing palette (matches web version)
    static let drawColors: [(name: String, color: Color)] = [
        ("Ink", ink),
        ("Navy", navy),
        ("Teal", tealDeep),
        ("Amber", amberDeep),
        ("Rose", Color(red: 0.780, green: 0.243, blue: 0.373))
    ]
}

// Fonts
extension Font {
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
