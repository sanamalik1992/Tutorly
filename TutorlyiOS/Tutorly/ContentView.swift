import SwiftUI

struct ContentView: View {
    @Environment(TutorSession.self) private var session
    @State private var textInput: String = ""
    @State private var showSettings = false
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

            VStack(spacing: 12) {
                header
                modeAndSubjectBar
                Whiteboard()
                    .frame(maxHeight: .infinity)
                voiceBar
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .sheet(isPresented: $showTranscript) { TranscriptSheet() }
        .alert("Error",
               isPresented: Binding(
                get: { session.errorMessage != nil },
                set: { if !$0 { session.errorMessage = nil } })
        ) {
            Button("OK") { session.errorMessage = nil }
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    // MARK: - Background

    private var backgroundGlow: some View {
        ZStack {
            Circle()
                .fill(Theme.navy.opacity(0.07))
                .frame(width: 500)
                .blur(radius: 90)
                .offset(x: -160, y: -260)
            Circle()
                .fill(Theme.teal.opacity(0.09))
                .frame(width: 420)
                .blur(radius: 80)
                .offset(x: 180, y: 260)
            Circle()
                .fill(Theme.amber.opacity(0.06))
                .frame(width: 320)
                .blur(radius: 70)
                .offset(x: 40, y: 80)
        }
    }

    // MARK: - Header

    private var header: some View {
        @Bindable var session = session
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.brandGradient)
                    .frame(width: 40, height: 40)
                    .shadow(color: Theme.navy.opacity(0.3), radius: 8, x: 0, y: 3)
                Text("T")
                    .font(.serif(21, weight: .heavy))
                    .foregroundStyle(Theme.paper)
                Circle()
                    .fill(Theme.amber)
                    .frame(width: 6, height: 6)
                    .offset(x: 12, y: -12)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 1) {
                    Text("Tutor")
                        .font(.serif(24, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("ly")
                        .font(.serif(24, weight: .regular))
                        .italic()
                        .foregroundStyle(Theme.navy)
                    Text(".")
                        .font(.serif(24, weight: .heavy))
                        .foregroundStyle(Theme.amber)
                }
                Text("let's learn together")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.inkFaint)
            }

            Spacer()

            Toggle(isOn: $session.handsFree) {
                Text("Hands-free")
                    .font(.mono(10, weight: .semibold))
                    .kerning(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.inkSoft)
            }
            .toggleStyle(CompactToggleStyle())

            Button { showTranscript = true } label: {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 34, height: 34)
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.line))
            }

            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 34, height: 34)
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.line))
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Mode + subject bar

    private var modeAndSubjectBar: some View {
        @Bindable var session = session
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 0) {
                    modeButton(.teach)
                    modeButton(.quiz)
                }
                .background(Theme.paper)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.ink, lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: 220)

                HStack(spacing: 8) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkFaint)
                    TextField("Subject or topic…", text: $session.subject)
                        .font(.system(size: 14))
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.paper)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(quickSubjects, id: \.self) { s in
                        let active = session.subject == s
                        Button { session.startPresetSession(s) } label: {
                            Text(s)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(active ? Theme.paper : Theme.inkSoft)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 7)
                                .background(active ? Theme.navy : Color.clear)
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(active ? Theme.navy : Theme.line, lineWidth: 1))
                        }
                    }
                }
            }
        }
    }

    private func modeButton(_ m: TutorMode) -> some View {
        @Bindable var session = session
        let active = session.mode == m
        return Button { session.mode = m } label: {
            Text(m.label)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(active ? Theme.paper : Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(active ? Theme.ink : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Voice bar

    private var voiceBar: some View {
        @Bindable var session = session
        return VStack(spacing: 10) {
            // Status row
            HStack(spacing: 8) {
                statusTag
                if session.synth.isSpeaking {
                    WaveformBars(isActive: true)
                }
                Text(statusText)
                    .font(.system(size: 14, design: .rounded))
                    .italic()
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(2)
                Spacer()
            }
            .frame(minHeight: 28)

            // Controls row
            HStack(spacing: 10) {
                // Voice gender picker
                HStack(spacing: 4) {
                    ForEach(VoiceGender.allCases, id: \.rawValue) { g in
                        Button { session.synth.gender = g } label: {
                            VStack(spacing: 2) {
                                Text(g == .female ? "♀" : "♂")
                                    .font(.system(size: 15, weight: .bold))
                                Text(g.label)
                                    .font(.system(size: 8, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(session.synth.gender == g ? Theme.paper : Theme.inkSoft)
                            .frame(width: 42, height: 42)
                            .background(
                                session.synth.gender == g
                                ? AnyShapeStyle(Theme.brandGradient)
                                : AnyShapeStyle(Theme.bgDeep)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                // Mic button
                Button {
                    if session.synth.isSpeaking  { session.stopSpeaking();  return }
                    if session.recognizer.isListening { session.stopListening(); return }
                    session.startListening()
                } label: {
                    ZStack {
                        Circle()
                            .fill(micGradient)
                            .frame(width: 64, height: 64)
                            .shadow(color: micShadow, radius: 12, y: 5)
                        Image(systemName: micIcon)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .scaleEffect(session.recognizer.isListening ? 1.1 : 1.0)
                    .animation(
                        session.recognizer.isListening
                        ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                        : .spring(response: 0.3),
                        value: session.recognizer.isListening
                    )
                }
                .disabled(session.isThinking)

                // Text input
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
                        .disabled(session.isThinking)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.paper)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var statusTag: some View {
        Group {
            if session.isThinking {
                pulsingTag("THINKING", color: Theme.navy)
            } else if session.recognizer.isListening {
                tag("LISTENING", color: Theme.amberDeep)
            } else if session.synth.isSpeaking {
                tag("SPEAKING", color: Theme.tealDeep)
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

    private func pulsingTag(_ text: String, color: Color) -> some View {
        tag(text, color: color)
            .modifier(PulseModifier())
    }

    private var statusText: String {
        if session.isThinking { return "on it..." }
        if session.recognizer.isListening {
            return session.recognizer.interim.isEmpty ? "go ahead, I'm listening..." : session.recognizer.interim
        }
        if session.synth.isSpeaking { return "tap mic to jump in" }
        if session.messages.isEmpty { return "Tap the mic or pick a subject to get started!" }
        if session.handsFree { return "hands-free on — mic restarts after I'm done" }
        return "tap the mic to reply"
    }

    private var micIcon: String {
        if session.recognizer.isListening { return "stop.fill" }
        if session.synth.isSpeaking      { return "waveform" }
        return "mic.fill"
    }

    private var micGradient: LinearGradient {
        if session.recognizer.isListening {
            return LinearGradient(colors: [Theme.amber, Theme.amberDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        if session.synth.isSpeaking {
            return LinearGradient(colors: [Theme.teal, Theme.tealDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [Theme.navy, Theme.teal], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var micShadow: Color {
        if session.recognizer.isListening { return Theme.amber.opacity(0.5) }
        if session.synth.isSpeaking       { return Theme.teal.opacity(0.5) }
        return Theme.navy.opacity(0.3)
    }

    private func sendText() {
        let t = textInput
        textInput = ""
        textFocused = false
        Task { await session.send(t) }
    }
}

// MARK: - Waveform bars (speaking indicator)

struct WaveformBars: View {
    let isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !isActive)) { ctx in
            HStack(spacing: 3) {
                ForEach(0..<6, id: \.self) { i in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    let h: CGFloat = isActive
                        ? abs(CGFloat(sin(t * 5.0 + Double(i) * 1.1))) * 18 + 5
                        : 4
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.teal)
                        .frame(width: 3, height: h)
                }
            }
        }
        .frame(width: 34, height: 28)
    }
}

// MARK: - Pulsing animation modifier

struct PulseModifier: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on ? 1.0 : 0.55)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) { on = true }
            }
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
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .padding(2)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
            }
            .animation(.easeInOut(duration: 0.2), value: configuration.isOn)
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
                VStack(alignment: .leading, spacing: 12) {
                    if session.messages.isEmpty {
                        VStack(spacing: 10) {
                            Text("Nothing yet")
                                .font(.serif(20)).italic()
                                .foregroundStyle(Theme.inkFaint)
                            Text("Pick a subject or tap the mic to get started.")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(Theme.inkFaint)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }
                    ForEach(session.messages) { m in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(m.role == .user ? "YOU" : "TUTORLY")
                                .font(.mono(9, weight: .bold))
                                .kerning(1.2)
                                .foregroundStyle(Theme.inkFaint)
                            Text(m.content)
                                .font(.system(size: 15, design: .rounded))
                                .foregroundStyle(Theme.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(m.role == .assistant ? Theme.navy.opacity(0.03) : Theme.paper)
                        .overlay(
                            Rectangle()
                                .fill(m.role == .assistant ? Theme.navy : Theme.teal)
                                .frame(width: 2),
                            alignment: .leading
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding()
            }
            .background(Theme.bg)
            .navigationTitle("Conversation")
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
    @State private var apiKey: String = Keychain.read() ?? ""
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-…", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 14, design: .monospaced))
                } header: {
                    Text("Anthropic API Key")
                } footer: {
                    Text("Stored securely in your iOS Keychain — never committed to source control. Get a key at console.anthropic.com.")
                }

                Section {
                    Picker("Voice", selection: Binding(
                        get: { session.synth.gender },
                        set: { session.synth.gender = $0 }
                    )) {
                        ForEach(VoiceGender.allCases, id: \.rawValue) { g in
                            Text(g == .female ? "Girl (friendly female voice)" : "Boy (friendly male voice)")
                                .tag(g)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("Tutor Voice")
                } footer: {
                    Text("You can also switch voices instantly using the girl/boy buttons next to the mic.")
                }

                Section {
                    Button {
                        Keychain.save(apiKey)
                        saved = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_200_000_000)
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text(saved ? "Saved" : "Save Key")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Spacer()
                        }
                    }
                    .disabled(apiKey.isEmpty)
                }

                Section {
                    Link("Get an API key", destination: URL(string: "https://console.anthropic.com")!)
                }

                Section {
                    Text("Tutorly is a voice AI tutor with a live whiteboard. Speak your question, and the tutor explains it out loud while drawing diagrams and working through problems step by step.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Theme.inkFaint)
                } header: {
                    Text("About")
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
    ContentView()
        .environment(TutorSession())
}
