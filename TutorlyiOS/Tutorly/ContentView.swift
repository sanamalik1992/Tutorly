import SwiftUI
import PencilKit

// MARK: - Animated card border (shared by all cards except header)

struct AnimatedCardBorder: ViewModifier {
    let cornerRadius: CGFloat
    let lineWidth: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content.overlay(
            TimelineView(.animation) { timeline in
                let angle = (timeline.date.timeIntervalSinceReferenceDate * 20)
                    .truncatingRemainder(dividingBy: 360)
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        AngularGradient(
                            colors: [Theme.navy, Theme.teal, Theme.amber, Theme.navy],
                            center: .center,
                            angle: .degrees(angle)
                        ),
                        lineWidth: lineWidth
                    )
                    .opacity(opacity)
            }
        )
    }
}

extension View {
    func animatedBorder(cornerRadius: CGFloat = 14, lineWidth: CGFloat = 1.0, opacity: Double = 0.25) -> some View {
        modifier(AnimatedCardBorder(cornerRadius: cornerRadius, lineWidth: lineWidth, opacity: opacity))
    }
}

// MARK: - Root

struct ContentView: View {
    @Environment(TutorSession.self) private var session
    @State private var showSettings   = false
    @State private var showTranscript = false
    @State private var wbvm           = WhiteboardViewModel()

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 12) {
                HeaderCard(showSettings: $showSettings, showTranscript: $showTranscript)
                ModeSubjectCard()
                ToolbarCard()
                WhiteboardCard()
                VoiceBarCard()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .environment(wbvm)
        }
        .sheet(isPresented: $showSettings)   { SettingsSheet() }
        .sheet(isPresented: $showTranscript) { TranscriptSheet() }
        .alert("Error", isPresented: Binding(
            get: { session.errorMessage != nil || session.realtimeSession.errorMessage != nil },
            set: { if !$0 {
                session.errorMessage = nil
                session.realtimeSession.errorMessage = nil
            }}
        )) {
            Button("OK") {
                session.errorMessage = nil
                session.realtimeSession.errorMessage = nil
            }
        } message: {
            Text(session.errorMessage ?? session.realtimeSession.errorMessage ?? "")
        }
    }
}

// MARK: - HeaderCard  (56 pt, brand mark + icons only)

struct HeaderCard: View {
    @Binding var showSettings:   Bool
    @Binding var showTranscript: Bool

