/// This view edits the name of the user's primary Roam graph.
/// `SettingsHome` presents it from Graph Settings and passes the shared
/// `ProfileViewModel`. Saving writes the name to the SwiftData profile used when
/// captures are routed to the primary graph.

import SwiftUI

struct SettingGraph: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ProfileViewModel

    var body: some View {
        ScrollView {
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

                    Text("Graph Name")
                        .font(.title2)
                        .bold()
                        .multilineTextAlignment(.center)

                    Text("Tell us the name of your Roam Research graph where we will send new notes.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
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
                        .onSubmit {
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
                    .padding(.horizontal)
                
                Spacer()
                
            }
            .padding()
        }
        .background(Color(.secondarySystemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    try? viewModel.saveChanges(context: context)
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingGraph(viewModel: ProfileViewModel())
    }
}
