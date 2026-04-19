import SwiftUI

struct ContentView: View {
    @Environment(TutorSession.self) private var session
    @State private var textInput = ""
    @State private var showSettings  = false
    @State private var showTranscript = false
    @FocusState private var textFocused: Bool

    private let quickSubjects = [
        "Algebra", "Calculus", "Physics", "Chemistry",
        "Biology", "History", "Essays", "Python"
    ]

    var body: some View {
        @Bindable var session = session

        ZStack {
            Theme.bg.ignoresSafeArea()
            backgroundGlow.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 10)

                controlsBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                Whiteboard()
                    .padding(.horizontal, 16)
                    .frame(maxHeight: .infinity)

                voiceBar
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showSettings)  { SettingsSheet() }
        .sheet(isPresented: $showTranscript) { TranscriptSheet() }
        .alert("Error", isPresented: Binding(
            get: { session.errorMessage != nil || session.realtimeSession.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil; session.realtimeSession.errorMessage = nil } }
        )) {
            Button("OK") { session.errorMessage = nil; session.realtimeSession.errorMessage = nil }
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

    // MARK: - Header (brand + icons only — no toggles)

    private var header: some View {
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
                    Text("Tutor").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                    Text("ly").font(.system(size: 22, weight: .regular, design: .rounded)).italic().foregroundStyle(Theme.navy)
                    Text(".").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(Theme.amber)
                }
                Text("let's learn together")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.inkFaint)
            }

            Spacer()

            // Connection dot
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
    }

    // MARK: - Controls bar (mode, subject, chips — all full-width, no clipping)

    private var controlsBar: some View {
        @Bindable var session = session
        return VStack(spacing: 8) {
            // Row 1: mode toggle — full width
            HStack(spacing: 0) {
                modeButton(.teach)
                modeButton(.quiz)
            }
            .frame(maxWidth: .infinity)
            .background(Theme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.ink, lineWidth: 1.5))

            // Row 2: subject input — full width
            HStack(spacing: 8) {
                Image(systemName: "book.closed")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
                TextField("Subject or topic…", text: $session.subject)
                    .font(.system(size: 14, design: .rounded))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))

            // Row 3: scrolling chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(quickSubjects, id: \.self) { s in
                        let active = session.subject == s
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                session.startPresetSession(s)
                            }
                        } label: {
                            Text(s)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(active ? Theme.paper : Theme.inkSoft)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(active ? Theme.navy : Color.clear)
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(active ? Theme.navy : Theme.line))
                        }
                        .buttonStyle(SpringButtonStyle())
                    }
                }
                .padding(.horizontal, 1)
            }
        }
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

    // MARK: - Voice bar

    private var voiceBar: some View {
        let rs = session.realtimeSession

        return VStack(spacing: 10) {
            // Status row
            HStack(spacing: 8) {
                statusTag
                if rs.isTutorSpeaking { WaveformBars(isActive: true) }
                Text(statusText)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 28)

            HStack(spacing: 10) {
                // Mute / unmute button (mic always on via Realtime; this just mutes input)
                MuteMicButton(realtimeSession: rs)

                // Text input fallback
                HStack(spacing: 6) {
                    TextField("Or type here…", text: $textInput)
                        .font(.system(size: 14, design: .rounded))
                        .focused($textFocused)
                        .submitLabel(.send)
                        .onSubmit(sendText)
                    if !textInput.isEmpty {
                        Button(action: sendText) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(Theme.navy)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: - Status helpers

    private var statusTag: some View {
        let rs = session.realtimeSession
        return Group {
            if !rs.isConnected {
                tag("OFFLINE", color: Theme.inkFaint)
            } else if rs.isStudentSpeaking {
                tag("LISTENING", color: Theme.amberDeep)
            } else if rs.isTutorSpeaking {
                tag("SPEAKING", color: Theme.tealDeep)
            } else if rs.isMuted {
                tag("MUTED", color: Theme.inkFaint)
            } else {
                EmptyView()
            }
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
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
        if !rs.isConnected    { return "Add your OpenAI key in Settings to start." }
        if rs.isMuted         { return "Muted — tap to unmute." }
        if rs.isStudentSpeaking { return "Go ahead, I'm listening…" }
        if rs.isTutorSpeaking { return "Tap the mic button to cut in." }
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

// MARK: - Mute mic button with idle pulse glow

struct MuteMicButton: View {
    let realtimeSession: RealtimeSession

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30, paused:
            realtimeSession.isMuted ||
            realtimeSession.isStudentSpeaking ||
            realtimeSession.isTutorSpeaking
        )) { ctx in
            let t     = ctx.date.timeIntervalSinceReferenceDate
            let pulse = CGFloat((sin(t * .pi / 2.0) + 1) / 2) // 0→1→0 every 4s

            Button { realtimeSession.toggleMute() } label: {
                ZStack {
                    // Idle glow ring
                    Circle()
                        .fill(glowColor.opacity(0.15 * pulse))
                        .frame(width: 84, height: 84)
                    Circle()
                        .fill(buttonGradient)
                        .frame(width: 64, height: 64)
                        .shadow(color: glowColor.opacity(0.28 + 0.18 * pulse),
                                radius: 8 + 10 * pulse, y: 4)
                    Image(systemName: realtimeSession.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 24, weight: .semibold))
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

// MARK: - Custom toggle

struct CompactToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(configuration.isOn ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.line))
                    .frame(width: 30, height: 18)
                Circle().fill(.white).frame(width: 14, height: 14).padding(2)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: configuration.isOn)
        }
        .onTapGesture { configuration.isOn.toggle() }
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
                        Text("Nothing yet — start a voice conversation.")
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
                        .overlay(Rectangle().fill(m.role == .assistant ? Theme.navy : Theme.teal).frame(width: 2), alignment: .leading)
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
                    Button("Clear") { session.newSession(); dismiss() }.foregroundStyle(Theme.inkSoft)
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

    @State private var openAIKey: String  = Keychain.readOpenAI() ?? ""
    @State private var anthropicKey: String = Keychain.read() ?? ""
    @State private var saved = false

    var body: some View {
        @Bindable var session = session

        NavigationStack {
            Form {
                // OpenAI key (Realtime voice)
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

                // Anthropic key (fallback / text mode)
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

                // Voice
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

                // Conversation
                Section {
                    Toggle("Hands-free (text mode)", isOn: $session.handsFree)
                } header: {
                    Text("Conversation")
                } footer: {
                    Text("Restarts the mic automatically after each reply in text mode. In voice mode, the mic is always live.")
                }

                // Save
                Section {
                    Button {
                        Keychain.saveOpenAI(openAIKey)
                        Keychain.save(anthropicKey)
                        saved = true
                        session.realtimeSession.disconnect()
                        session.realtimeSession.connect()
                        Task {
                            try? await Task.sleep(nanoseconds: 1_200_000_000)
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text(saved ? "Saved — reconnecting" : "Save & Connect")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Spacer()
                        }
                    }
                    .disabled(openAIKey.isEmpty && anthropicKey.isEmpty)
                }

                Section {
                    Link("OpenAI platform", destination: URL(string: "https://platform.openai.com")!)
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
