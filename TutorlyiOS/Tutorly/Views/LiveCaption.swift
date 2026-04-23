import SwiftUI

struct LiveCaption: View {
    let text: String
    var body: some View {
        if !text.isEmpty {
            Text("\u{201C}\(text)\u{201D}")
                .font(.ui(13, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.bg.opacity(0.85))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 6)),
                    removal: .opacity
                ))
        }
    }
}
