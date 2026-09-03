/// This view lists and manages the additional Roam graphs available for capture.
/// `SettingsHome` opens it after multi-graph capture is enabled, and it presents
/// `AddEditGraphView` to create or edit entries. It also controls whether quick
/// capture reuses the last selected graph.

import SwiftUI

struct ManageGraphsView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject var viewModel: ProfileViewModel

    @State private var showingAddGraph = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: $viewModel.multiGraphDefaultToLast) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default to Last Used Graph")
                    }
                }
                .onChange(of: viewModel.multiGraphDefaultToLast) {
                    try? viewModel.saveChanges(context: context)
                }
            } header: {
                Text("Quick Capture")
            } footer: {
                Text("When enabled: Single tap to send to last graph. Long press to choose a different graph. Otherwise, you'll choose a graph each time.")
            }

            if viewModel.additionalGraphs.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Text("No additional graphs configured.")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    }
                } header: {
                    Text("My Graphs")
                }
            } else {
                Section {
                    ForEach(sortedGraphs) { graph in
                        NavigationLink {
                            AddEditGraphView(viewModel: viewModel, existingGraph: graph)
                        } label: {
                            Text(graph.name)
                        }
                    }
                } header: {
                    Text("My Graphs")
                } footer: {
                    Text("Primary Graph is intentionally kept separate. Use the main settings to make changes to your Primary Graph.")
                }
            }

            Section {
                Button {
                    showingAddGraph = true
                } label: {
                    Label("Add Graph", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Additional Graphs")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddGraph) {
            NavigationStack {
                AddEditGraphView(viewModel: viewModel, existingGraph: nil)
            }
        }
    }

    // Keep graph choices predictable in both the list and its edit destinations.
    private var sortedGraphs: [AdditionalGraph] {
        viewModel.additionalGraphs.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}

#Preview {
    NavigationStack {
        ManageGraphsView(viewModel: ProfileViewModel())
    }
}
