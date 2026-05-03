import SwiftUI

struct SettingsSheet: View {
    @Environment(TutorSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var showProSheet = false

    var body: some View {
        NavigationStack {
            Form {
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
