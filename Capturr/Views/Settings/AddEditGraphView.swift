/// This view creates or edits an additional Roam graph and its append token.
/// `ManageGraphsView` presents it as a sheet for new graphs and as a destination
/// for existing ones. It saves graph details through `ProfileViewModel` and keeps
/// each graph's token in the Keychain through `CredentialsManager`.

import SwiftUI

struct AddEditGraphView: View {
    // MARK: - State

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ProfileViewModel

    let existingGraph: AdditionalGraph?

    @State private var graphName: String = ""
    @State private var apiToken: String = ""
    @State private var showDeleteConfirmation = false
    @State private var hasExistingToken = false

    private var isEditing: Bool { existingGraph != nil }

    // MARK: - Validation

    private var isValid: Bool {
        let trimmedName = graphName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return false }
        guard viewModel.isGraphNameUnique(trimmedName, excludingId: existingGraph?.id) else { return false }
        // An empty token keeps the saved Keychain token when editing, but a new graph needs one.
        if !isEditing && apiToken.isEmpty { return false }
        return true
    }

    private var nameValidationMessage: String? {
        let trimmedName = graphName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return nil }
        if !viewModel.isGraphNameUnique(trimmedName, excludingId: existingGraph?.id) {
            return "Name must be unique"
        }
        return nil
    }

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

                    Text(isEditing ? "Edit Graph" : "Add Graph")
                        .font(.title2)
                        .bold()
                        .multilineTextAlignment(.center)

                    Text("Configure an additional Roam Research graph to send captures to.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.bottom, 15)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Graph Name")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Enter graph name", text: $graphName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .keyboardType(.asciiCapable)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        if let message = nameValidationMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Append API Token")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            if isEditing && hasExistingToken {
                                HStack {
                                    Text("Token configured")
                                        .foregroundColor(.green)
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                                .font(.caption)
                            }
                        }

                        TextField(
                            isEditing && hasExistingToken ? "Enter new token to replace..." : "Enter API token...",
                            text: $apiToken
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.asciiCapable)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.horizontal)
                }
                .padding()
                .padding(.bottom, 15)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Spacer()
            }
            .padding()
            .padding(.bottom, 25)
        }
        .background(Color(.secondarySystemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if !isEditing {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            
            if isEditing {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
                
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveGraph()
                }
                .disabled(!isValid)
            }
        }
        .onAppear {
            if let graph = existingGraph {
                graphName = graph.name
                hasExistingToken = CredentialsManager.shared.hasAppendToken(forGraphId: graph.id)
            }
        }
        .alert("Delete Graph?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteGraph()
            }
        } message: {
            Text("This will remove the graph configuration. Any pending captures for this graph will fail.")
        }
    }

    // MARK: - Actions

    private func saveGraph() {
        let trimmedName = graphName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        if let existing = existingGraph {
            // Replace the value in the published array so observers receive the edited name.
            var graphs = viewModel.additionalGraphs
            if let index = graphs.firstIndex(where: { $0.id == existing.id }) {
                graphs[index].name = trimmedName
                viewModel.additionalGraphs = graphs
            }

            // Leaving this blank intentionally preserves the existing Keychain token.
            if !apiToken.isEmpty {
                Task {
                    try? await CredentialsManager.shared.saveGraphAppendToken(apiToken, graphId: existing.id, context: context)
                }
            }
        } else {
            let newGraph = AdditionalGraph(name: trimmedName)
            viewModel.additionalGraphs.append(newGraph)

            // Graph tokens live in Keychain rather than the SwiftData profile.
            Task {
                try? await CredentialsManager.shared.saveGraphAppendToken(apiToken, graphId: newGraph.id, context: context)
            }
        }

        try? viewModel.saveChanges(context: context)
        dismiss()
    }

    private func deleteGraph() {
        guard let graph = existingGraph else { return }

        viewModel.additionalGraphs.removeAll { $0.id == graph.id }

        // Remove the separately stored credential along with the graph configuration.
        Task {
            try? await CredentialsManager.shared.deleteGraphAppendToken(graphId: graph.id)
        }

        // Capture screens must fall back to the primary graph after this destination disappears.
        if viewModel.lastUsedGraphId == graph.id {
            viewModel.lastUsedGraphId = nil
        }

        try? viewModel.saveChanges(context: context)
        dismiss()
    }
}

#Preview("Add") {
    NavigationStack {
        AddEditGraphView(viewModel: ProfileViewModel(), existingGraph: nil)
    }
}

#Preview("Edit") {
    NavigationStack {
        AddEditGraphView(
            viewModel: ProfileViewModel(),
            existingGraph: AdditionalGraph(id: "test-id", name: "Test Graph")
        )
    }
}
