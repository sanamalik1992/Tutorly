import SwiftUI

struct SettingsSheet: View {
    @Environment(TutorSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var showProSheet = false
    @State private var showSignOutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var showDeleteError = false
    @State private var storeKit = StoreKitManager.shared
    @AppStorage("aiConsentGiven") private var aiConsentGiven = false
    private var auth: AuthService { AuthService.shared }

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
                    if storeKit.isInTrial {
                        Label(trialStatusLabel, systemImage: "gift.fill")
                            .foregroundStyle(Theme.accent)
                        if let user = auth.currentUser, user.sessionsRemaining >= 0 {
                            HStack {
                                Text("Sessions left today")
                                Spacer()
                                Text("\(user.sessionsRemaining) of 3")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(user.sessionsRemaining == 0 ? .red : .secondary)
                            }
                        }
                        Text("Cancel in Settings → Apple ID → Subscriptions before your trial ends to avoid being charged.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else if ProService.shared.isPro {
                        Label("Tutorly Pro — Active", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button(action: { showProSheet = true }) {
                            Label("Start Free Trial", systemImage: "sparkles")
                                .foregroundStyle(Theme.accent)
                        }
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

                // Account deletion — required by Apple Guideline 5.1.1(v)
                Section("Account") {
                    if isDeleting {
                        HStack(spacing: 12) {
                            ProgressView().tint(.red)
                            Text("Deleting account…")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 15))
                        }
                    } else {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Text("Delete Account")
                        }
                        .disabled(isDeleting)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .disabled(isDeleting)
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
            .confirmationDialog("Delete account?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete Account", role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete your account and all associated data. This action cannot be undone.")
            }
            .alert("Couldn't delete account", isPresented: $showDeleteError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please check your connection and try again, or contact support at tutorlyAI_app@outlook.com.")
            }
        }
        .sheet(isPresented: $showProSheet) { ProView() }
    }

    // MARK: - Helpers

    private var trialStatusLabel: String {
        let days = storeKit.trialDaysRemaining
        if days <= 0 { return "Free Trial — last day" }
        return days == 1 ? "Free Trial — 1 day remaining" : "Free Trial — \(days) days remaining"
    }

    // MARK: - Delete account

    private func deleteAccount() async {
        guard let jwt = Keychain.appJwt() else {
            await MainActor.run { showDeleteError = true }
            return
        }

        await MainActor.run { isDeleting = true }

        do {
            guard let url = URL(string: "https://tutorly-backend-omega.vercel.app/api/user/delete") else {
                await MainActor.run { isDeleting = false; showDeleteError = true }
                return
            }
            var req = URLRequest(url: url, timeoutInterval: 15)
            req.httpMethod = "DELETE"
            req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                await MainActor.run { isDeleting = false; showDeleteError = true }
                return
            }

            // Success — clear all local state, reset consent, sign out
            await MainActor.run {
                aiConsentGiven = false
                session.disconnect()
                auth.signOut()
                // isDeleting stays true until the view disappears with the session
            }
            print("[Auth] account deleted successfully")

        } catch {
            await MainActor.run { isDeleting = false; showDeleteError = true }
            print("[Auth] account deletion error: \(error.localizedDescription)")
        }
    }
}
