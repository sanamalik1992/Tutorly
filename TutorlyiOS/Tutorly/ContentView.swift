import SwiftUI
import PencilKit

// MARK: - Shared

private let kSubjectChips = ["Maths", "Physics", "Chemistry", "Biology", "History", "English", "Coding", "Economics"]

struct AnimatedCardBorder: ViewModifier {
    let cornerRadius: CGFloat
    let lineWidth:    CGFloat
    let opacity:      Double
    func body(content: Content) -> some View {
        content.overlay(
            TimelineView(.animation) { tl in
                let a = (tl.date.timeIntervalSinceReferenceDate * 20).truncatingRemainder(dividingBy: 360)
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        AngularGradient(colors: [Theme.navy, Theme.teal, Theme.amber, Theme.navy],
                                        center: .center, angle: .degrees(a)),
                        lineWidth: lineWidth
                    )
                    .opacity(opacity)
            }
        )
    }
}
extension View {
    func animatedBorder(cornerRadius: CGFloat = 20, lineWidth: CGFloat = 1, opacity: Double = 0.3) -> some View {
        modifier(AnimatedCardBorder(cornerRadius: cornerRadius, lineWidth: lineWidth, opacity: opacity))
    }
}

struct SpringButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
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
            VStack(spacing: 0) {
                AppHeader(showSettings: $showSettings, showTranscript: $showTranscript)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 12)

                ControlsStrip()
                    .padding(.bottom, 10)

                // Whiteboard is the dominant element — toolbar floats over it
                ZStack(alignment: .top) {
                    Whiteboard()
                        .padding(.horizontal, 16)

                    FloatingToolbar()
                        .padding(.horizontal, 24)
                        .padding(.top, 10)
                }
                .frame(maxHeight: .infinity)

                VoicePill()
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
            }
            .environment(wbvm)
        }
        .sheet(isPresented: $showSettings)   { SettingsSheet() }
        .sheet(isPresented: $showTranscript) { TranscriptSheet() }
        .alert("Error", isPresented: Binding(
            get: { session.errorMessage != nil || session.realtimeSession.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil; session.realtimeSession.errorMessage = nil }}
        )) {
            Button("OK") { session.errorMessage = nil; session.realtimeSession.errorMessage = nil }
        } message: {
            Text(session.errorMessage ?? session.realtimeSession.errorMessage ?? "")
        }
    }
}

// MARK: - AppHeader

struct AppHeader: View {
    @Binding var showSettings:   Bool
    @Binding var showTranscript: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Brand pill
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.brandGradient)
                        .frame(width: 28, height: 28)
                    Text("T")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                HStack(spacing: 1) {
                    Text("Tutor")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text("ly")
                        .font(.system(size: 20, weight: .regular, design: .rounded).italic())
                        .foregroundStyle(Theme.navy)
                    Text(".")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.amber)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                headerBtn("text.alignleft") { showTranscript = true }
                headerBtn("gearshape")      { showSettings   = true }
            }
        }
    }

    private func headerBtn(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkFaint)
                .frame(width: 36, height: 36)
                .background(Theme.bgDeep)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - ControlsStrip  (mode pills + subject chips in one scrollable row)

struct ControlsStrip: View {
    @Environment(TutorSession.self) private var session
    @State private var showCustomField = false
    @State private var customText      = ""

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // ── Mode pill toggle ─────────────────────────
                ModePillToggle()
                    .padding(.leading, 20)

                Rectangle()
                    .fill(Theme.line)
                    .frame(width: 1, height: 22)
                    .padding(.horizontal, 2)

                // ── Subject chips ────────────────────────────
                ForEach(kSubjectChips, id: \.self) { subject in
                    SubjectChip(
                        label: subject,
                        active: session.subject == subject
                    ) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            session.subject = (session.subject == subject) ? "" : subject
                            showCustomField = false
                        }
                    }
                }

                // Custom chip / field
                if showCustomField {
                    TextField("Topic…", text: $customText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14)
                        .frame(width: 130, height: 34)
                        .background(Theme.paper)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Theme.navy.opacity(0.4), lineWidth: 1.5))
                        .onSubmit {
                            if !customText.isEmpty { session.subject = customText }
                            showCustomField = false
                        }
                } else {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            showCustomField = true
                            session.subject = ""
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                            Text("Other")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Theme.bgDeep)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                    }
                    .padding(.trailing, 20)
                }
            }
            .frame(height: 44)
        }
    }
}

struct ModePillToggle: View {
    @Environment(TutorSession.self) private var session

    var body: some View {
        HStack(spacing: 2) {
            modePill(.teach)
            modePill(.quiz)
        }
        .padding(3)
        .background(Theme.bgDeep)
        .clipShape(Capsule())
    }

