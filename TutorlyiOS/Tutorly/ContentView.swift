import SwiftUI

struct ContentView: View {
    @Environment(TutorSession.self) private var session
    @State private var wbvm           = WhiteboardViewModel()
    @State private var showSettings   = false
    @State private var showTranscript = false
    @State private var showTextInput  = false
    @State private var textInput      = ""
    @FocusState private var textFocused: Bool
    @FocusState private var subjectFocused: Bool

    private let quickSubjects = [
        "Algebra", "Calculus", "Physics", "Chemistry",
        "Biology", "History", "Essays", "Python"
    ]

    var body: some View {
        @Bindable var session = session

        ZStack {
            Theme.bg.ignoresSafeArea()
            backgroundGlow.ignoresSafeArea()

            VStack(spacing: 12) {
                headerCard
                modeSubjectCard
                WhiteboardToolbar()
                Whiteboard()
                    .frame(maxHeight: .infinity)
                voiceBarCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .environment(wbvm)
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

    // MARK: - Background glow

    private var backgroundGlow: some View {
        ZStack {
            Circle().fill(Theme.navy.opacity(0.07)).frame(width: 500).blur(radius: 90).offset(x: -160, y: -260)
            Circle().fill(Theme.teal.opacity(0.08)).frame(width: 400).blur(radius: 80).offset(x: 180, y: 260)
            Circle().fill(Theme.amber.opacity(0.06)).frame(width: 300).blur(radius: 70).offset(x: 40, y: 80)
        }
    }

    // MARK: - CARD 1: Header

    private var headerCard: some View {
        HStack(spacing: 12) {
            // Brand mark
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.brandGradient)
                    .frame(width: 38, height: 38)
                    .shadow(color: Theme.navy.opacity(0.28), radius: 8, x: 0, y: 3)
                Text("T")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.paper)
                Circle().fill(Theme.amber).frame(width: 6, height: 6).offset(x: 11, y: -11)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 1) {
                    Text("Tutor")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text("ly")
                        .font(.system(size: 22, weight: .regular, design: .rounded))
                        .italic()
                        .foregroundStyle(Theme.navy)
                    Text(".")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.amber)
                }
                Text("let's learn together")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.inkFaint)
            }

            Spacer()

            // Connection status dot
            Circle()
                .fill(session.realtimeSession.isConnected ? Theme.teal : Theme.line)
                .frame(width: 8, height: 8)

            Button { showTranscript = true } label: {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(height: 60)
    }

    // MARK: - CARD 2: Mode + Subject

    private var modeSubjectCard: some View {
        @Bindable var session = session
        return VStack(spacing: 8) {
            // Mode toggle — full width
            HStack(spacing: 0) {
                modeButton(.teach)
                modeButton(.quiz)
            }
            .frame(maxWidth: .infinity)
            .background(Theme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.ink, lineWidth: 1.5))

            // Subject field — full width
            HStack(spacing: 8) {
                Image(systemName: "book.closed")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
                TextField("Subject or topic…", text: $session.subject)
                    .font(.system(size: 14, design: .rounded))
                    .focused($subjectFocused)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
                subjectFocused ? Theme.navy.opacity(0.4) : Theme.line
            ))

            // Focus-triggered suggestion chips (only when field focused and empty)
            if subjectFocused && session.subject.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(quickSubjects, id: \.self) { s in
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    session.startPresetSession(s)
                                    subjectFocused = false
                                }
                            } label: {
                                Text(s)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(Theme.inkSoft)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color.clear)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().strokeBorder(Theme.line))
                            }
                            .buttonStyle(SpringButtonStyle())
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: subjectFocused)
    }

    private func modeButton(_ m: TutorMode) -> some View {
        @Bindable var session = session
        let active = session.mode == m
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { session.mode = m }
        } label: {
            Text(m.label)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(active ? Theme.paper : Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(active ? Theme.ink : Color.clear)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: active)
    }

    // MARK: - CARD 4: Voice bar

    private var voiceBarCard: some View {
        let rs = session.realtimeSession
        return Group {
            if rs.isConnected {
                connectedBar
            } else if showTextInput {
                typingBar
            } else {
                disconnectedBar
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: rs.isConnected)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showTextInput)
    }

    // State A: not connected — big Connect CTA + "type" chip
    private var disconnectedBar: some View {
        HStack(spacing: 10) {
            Button {
                session.realtimeSession.connect()
            } label: {
                Label("Connect Voice", systemImage: "waveform")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Theme.brandGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(SpringButtonStyle())

            Button {
                withAnimation(.spring(response: 0.35)) {
                    showTextInput = true
                    textFocused = true
                }
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 14))
                    Text("type")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 54, height: 50)
                .background(Theme.paper)
                .clipShape(RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.line))
            }
            .buttonStyle(SpringButtonStyle())
        }
    }

    // State B: text input expanded
    private var typingBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                TextField("Ask anything…", text: $textInput)
                    .font(.system(size: 14, design: .rounded))
                    .focused($textFocused)
                    .submitLabel(.send)
                    .onSubmit(sendText)
                if !textInput.isEmpty {
                    Button(action: sendText) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Theme.navy)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Theme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.line))

            Button {
                withAnimation(.spring(response: 0.35)) {
                    showTextInput = false
                    textInput = ""
                    textFocused = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.inkFaint)
            }
        }
    }

    // State C: connected — mic button + live status
    private var connectedBar: some View {
        let rs = session.realtimeSession
        return HStack(spacing: 12) {
            MicButton(realtimeSession: rs)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    statusTag
                    if rs.isTutorSpeaking {
                        WaveformBars(isActive: true)
                    }
                }
                Text(statusText)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Status helpers

    private var statusTag: some View {
        let rs = session.realtimeSession
        return Group {
            if rs.isStudentSpeaking {
                statusPill("LISTENING", color: Theme.amberDeep)
            } else if rs.isTutorSpeaking {
                statusPill("SPEAKING", color: Theme.tealDeep)
            } else if rs.isMuted {
                statusPill("MUTED", color: Theme.inkFaint)
            } else {
                statusPill("READY", color: Theme.teal.opacity(0.8))
            }
        }
    }

    private func statusPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.mono(9, weight: .bold))
            .kerning(1.4)
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color)
            .clipShape(Capsule())
    }

    private var statusText: String {
        let rs = session.realtimeSession
        if rs.isMuted          { return "Muted — tap mic to unmute." }
        if rs.isStudentSpeaking { return "Go ahead, I'm listening…" }
        if rs.isTutorSpeaking  { return "Tap the mic to cut in." }
        return "Ask me anything — I'm always listening."
    }

    private func sendText() {
        let t = textInput.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        textInput = ""; textFocused = false
        if session.realtimeSession.isConnected {
            session.realtimeSession.sendText(t)
        } else {
            Task { await session.sendViaAnthropic(t) }
        }
    }
}

