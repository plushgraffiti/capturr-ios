/// This view coordinates the three-page first-run setup flow.
/// `CapturrApp` presents it as a full-screen cover when onboarding has not been
/// completed or has been reset in Settings. Each child page calls back to advance,
/// and dismissing the cover lets the app record onboarding as seen.

import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ProfileViewModel
    @State private var currentPage = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $currentPage) {
                OnboardingGraph(viewModel: viewModel, onNext: { currentPage = 1 }).tag(0)
                OnboardingToken(viewModel: viewModel, onNext: { currentPage = 2 }).tag(1)
                OnboardingPermissions(onNext: { dismiss() }).tag(2)
            }
            .background(Color(.secondarySystemBackground))
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
            .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))

            Button(
                action: {
                    dismiss()
                }
            ) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .padding()
                
            }
            .accessibilityLabel("Close onboarding")
            .foregroundStyle(.secondary)
            .padding()
        }
    }

}

#Preview {
    OnboardingView(viewModel: ProfileViewModel())
}