    var body: some View {
        HStack(spacing: 12) {
            // 36pt gradient T mark
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.brandGradient)
                    .frame(width: 36, height: 36)
                    .shadow(color: Theme.navy.opacity(0.25), radius: 6, y: 2)
                Text("T")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            // Title — SF Pro Rounded Bold 22 pt
            HStack(spacing: 1) {
                Text("Tutor")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text("ly")
                    .font(.system(size: 22, weight: .regular, design: .rounded))
                    .italic()
                    .foregroundStyle(Theme.navy)
                Text(".")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.amber)
            }
            Spacer()
            // Transcript icon
            Button { showTranscript = true } label: { headerIcon("text.alignleft") }
            // Settings icon
            Button { showSettings   = true } label: { headerIcon("gearshape") }
        }
        .frame(height: 56)
    }

    private func headerIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Theme.inkSoft)
            .frame(width: 34, height: 34)
            .background(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - ModeSubjectCard  (ultraThinMaterial, 14pt radius, 16pt padding)

struct ModeSubjectCard: View {
    @Environment(TutorSession.self) private var session

    var body: some View {
        @Bindable var session = session
        return VStack(spacing: 0) {
            // Row 1: Teach me | Quiz me, full-width, 44pt
            HStack(spacing: 0) {
                modeTab(.teach)
                modeTab(.quiz)
            }
            .frame(height: 44)
            Divider()
            // Row 2: subject field, full-width, 44pt
            HStack(spacing: 8) {
                Image(systemName: "book.closed")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
                TextField("What are we learning today?", text: $session.subject)
                    .font(.system(size: 14, design: .rounded))
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .animatedBorder(cornerRadius: 14)
    }

    private func modeTab(_ m: TutorMode) -> some View {
        let active = session.mode == m
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { session.mode = m }
        } label: {
            Text(m.label)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(active ? Theme.paper : Theme.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(active ? Theme.ink : Color.clear)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: active)
    }
}

// MARK: - ToolbarCard  (44pt, ultraThinMaterial, 12pt radius)

struct ToolbarCard: View {
    @Environment(TutorSession.self) private var session
    @Environment(WhiteboardViewModel.self) private var vm

    var body: some View {
        HStack(spacing: 10) {
            // Pen
            toolBtn("pencil.tip", active: !vm.isEraser) {
                vm.isEraser = false
                vm.tool = PKInkingTool(.pen, color: .init(vm.selectedColor), width: vm.brushSize)
            }
            // Eraser
            toolBtn("eraser", active: vm.isEraser) {
                vm.isEraser = true
                vm.tool = PKEraserTool(.vector)
            }
            // Divider
            Rectangle().fill(Theme.line).frame(width: 1, height: 22).padding(.horizontal, 2)
            // 5 color swatches
            HStack(spacing: 6) {
                ForEach(Theme.drawColors, id: \.name) { c in
                    Button {
                        vm.selectedColor = c.color
                        vm.isEraser = false
                        vm.tool = PKInkingTool(.pen, color: .init(c.color), width: vm.brushSize)
                    } label: {
                        Circle().fill(c.color).frame(width: 22, height: 22)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        vm.selectedColor == c.color && !vm.isEraser
                                            ? Theme.ink : Color.clear,
                                        lineWidth: 2)
                                    .padding(-3)
                            )
                    }
                }
            }
            Spacer()
            // Clear
            Button { session.clearBoard() } label: {
                Text("CLEAR")
                    .font(.mono(10, weight: .semibold)).kerning(1.2)
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.line))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animatedBorder(cornerRadius: 12)
    }

    private func toolBtn(_ image: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(active ? Theme.paper : Theme.ink)
                .frame(width: 34, height: 34)
                .background(active ? Theme.ink : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - WhiteboardCard  (flex height, wraps Whiteboard + animated gradient border)

struct WhiteboardCard: View {
    @Environment(TutorSession.self) private var session

    var body: some View {
        Whiteboard()
            .frame(maxHeight: .infinity)
    }
}

// MARK: - VoiceBarCard  (80pt, ultraThinMaterial, 14pt radius)

struct VoiceBarCard: View {
    @Environment(TutorSession.self) private var session

    var body: some View {
        let rs = session.realtimeSession
        HStack(spacing: 16) {
            ConnectMicButton(realtimeSession: rs)
            Text(statusLabel(rs: rs))
                .font(.system(size: 14, weight: .regular, design: .rounded).italic())
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(height: 80)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .animatedBorder(cornerRadius: 14)
    }

    private func statusLabel(rs: RealtimeSession) -> String {
        if !rs.isConnected      { return "Tap Connect to start" }
        if rs.isMuted           { return "Muted" }
        if rs.isStudentSpeaking { return "Listening…" }
        if session.isThinking   { return "Tutorly is thinking" }
        if rs.isTutorSpeaking   { return "Tutorly is speaking" }
        return "Always listening…"
    }
}

// MARK: - ConnectMicButton  (64pt circle, 4 states, 4s pulse when idle-connected)

struct ConnectMicButton: View {
    let realtimeSession: RealtimeSession

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30, paused:
            !realtimeSession.isConnected ||
            realtimeSession.isMuted ||
            realtimeSession.isStudentSpeaking ||
            realtimeSession.isTutorSpeaking
        )) { ctx in
            let t     = ctx.date.timeIntervalSinceReferenceDate
            let pulse = CGFloat((sin(t * .pi / 2.0) + 1) / 2)   // 0 → 1 → 0 over 4 s

            Button {
                if realtimeSession.isConnected { realtimeSession.toggleMute() }
                else { realtimeSession.connect() }
            } label: {
                ZStack {
                    if realtimeSession.isConnected && !realtimeSession.isMuted {
                        Circle()
                            .fill(glowColor.opacity(0.15 * pulse))
                            .frame(width: 86, height: 86)
                    }
                    Circle()
                        .fill(buttonGradient)
                        .frame(width: 64, height: 64)
                        .shadow(color: glowColor.opacity(0.20 + 0.20 * pulse),
                                radius: 8 + 8 * pulse, y: 3)
                    Image(systemName: buttonIcon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(SpringButtonStyle())
        }
    }

    private var buttonIcon: String {
        if !realtimeSession.isConnected { return "waveform" }
        return realtimeSession.isMuted ? "mic.slash.fill" : "mic.fill"
    }

    private var buttonGradient: LinearGradient {
        if realtimeSession.isMuted {
            return LinearGradient(colors: [Color(white: 0.55), Color(white: 0.45)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        if realtimeSession.isConnected {
            if realtimeSession.isStudentSpeaking {
                return LinearGradient(colors: [Theme.amber, Theme.amberDeep],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            return LinearGradient(colors: [Theme.teal, Theme.tealDeep],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        // Not connected — navy → teal
        return LinearGradient(colors: [Theme.navy, Theme.teal],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var glowColor: Color {
        realtimeSession.isConnected ? Theme.teal : Theme.navy
    }
}

// MARK: - SpringButtonStyle

struct SpringButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - TranscriptSheet

struct TranscriptSheet: View {
    @Environment(TutorSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if session.messages.isEmpty {
                        Text("Nothing yet — start a conversation.")
                            .font(.system(size: 14, design: .rounded)).italic()
                            .foregroundStyle(Theme.inkFaint)
                            .frame(maxWidth: .infinity).padding(.top, 60)
                    }
                    ForEach(session.messages) { m in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(m.role == .user ? "YOU" : "TUTORLY")
                                .font(.mono(9, weight: .bold)).kerning(1.2)
                                .foregroundStyle(Theme.inkFaint)
                            Text(m.content)
                                .font(.system(size: 15, design: .rounded))
                                .foregroundStyle(Theme.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(m.role == .assistant ? Theme.navy.opacity(0.04) : Theme.paper)
                        .overlay(Rectangle()
                            .fill(m.role == .assistant ? Theme.navy : Theme.teal)
                            .frame(width: 2), alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding()
            }
            .background(Theme.bg)
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") { session.newSession(); dismiss() }
                        .foregroundStyle(Theme.inkSoft)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.bold()
                }
            }
        }
    }
}

// MARK: - SettingsSheet

struct SettingsSheet: View {
    @Environment(TutorSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var openAIKey    = Keychain.readOpenAI() ?? ""
    @State private var anthropicKey = Keychain.read() ?? ""
    @State private var saved        = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-…", text: $openAIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 14, design: .monospaced))
                } header: { Text("OpenAI API Key") } footer: {
                    Text("Real-time voice mode. Get a key at platform.openai.com. Stored in your iOS Keychain.")
                }

                Section {
                    SecureField("sk-ant-…", text: $anthropicKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 14, design: .monospaced))
                } header: { Text("Anthropic API Key (text fallback)") } footer: {
                    Text("Used when Realtime voice is not connected.")
                }

                Section {
                    Picker("Fallback voice", selection: Binding(
                        get: { session.synth.gender },
                        set: { session.synth.gender = $0 }
                    )) {
                        Text("Female").tag(VoiceGender.female)
                        Text("Male").tag(VoiceGender.male)
                    }
                    .pickerStyle(.segmented)
                } header: { Text("Fallback Voice") } footer: {
                    Text("Voice used when falling back to the Anthropic text pipeline.")
                }

                Section {
                    Button {
                        Keychain.saveOpenAI(openAIKey)
                        Keychain.save(anthropicKey)
                        saved = true
                        session.realtimeSession.disconnect()
                        if !openAIKey.isEmpty { session.realtimeSession.connect() }
                        Task {
                            try? await Task.sleep(nanoseconds: 1_200_000_000)
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text(saved ? "Saved — reconnecting…" : "Save & Connect")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Spacer()
                        }
                    }
                    .disabled(openAIKey.isEmpty && anthropicKey.isEmpty)
                }

                Section {
                    Link("OpenAI platform",   destination: URL(string: "https://platform.openai.com")!)
                    Link("Anthropic console", destination: URL(string: "https://console.anthropic.com")!)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ContentView().environment(TutorSession())
}