// MARK: - Mic button (4-state: idle / listening / speaking / muted)

struct MicButton: View {
    let realtimeSession: RealtimeSession

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30, paused:
            realtimeSession.isMuted ||
            realtimeSession.isStudentSpeaking ||
            realtimeSession.isTutorSpeaking
        )) { ctx in
            let t     = ctx.date.timeIntervalSinceReferenceDate
            let pulse = CGFloat((sin(t * .pi / 2.0) + 1) / 2)

            Button { realtimeSession.toggleMute() } label: {
                ZStack {
                    Circle()
                        .fill(glowColor.opacity(0.15 * pulse))
                        .frame(width: 84, height: 84)
                    Circle()
                        .fill(buttonGradient)
                        .frame(width: 62, height: 62)
                        .shadow(color: glowColor.opacity(0.28 + 0.18 * pulse),
                                radius: 8 + 10 * pulse, y: 4)
                    Image(systemName: realtimeSession.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(SpringButtonStyle())
        }
    }

    private var buttonGradient: LinearGradient {
        if realtimeSession.isMuted {
            return LinearGradient(colors: [Color(white: 0.55), Color(white: 0.45)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        if realtimeSession.isStudentSpeaking {
            return LinearGradient(colors: [Theme.amber, Theme.amberDeep],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        if realtimeSession.isTutorSpeaking {
            return LinearGradient(colors: [Theme.teal, Theme.tealDeep],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [Theme.navy, Theme.teal],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var glowColor: Color {
        realtimeSession.isTutorSpeaking ? Theme.teal : Theme.navy
    }
}

// MARK: - Waveform bars

struct WaveformBars: View {
    let isActive: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: !isActive)) { ctx in
            HStack(spacing: 3) {
                ForEach(0..<6, id: \.self) { i in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    let h: CGFloat = isActive
                        ? abs(CGFloat(sin(t * 5.0 + Double(i) * 1.1))) * 18 + 5 : 4
                    RoundedRectangle(cornerRadius: 2).fill(Theme.teal).frame(width: 3, height: h)
                }
            }
        }
        .frame(width: 34, height: 28)
    }
}

// MARK: - Spring button style

struct SpringButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - Transcript sheet

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
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
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

// MARK: - Settings sheet

struct SettingsSheet: View {
    @Environment(TutorSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var openAIKey    = Keychain.readOpenAI() ?? ""
    @State private var anthropicKey = Keychain.read() ?? ""
    @State private var saved        = false

    var body: some View {
        @Bindable var session = session

        NavigationStack {
            Form {
                Section {
                    SecureField("sk-…", text: $openAIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 14, design: .monospaced))
                } header: {
                    Text("OpenAI API Key")
                } footer: {
                    Text("Used for real-time voice mode. Get a key at platform.openai.com. Stored in your iOS Keychain.")
                }

                Section {
                    SecureField("sk-ant-…", text: $anthropicKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 14, design: .monospaced))
                } header: {
                    Text("Anthropic API Key (text fallback)")
                } footer: {
                    Text("Used when Realtime is not connected. Get a key at console.anthropic.com.")
                }

                Section {
                    Picker("Voice", selection: Binding(
                        get: { session.synth.gender },
                        set: { session.synth.gender = $0 }
                    )) {
                        ForEach(VoiceGender.allCases, id: \.rawValue) { g in
                            Text(g == .female ? "Girl" : "Boy").tag(g)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Fallback Voice")
                } footer: {
                    Text("Voice used when falling back to the Anthropic text pipeline.")
                }

                Section {
                    Toggle("Hands-free (text mode)", isOn: $session.handsFree)
                } header: {
                    Text("Conversation")
                }

                Section {
                    Button {
                        Keychain.saveOpenAI(openAIKey)
                        Keychain.save(anthropicKey)
                        saved = true
                        session.realtimeSession.disconnect()
                        if !openAIKey.isEmpty {
                            session.realtimeSession.connect()
                        }
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
                    Link("OpenAI platform",    destination: URL(string: "https://platform.openai.com")!)
                    Link("Anthropic console",  destination: URL(string: "https://console.anthropic.com")!)
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
