import SwiftUI

struct SettingsSheet: View {
    @Environment(TutorSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = Keychain.read("openai") ?? ""
    @State private var saved = false
    @State private var showProSheet = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-...", text: $apiKey)
                        .font(.system(size: 14, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: { Text("OpenAI API Key") }
                  footer: { Text("Stored in iOS Keychain on your device only. Never sent anywhere except to OpenAI's Realtime API.") }

                Section {
                    Button {
                        Keychain.save(apiKey, for: "openai")
                        saved = true
                        Task {
                            try? await Task.sleep(nanoseconds: 600_000_000)
                            session.connect()
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text(saved ? "Saved ✓" : "Save & Connect").bold()
                            Spacer()
                        }
                    }
                    .disabled(apiKey.isEmpty)
                }

                Section {
                    Link("Get a key at console.openai.com",
                         destination: URL(string: "https://platform.openai.com/api-keys")!)
                }

                Section("Subscription") {
                    if ProService.shared.isPro {
                        Label("Tutorly Pro — Active", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button(action: { showProSheet = true }) {
                            Label("Upgrade to Pro", systemImage: "sparkles")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }

                Section {
                    Button(role: .destructive, action: {
                        session.disconnect()
                        AuthService.shared.signOut()
                        dismiss()
                    }) {
                        HStack {
                            Spacer()
                            Text("Sign Out")
                            Spacer()
                        }
                    }
                }
            }
            .onAppear { apiKey = Keychain.read("openai") ?? "" }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showProSheet) { ProView() }
    }
}
