/// This view lets the user configure the primary graph's append-only API token.
/// `SettingsHome` presents it from Graph Settings. The token is stored securely
/// by `CredentialsManager`, which also lets pending captures retry after the
/// credential changes.

import SwiftUI

struct SettingApiToken: View {
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
                        Image(systemName: "key")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.white)
                            .offset(x: 1, y: -1)
                    }
                    .padding(.top)

                    Text("Append API Token")
                        .font(.title2)
                        .bold()
                        .multilineTextAlignment(.center)

                    Text("We need an API token to connect and send notes to your Roam Research graph.")
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

                Text("You can generate a new API Token in Roam Research via Settings > Graph. When asked for Access Scope, select **append-only access**.\n\n**Tip:** For easy copy/paste, copy the API Token from your Mac and the clipboard should be shared with your iPhone. Tap and hold in the field above and select Paste.")
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
            isConfigured = CredentialsManager.shared.hasPrimaryAppendToken
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
                try await CredentialsManager.shared.savePrimaryAppendToken(newToken, context: context)
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
        SettingApiToken(viewModel: ProfileViewModel())
    }
}