    private func modePill(_ m: TutorMode) -> some View {
        let active = session.mode == m
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { session.mode = m }
        } label: {
            Text(m.label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(active ? .white : Theme.inkSoft)
                .padding(.horizontal, 16)
                .frame(height: 28)
                .background(active ? Theme.navy : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: active)
    }
}

struct SubjectChip: View {
    let label:  String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(active ? .white : Theme.inkSoft)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(active ? Theme.tealDeep : Theme.bgDeep)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(active ? Color.clear : Theme.line, lineWidth: 1))
                .shadow(color: active ? Theme.teal.opacity(0.3) : .clear, radius: 6, y: 2)
        }
        .buttonStyle(SpringButtonStyle())
    }
}

// MARK: - FloatingToolbar  (glassmorphism pill, overlays the canvas)

struct FloatingToolbar: View {
    @Environment(TutorSession.self) private var session
    @Environment(WhiteboardViewModel.self) private var vm

    var body: some View {
        HStack(spacing: 8) {
            // Pen / Eraser
            HStack(spacing: 2) {
                toolBtn("pencil.tip", active: !vm.isEraser) {
                    vm.isEraser = false
                    vm.tool = PKInkingTool(.pen, color: .init(vm.selectedColor), width: vm.brushSize)
                }
                toolBtn("eraser", active: vm.isEraser) {
                    vm.isEraser = true
                    vm.tool = PKEraserTool(.vector)
                }
            }
            .padding(3)
            .background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 9))

            // Color swatches
            HStack(spacing: 5) {
                ForEach(Theme.drawColors, id: \.name) { c in
                    Button {
                        vm.selectedColor = c.color
                        vm.isEraser = false
                        vm.tool = PKInkingTool(.pen, color: .init(c.color), width: vm.brushSize)
                    } label: {
                        Circle().fill(c.color).frame(width: 20, height: 20)
                            .shadow(color: c.color.opacity(vm.selectedColor == c.color && !vm.isEraser ? 0.5 : 0),
                                    radius: 4)
                            .scaleEffect(vm.selectedColor == c.color && !vm.isEraser ? 1.2 : 1)
                            .animation(.spring(response: 0.25, dampingFraction: 0.7),
                                       value: vm.selectedColor == c.color)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThickMaterial)
            .clipShape(Capsule())

            Spacer()

            // Clear
            Button { session.clearBoard() } label: {
                Text("CLEAR")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThickMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 3)
    }

    private func toolBtn(_ icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(active ? Theme.paper : Theme.inkFaint)
                .frame(width: 32, height: 32)
                .background(active ? Theme.ink : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }
}

// MARK: - VoicePill  (Duolingo-style dominant bottom element)

struct VoicePill: View {
    @Environment(TutorSession.self) private var session

    var body: some View {
        let rs = session.realtimeSession
        HStack(spacing: 0) {
            // Big mic button
            VoiceMicButton(rs: rs)
                .padding(.leading, 12)

            // Status
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle(rs: rs))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(statusSub(rs: rs))
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.inkFaint)
                    .lineLimit(1)
            }
            .padding(.leading, 16)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Waveform animation when speaking
            if rs.isConnected {
                WaveformBars(active: rs.isTutorSpeaking || rs.isStudentSpeaking)
                    .frame(width: 32)
                    .padding(.trailing, 16)
            }
        }
        .frame(height: 88)
        .background(pillBackground(rs: rs))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: pillShadow(rs: rs), radius: 14, y: 4)
        .animatedBorder(cornerRadius: 24, lineWidth: 1.2, opacity: rs.isConnected ? 0.4 : 0.2)
    }

    private func pillBackground(_ rs: RealtimeSession) -> some ShapeStyle {
        if rs.isStudentSpeaking {
            return AnyShapeStyle(LinearGradient(
                colors: [Theme.amber.opacity(0.12), Theme.paper],
                startPoint: .leading, endPoint: .trailing))
        }
        if rs.isTutorSpeaking {
            return AnyShapeStyle(LinearGradient(
                colors: [Theme.teal.opacity(0.10), Theme.paper],
                startPoint: .leading, endPoint: .trailing))
        }
        return AnyShapeStyle(Theme.paper)
    }

    private func pillShadow(_ rs: RealtimeSession) -> Color {
        if rs.isStudentSpeaking { return Theme.amber.opacity(0.2) }
        if rs.isTutorSpeaking   { return Theme.teal.opacity(0.2) }
        return Color.black.opacity(0.07)
    }

    private func statusTitle(_ rs: RealtimeSession) -> String {
        if !rs.isConnected      { return "Connect to start" }
        if rs.isMuted           { return "Microphone muted" }
        if rs.isStudentSpeaking { return "Listening…" }
        if session.isThinking   { return "Thinking…" }
        if rs.isTutorSpeaking   { return "Speaking…" }
        return "Ready"
    }

    private func statusSub(_ rs: RealtimeSession) -> String {
        if !rs.isConnected      { return "Tap the mic to connect voice" }
        if rs.isMuted           { return "Tap to unmute" }
        if rs.isStudentSpeaking { return "Go ahead, I'm listening" }
        if rs.isTutorSpeaking   { return "Tap mic to interrupt" }
        return "Ask me anything"
    }
}

