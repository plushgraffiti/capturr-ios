/// This view collects the primary Roam graph name during onboarding.
/// `OnboardingView` presents it as the first page and supplies the shared
/// `ProfileViewModel`. It saves the name to the SwiftData profile before asking
/// the parent flow to advance to API-token setup.

import SwiftUI

struct OnboardingGraph: View {
    @Environment(\.modelContext) private var context
    @ObservedObject var viewModel: ProfileViewModel
    let onNext: () -> Void
    
    private var isGraphNameValid: Bool {
        !(viewModel.graphName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 80, height: 80)
                    Image(systemName: "chart.bar.xaxis")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.white)
                        .offset(x: 1, y: -1)
                }
                .padding(.top)

                Text("Setup: Graph Name")
                    .font(.title2)
                    .bold()
                    .multilineTextAlignment(.center)

                Text("To get started tell us the name of the Roam Research graph to send new notes.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .padding(.horizontal)
                
                HStack(spacing: 12) {
                    TextField("Not set", text: Binding(
                        get: { viewModel.graphName ?? "" },
                        set: { viewModel.graphName = $0 }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.asciiCapable)
                    .submitLabel(.done)
                    .onChange(of: viewModel.graphName, initial: false) { _, _ in
                        // Preserve typed text even if the user closes onboarding before tapping Next.
                        try? viewModel.saveChanges(context: context)
                    }
                    
                }
                .padding()
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("If you are unsure what your graph name is, it normally appears in top left corner of the Roam Research UI (depending on theme). If not, go to Settings > Graph")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)
            
            Spacer()
            
            Button {
                try? viewModel.saveChanges(context: context)
                onNext()
            } label: {
                Text("Next")
                    .frame(maxWidth: .infinity)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .padding(8)
            }
            .buttonStyle(.borderedProminent)
            .mask { RoundedRectangle(cornerRadius: 16, style: .continuous) }
            .disabled(!isGraphNameValid)
            .padding(.bottom, 60)
            
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }
        
}

#Preview {
    OnboardingGraph(viewModel: ProfileViewModel(), onNext: { })
}
