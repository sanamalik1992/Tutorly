import SwiftUI

struct ContentView: View {
    @Environment(TutorSession.self) private var session
    @State private var showSettings = false
    @State private var showTypeInput = false
    @State private var typedPrompt = ""
    @State private var mode: LearnMode = .teach
    @State private var subject = ""
    @FocusState private var isSubjectFocused: Bool
    @State private var toast: String?

    private let suggestions = ["Algebra", "Calculus", "Biology", "Chemistry", "History"]

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 12) {
                headerCard
                modeSubjectCard
                toolsCard
                whiteboardCard
                voiceBarCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)

            if let toast { toastView(toast) }
        }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .onChange(of: session.realtime.errorMessage) { _, newValue in
            guard let newValue else { return }
            withAnimation { toast = newValue }
            session.realtime.errorMessage = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { toast = nil } }
        }
    }

    private var headerCard: some View {
        cardBase(height: 60) {
            HStack {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(colors: [.blue, .teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 36, height: 36)
                        .overlay(Text("T").bold().foregroundStyle(.white))
                    Text("Tutor") + Text("ly").italic().foregroundStyle(.blue) + Text("•").foregroundStyle(.orange)
                }.font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "text.alignleft")
                    Button(action: { showSettings = true }) { Image(systemName: "gear") }
                }
                .font(.system(size: 19, weight: .semibold))
                .frame(height: 36)
            }
        }
    }

    private var modeSubjectCard: some View {
        cardBase {
            VStack(spacing: 10) {
                Picker("Mode", selection: $mode) {
                    ForEach(LearnMode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                TextField("What are we learning today?", text: $subject)
                    .focused($isSubjectFocused)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.09)))
                    .overlay(alignment: .leading) { Image(systemName: "book").padding(.leading, 8).opacity(0.6) }
                    .padding(.leading, 24)
                if isSubjectFocused && subject.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(suggestions, id: \.self) { s in Button(s) { subject = s } } }
                    }
                }
            }
        }
    }

    private var toolsCard: some View {
        cardBase {
            HStack { ForEach(["black","blue","green","orange","red"], id: \.self) { c in Circle().fill(Color(c)).frame(width: 20, height: 20) }
                Spacer(); Image(systemName: "pencil"); Image(systemName: "eraser"); Image(systemName: "trash") }
            .font(.system(size: 16, weight: .semibold))
        }
    }

    private var whiteboardCard: some View {
        ZStack {
            TutorWhiteboardCanvas().clipShape(RoundedRectangle(cornerRadius: 14))
            TimelineView(.animation) { context in
                let angle = Angle.degrees((context.date.timeIntervalSinceReferenceDate * 30).truncatingRemainder(dividingBy: 360))
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(AngularGradient(colors: [.blue,.teal,.orange,.blue], center: .center, angle: angle), lineWidth: session.realtime.isThinking ? 3 : 1.5)
                    .opacity(session.realtime.isThinking ? 0.95 : 0.35)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var voiceBarCard: some View {
        cardBase(height: 80) {
            HStack(spacing: 12) {
                VStack(spacing: 2) {
                    Text(statusLine).font(.system(size: 14, weight: .medium, design: .rounded)).lineLimit(1)
                    Button(action: voiceButtonTap) { Circle().fill(buttonGradient).frame(width: 64, height: 64).overlay(Image(systemName: voiceIcon).foregroundStyle(.white)) }
                    Text(session.realtime.isConnected ? (session.realtime.isMuted ? "MUTED" : "LIVE") : "CONNECT")
                        .font(.system(size: 9, weight: .bold, design: .rounded).monospaced()).tracking(1.3)
                }
                Spacer()
                if showTypeInput && !session.realtime.isConnected {
                    TextField("Type instead", text: $typedPrompt).textFieldStyle(.roundedBorder)
                } else if !session.realtime.isConnected {
                    Button("type instead") { withAnimation { showTypeInput = true } }
                }
            }
        }
    }

    private func voiceButtonTap() {
        if session.realtime.isConnected { session.realtime.toggleMute() }
        else { session.connect() }
    }

    private var statusLine: String {
        if !session.realtime.isConnected { return "Tap Connect to start" }
        if session.realtime.isMuted { return "Muted" }
        if session.realtime.voiceState == .speaking { return "Tutorly is speaking" }
        if session.realtime.isThinking { return "Tutorly is thinking" }
        return "Listening…"
    }

    private var voiceIcon: String { session.realtime.voiceState == .speaking ? "waveform" : (session.realtime.isConnected && !session.realtime.isMuted ? "mic" : "mic.slash") }
    private var buttonGradient: LinearGradient {
        if !session.realtime.isConnected { return .init(colors: [.blue,.teal], startPoint: .topLeading, endPoint: .bottomTrailing) }
        if session.realtime.isMuted { return .init(colors: [.gray,.gray], startPoint: .topLeading, endPoint: .bottomTrailing) }
        if session.realtime.voiceState == .speaking { return .init(colors: [.orange,.blue], startPoint: .topLeading, endPoint: .bottomTrailing) }
        return .init(colors: [.teal,.orange], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func toastView(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 8).background(.black.opacity(0.85), in: Capsule()).frame(maxHeight: .infinity, alignment: .top).padding(.top, 18)
    }

    private func cardBase<Content: View>(height: CGFloat? = nil, @ViewBuilder content: () -> Content) -> some View {
        content().padding(16).frame(maxWidth: .infinity).frame(height: height).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
    }
}

private extension ContentView { enum LearnMode: String, CaseIterable { case teach = "Teach me", quiz = "Quiz me" } }

private struct TutorWhiteboardCanvas: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06))
            Canvas { ctx, size in
                let spacing: CGFloat = 18
                let dot = Color.white.opacity(0.12)
                var y: CGFloat = 8
                while y < size.height {
                    var x: CGFloat = 8
                    while x < size.width {
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)), with: .color(dot))
                        x += spacing
                    }
                    y += spacing
                }
                var margin = Path()
                margin.move(to: CGPoint(x: 24, y: 0))
                margin.addLine(to: CGPoint(x: 24, y: size.height))
                ctx.stroke(margin, with: .color(Color.red.opacity(0.25)), lineWidth: 1)
            }
            .padding(10)
        }
    }
}