// MARK: - VoiceMicButton

struct VoiceMicButton: View {
    let rs: RealtimeSession

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30, paused:
            !rs.isConnected || rs.isMuted || rs.isStudentSpeaking || rs.isTutorSpeaking
        )) { ctx in
            let t     = ctx.date.timeIntervalSinceReferenceDate
            let pulse = CGFloat((sin(t * .pi / 2.0) + 1) / 2)

            Button {
                if rs.isConnected { rs.toggleMute() } else { rs.connect() }
            } label: {
                ZStack {
                    // Outer glow ring
                    if rs.isConnected && !rs.isMuted {
                        Circle()
                            .fill(glowColor.opacity(0.12 * pulse))
                            .frame(width: 84, height: 84)
                    }
                    Circle()
                        .fill(btnGradient)
                        .frame(width: 64, height: 64)
                        .shadow(color: glowColor.opacity(0.22 + 0.18 * pulse),
                                radius: 10 + 8 * pulse, y: 4)
                    Image(systemName: btnIcon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(SpringButtonStyle())
        }
    }

    private var btnIcon: String {
        guard rs.isConnected else { return "waveform" }
        return rs.isMuted ? "mic.slash.fill" : "mic.fill"
    }

    private var btnGradient: LinearGradient {
        if rs.isMuted { return LinearGradient(colors: [.gray.opacity(0.7), .gray.opacity(0.5)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing) }
        if rs.isStudentSpeaking { return LinearGradient(colors: [Theme.amber, Theme.amberDeep],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing) }
        if rs.isConnected { return LinearGradient(colors: [Theme.teal, Theme.tealDeep],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing) }
        return LinearGradient(colors: [Theme.navy, Theme.teal],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var glowColor: Color {
        if rs.isStudentSpeaking { return Theme.amber }
        return rs.isConnected ? Theme.teal : Theme.navy
    }
}

// MARK: - WaveformBars  (3 bars that animate when active)

struct WaveformBars: View {
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30, paused: !active)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                bar(phase: 0,    t: t)
                bar(phase: 0.4,  t: t)
                bar(phase: 0.8,  t: t)
            }
        }
    }

    private func bar(phase: Double, t: Double) -> some View {
        let h: CGFloat = active
            ? CGFloat(0.4 + 0.5 * (sin(t * 6 + phase) * 0.5 + 0.5)) * 22
            : 6
        return RoundedRectangle(cornerRadius: 2)
            .fill(active ? Theme.teal : Theme.line)
            .frame(width: 3, height: h)
            .animation(.easeInOut(duration: 0.15), value: h)
    }
}

// MARK: - TranscriptSheet

struct TranscriptSheet: View {
    @Environment(TutorSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if session.messages.isEmpty {
                        Text("Nothing yet — start a conversation.")
                            .font(.system(size: 14, design: .rounded)).italic()
                            .foregroundStyle(Theme.inkFaint)
                            .frame(maxWidth: .infinity).padding(.top, 60)
                    }
                    ForEach(session.messages) { m in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(m.role == .user ? "YOU" : "TUTORLY")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .kerning(1.2).foregroundStyle(Theme.inkFaint)
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
                        .clipShape(RoundedRectangle(cornerRadius: 6))
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
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.system(size: 14, design: .monospaced))
                } header: { Text("OpenAI API Key") } footer: {
                    Text("Real-time voice mode. Stored in your iOS Keychain.")
                }
                Section {
                    SecureField("sk-ant-…", text: $anthropicKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.system(size: 14, design: .monospaced))
                } header: { Text("Anthropic API Key (text fallback)") }
                Section {
                    Picker("Fallback voice", selection: Binding(
                        get: { session.synth.gender }, set: { session.synth.gender = $0 }
                    )) {
                        Text("Female").tag(VoiceGender.female)
                        Text("Male").tag(VoiceGender.male)
                    }
                    .pickerStyle(.segmented)
                } header: { Text("Fallback Voice") }
                Section {
                    Button {
                        Keychain.saveOpenAI(openAIKey); Keychain.save(anthropicKey)
                        saved = true
                        session.realtimeSession.disconnect()
                        if !openAIKey.isEmpty { session.realtimeSession.connect() }
                        Task { try? await Task.sleep(nanoseconds: 1_200_000_000); dismiss() }
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
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

#Preview {
    ContentView().environment(TutorSession())
}
