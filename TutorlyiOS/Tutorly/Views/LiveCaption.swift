import SwiftUI

struct LiveCaption: View {
    let liveText: String
    @Environment(TutorSession.self) private var session

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(session.transcriptTurns) { turn in
                        Text(turn.text)
                            .font(.ui(13, weight: .regular))
                            .foregroundStyle(Theme.inkMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                    }
                    if !liveText.isEmpty {
                        Text("\u{201C}\(liveText)")
                            .font(.ui(13, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                            .id("live")
                    }
                }
                .padding(.horizontal, 4)
            }
            .onChange(of: liveText) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("live", anchor: .bottom)
                }
            }
        }
        .frame(maxHeight: 80)
    }
}
