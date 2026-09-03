/// This view collects the append-only API token needed to send captures to Roam.
/// `OnboardingView` presents it after graph-name setup. It stores a newly entered
/// token in Keychain through `CredentialsManager`, or reuses an existing token,
/// before asking the parent flow to advance.

import SwiftUI

struct OnboardingToken: View {
    @Environment(\.modelContext) private var context
    @ObservedObject var viewModel: ProfileViewModel
    let onNext: () -> Void

    @State private var newToken: String = ""
    @State private var isConfigured: Bool = false

    private var canContinue: Bool {
        isConfigured || !newToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
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

                Text("Setup: API Token")
                    .font(.title2)
                    .bold()
                    .multilineTextAlignment(.center)

                Text("We need an API token to connect and send notes to your Roam Research graph.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                SecureField(
                    isConfigured ? "Enter new token to replace..." : "Enter your API token...",
                    text: $newToken
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.asciiCapable)
                .submitLabel(.done)
                .onSubmit { saveAndContinue() }
                .padding()

            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("You can generate a new API Token in Roam Research via Settings > Graph. When asked for Access Scope, select append-only.\n\n**Tip:** For easy copy/paste, copy the API Token from your Mac and the clipboard should be shared with your iPhone. Tap and hold in the field above and select Paste.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .padding(.horizontal)

            Spacer()

            Button {
                saveAndContinue()
            } label: {
                Text("Next")
                    .frame(maxWidth: .infinity)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .padding(8)
            }
            .buttonStyle(.borderedProminent)
            .mask { RoundedRectangle(cornerRadius: 16, style: .continuous) }
            .disabled(!canContinue)
            .padding(.bottom, 60)

        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .onAppear {
            isConfigured = CredentialsManager.shared.hasPrimaryAppendToken
        }
    }

    // Save a new secret to Keychain before advancing so capture setup is complete.
    private func saveAndContinue() {
        let trimmedToken = newToken.trimmingCharacters(in: .whitespacesAndNewlines)

        // A blank field means "keep the saved token," but only when one actually exists.
        guard !trimmedToken.isEmpty else {
            if isConfigured { onNext() }
            return
        }

        Task {
            do {
                try await CredentialsManager.shared.savePrimaryAppendToken(trimmedToken, context: context)
                await MainActor.run { onNext() }
            } catch {
                // Keep the form open so the user can retry without restarting onboarding.
            }
        }
    }
}

#Preview {
    OnboardingToken(viewModel: ProfileViewModel(), onNext: { })
}
