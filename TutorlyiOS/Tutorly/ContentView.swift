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

            VStack(spacing: 14) {
                header
                modeAndSubjectBar
                Whiteboard()
                    .frame(maxHeight: .infinity)
                voiceBar
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
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

    // MARK: - Pieces

    private var backgroundGlow: some View {
        ZStack {
            Circle()
                .fill(Theme.navy.opacity(0.06))
                .frame(width: 400)
                .blur(radius: 80)
                .offset(x: -140, y: -220)
            Circle()
                .fill(Theme.teal.opacity(0.10))
                .frame(width: 420)
                .blur(radius: 90)
                .offset(x: 160, y: 240)
        }
    }

    private var header: some View {
        @Bindable var session = session
        return HStack(spacing: 12) {
            // Brand mark
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.brandGradient)
                    .frame(width: 38, height: 38)
                    .shadow(color: Theme.navy.opacity(0.25), radius: 6, x: 0, y: 2)
                Text("T")
                    .font(.serif(20, weight: .heavy))
                    .foregroundStyle(Theme.paper)
                // Tassel dot
                Circle()
                    .fill(Theme.amber)
                    .frame(width: 6, height: 6)
                    .offset(x: 11, y: -11)
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
                Text("Your AI study buddy")
                    .font(.mono(9, weight: .medium))
                    .kerning(1.5)
                    .foregroundStyle(Theme.inkFaint)
                    .textCase(.uppercase)
            }

            Spacer()

            // Hands-free toggle
            Toggle(isOn: $session.handsFree) {
                Text("Hands-free")
                    .font(.mono(10, weight: .semibold))
                    .kerning(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.inkSoft)
            }
            .toggleStyle(CompactToggleStyle())

            Button { showTranscript = true } label: {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 34, height: 34)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
            }

            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 34, height: 34)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
            }
        }
        .padding(.top, 8)
    }

    private var modeAndSubjectBar: some View {
        @Bindable var session = session
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                // Mode segmented
                HStack(spacing: 0) {
                    modeButton(.teach)
                    modeButton(.quiz)
                }
                .background(Theme.paper)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.ink, lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: 220)

                // Subject input
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
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Quick-start chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(quickSubjects, id: \.self) { s in
                        Button { session.startPresetSession(s) } label: {
                            Text(s)
                                .font(.mono(11, weight: .medium))
                                .kerning(0.8)
                                .foregroundStyle(Theme.inkSoft)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(Theme.line, lineWidth: 1)
                                )
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
                .font(.serif(14, weight: .semibold))
                .foregroundStyle(active ? Theme.paper : Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(active ? Theme.ink : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private var voiceBar: some View {
        @Bindable var session = session
        return VStack(spacing: 8) {
            // Status line
            HStack(spacing: 8) {
                statusTag
                Text(statusText)
                    .font(.serif(14))
                    .italic()
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(2)
                Spacer()
            }
            .frame(minHeight: 20)

            // Mic + text input row
            HStack(spacing: 12) {
                // Mic button
                Button {
                    if session.synth.isSpeaking { session.stopSpeaking(); return }
                    if session.recognizer.isListening { session.stopListening(); return }
                    session.startListening()
                } label: {
                    ZStack {
                        Circle()
                            .fill(micGradient)
                            .frame(width: 60, height: 60)
                            .shadow(color: micShadow, radius: 10, y: 4)
                        Image(systemName: micIcon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .scaleEffect(session.recognizer.isListening ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                               value: session.recognizer.isListening)
                }
                .disabled(session.isThinking)

                // Text fallback
                HStack(spacing: 6) {
                    TextField("Or type your question…", text: $textInput)
                        .font(.system(size: 14))
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
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var statusTag: some View {
        Group {
            if session.isThinking {
                tag("THINKING", color: Theme.navy)
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
            .kerning(1.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var statusText: String {
        if session.isThinking { return "working it out…" }
        if session.recognizer.isListening {
            return session.recognizer.interim.isEmpty ? "go ahead, I'm listening…" : session.recognizer.interim
        }
        if session.synth.isSpeaking { return "tap mic to interrupt" }
        if session.messages.isEmpty { return "Tap the mic or pick a subject to begin." }
        if session.handsFree { return "Hands-free on — I'll listen when I finish." }
        return "Tap the mic to reply."
    }

    private var micIcon: String {
        if session.recognizer.isListening { return "stop.fill" }
        if session.synth.isSpeaking { return "waveform" }
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
        if session.synth.isSpeaking { return Theme.teal.opacity(0.5) }
        return Theme.navy.opacity(0.3)
    }

    private func sendText() {
        let t = textInput
        textInput = ""
        textFocused = false
        Task { await session.send(t) }
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
                            Text("No conversation yet")
                                .font(.serif(20)).italic()
                                .foregroundStyle(Theme.inkFaint)
                            Text("Pick a subject, or tap the mic and start talking.")
                                .font(.system(size: 13))
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
                                .font(.system(size: 15))
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
                    }
                }
                .padding()
            }
            .background(Theme.bg)
            .navigationTitle("Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        session.newSession()
                        dismiss()
                    }
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
                    Text("Anthropic API key")
                } footer: {
                    Text("Stored securely in your iOS Keychain — never leaves your device except to call the Anthropic API. Get a key at console.anthropic.com.")
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
                            Text(saved ? "Saved ✓" : "Save key")
                                .font(.system(size: 15, weight: .semibold))
                            Spacer()
                        }
                    }
                    .disabled(apiKey.isEmpty)
                }

                Section {
                    Link("Get an API key", destination: URL(string: "https://console.anthropic.com")!)
                    Link("Privacy: how this works", destination: URL(string: "https://www.anthropic.com/privacy")!)
                }

                Section {
                    Text("Tutorly is a voice tutor that explains concepts and quizzes you, with a live whiteboard the tutor draws on to illustrate ideas. Try maths — you'll see it sketching solutions step by step.")
                        .font(.system(size: 13))
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
