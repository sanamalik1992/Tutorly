import SwiftUI

enum Theme {
    // Surfaces
    static let bg      = Color(red: 0.102, green: 0.094, blue: 0.133)  // #1A1822
    static let bgElev  = Color(red: 0.141, green: 0.129, blue: 0.180)  // #24212E
    static let surface = Color(red: 0.165, green: 0.153, blue: 0.204)  // #2A2734

    // Ink
    static let ink       = Color(red: 0.949, green: 0.937, blue: 0.910) // #F2EFE8
    static let inkSoft   = Color(red: 0.710, green: 0.690, blue: 0.753) // #B5B0C0
    static let inkMuted  = Color(red: 0.478, green: 0.463, blue: 0.533) // #7A7688

    // Accent (coral)
    static let accent     = Color(red: 1.0,   green: 0.420, blue: 0.208) // #FF6B35
    static let accentSoft = Color(red: 1.0,   green: 0.420, blue: 0.208).opacity(0.18)
    static let accentDeep = Color(red: 1.0,   green: 0.690, blue: 0.541) // #FFB08A
    static let accentGlow = Color(red: 1.0,   green: 0.420, blue: 0.208).opacity(0.5)

    // Hairlines
    static let hairline       = Color.white.opacity(0.08)
    static let hairlineStrong = Color.white.opacity(0.16)
}

extension Font {
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}
