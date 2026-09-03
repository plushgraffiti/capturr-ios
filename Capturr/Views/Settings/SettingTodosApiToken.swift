/// This view configures the primary graph token used to read and update TODOs.
/// `SettingsHome` presents it while the TODO feature is enabled. The token is
/// stored securely by `CredentialsManager`, separately from the user's SwiftData
/// profile and the append-only capture token.

import SwiftUI

struct SettingTodosApiToken: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ProfileViewModel

    @State private var newToken: String = ""
    @State private var isConfigured: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                VStack(spacing: 16) {

                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 80, height: 80)
                        Image(systemName: "key.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.white)
                            .offset(x: 1, y: -1)
                    }
                    .padding(.top)

                    Text("Backend API Token")
                        .font(.title2)
                        .bold()
                        .multilineTextAlignment(.center)

                    Text("The Backend API token is required to fetch and update TODOs from your Roam Research graph.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    // Keep the saved secret out of the UI; only check whether its Keychain entry exists.
                    HStack {
                        Text("Status:")
                            .foregroundColor(.secondary)
                        if isConfigured {
                            Label("Configured", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Label("Not configured", systemImage:
                            "exclamationmark.circle.fill")
                                .foregroundColor(.orange)
                        }
                    }
                    .font(.subheadline)
                    .padding(.top, 8)

                    SecureField(
                        isConfigured ? "Enter new token to replace..." : "Enter your API token...",
                        text: $newToken
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.asciiCapable)
                    .submitLabel(.done)
                    .onSubmit {
                        saveToken()
                    }
                    .padding()

                }
                .padding()
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("You can generate a new Backend API Token in Roam Research via Settings > Graph. When asked for Access Scope, select **read & edit access**.\n\n**Tip:** For easy copy/paste, copy the API Token from your Mac and the clipboard should be shared with your iPhone. Tap and hold in the field above and select Paste.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal)

                Spacer()

            }
            .padding()
        }
        .background(Color(.secondarySystemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isConfigured = CredentialsManager.shared.hasPrimaryBackendToken
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveToken()
                }
                .disabled(newToken.isEmpty)
            }
        }
    }

    private func saveToken() {
        guard !newToken.isEmpty else { return }

        Task {
            do {
                try await CredentialsManager.shared.savePrimaryBackendToken(newToken, context: context)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                // Keep the form open so the user can retry without re-entering Settings.
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingTodosApiToken(viewModel: ProfileViewModel())
    }
}
