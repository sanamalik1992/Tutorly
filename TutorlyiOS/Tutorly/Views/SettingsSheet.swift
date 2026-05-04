import SwiftUI

struct SettingsSheet: View {
    @Environment(TutorSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var showProSheet = false
    @State private var showSignOutConfirm = false
    private var auth: AuthService { AuthService.shared }

    @State private var devKey: String = Keychain.read("openai") ?? ""
    @State private var devKeySaved: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                if let user = auth.currentUser {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(user.name)
                                        .font(.system(size: 16, weight: .semibold))
                                    if user.isPro {
                                        Text("PRO")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Theme.accent, in: Capsule())
                                    }
                                }
                                if let email = user.email {
                                    Text(email)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
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
                        if let user = auth.currentUser, user.sessionsRemaining >= 0 {
                            HStack {
                                Text("Free sessions remaining")
                                Spacer()
                                Text("\(user.sessionsRemaining)")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(user.sessionsRemaining == 0 ? .red : .secondary)
                            }
                        }
                    }
                }

                if Keychain.allowDevBypass {
                    Section("Dev (TestFlight / DEBUG only)") {
                        SecureField("OpenAI key (sk-…)", text: $devKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        HStack {
                            Button("Save") {
                                let trimmed = devKey.trimmingCharacters(in: .whitespacesAndNewlines)
                                if trimmed.isEmpty {
                                    Keychain.delete("openai")
                                } else {
                                    Keychain.save(trimmed, for: "openai")
                                }
                                devKey = trimmed
                                devKeySaved = true
                            }
                            Spacer()
                            if devKeySaved {
                                Text("Saved").font(.caption).foregroundStyle(.green)
                            }
                        }
                        Text("When set, RealtimeSession bypasses the backend session-start (and its free-limit gate) and connects to OpenAI directly. Visible in DEBUG and TestFlight builds — production App Store ignores this.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button(role: .destructive, action: { showSignOutConfirm = true }) {
                        HStack {
                            Spacer()
                            Text("Sign Out")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Sign out of Tutorly?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    session.disconnect()
                    auth.signOut()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .sheet(isPresented: $showProSheet) { ProView() }
    }
}
