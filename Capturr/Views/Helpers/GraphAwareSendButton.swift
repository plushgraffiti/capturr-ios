/// This view provides the graph-aware send control used by note and TODO capture screens.
/// It reads the shared profile's multi-graph preferences, then either sends directly
/// to the primary or last-used graph or asks the user to choose from a menu.
/// `CaptureWrite` and `CaptureTodo` create their outbox items from the selected graph
/// identifier and display name returned through `onSend`.

import SwiftUI

struct GraphAwareSendButton: View {
    @EnvironmentObject private var profileViewModel: ProfileViewModel

    // The capture screen receives the chosen destination; a nil ID means the primary graph.
    let onSend: (String?, String) -> Void

    var isDisabled: Bool = false

    var body: some View {
        if !profileViewModel.multiGraphEnabled || profileViewModel.additionalGraphs.isEmpty {
            // Without usable additional graphs, capture always goes to the primary graph.
            Button(action: { sendToPrimary() }) {
                buttonLabel(text: "Send to Graph")
            }
            .buttonStyle(SendButtonStyle())
            .disabled(isDisabled)
        } else if !profileViewModel.multiGraphDefaultToLast {
            // No default means every tap should ask rather than choose a graph implicitly.
            Menu {
                graphMenuContent()
            } label: {
                buttonLabel(text: "Choose a Graph", showGraphIcon: true)
            }
            .buttonStyle(SendButtonStyle())
            .disabled(isDisabled)
        } else {
            // A normal tap repeats the last destination; the context menu exposes alternatives.
            Button(action: { sendToLastUsed() }) {
                buttonLabel(text: "Send to \(lastUsedGraphName)")
            }
            .buttonStyle(SendButtonStyle())
            .disabled(isDisabled)
            .contextMenu {
                graphMenuContent()
            }
        }
    }

    // MARK: - Helpers

    private var lastUsedGraphName: String {
        let effectiveGraphId = profileViewModel.effectiveLastUsedGraphId()
        return profileViewModel.graphDisplayName(for: effectiveGraphId)
    }

    private func sendToPrimary() {
        let name = profileViewModel.graphName ?? "Primary Graph"
        updateLastUsed(nil)
        onSend(nil, name)
    }

    private func sendToLastUsed() {
        let effectiveGraphId = profileViewModel.effectiveLastUsedGraphId()
        let name = profileViewModel.graphDisplayName(for: effectiveGraphId)
        updateLastUsed(effectiveGraphId)
        onSend(effectiveGraphId, name)
    }

    private func sendToGraph(id: String?, name: String) {
        updateLastUsed(id)
        onSend(id, name)
    }

    private func updateLastUsed(_ graphId: String?) {
        profileViewModel.lastUsedGraphId = graphId
        // The capture screen persists this profile change after it creates the outbox item.
    }

    @ViewBuilder
    private func graphMenuContent() -> some View {
        // Keep the primary graph first even though additional graphs are alphabetical.
        let primaryName = profileViewModel.graphName ?? "Primary Graph"
        let lastUsedGraphId = profileViewModel.effectiveLastUsedGraphId()

        Button {
            sendToGraph(id: nil, name: primaryName)
        } label: {
            HStack {
                Text("\(primaryName)")
                if lastUsedGraphId == nil {
                    Image(systemName: "checkmark")
                }
            }
        }

        Divider()

        ForEach(sortedAdditionalGraphs) { graph in
            Button {
                sendToGraph(id: graph.id, name: graph.name)
            } label: {
                HStack {
                    Text(graph.name)
                    if lastUsedGraphId == graph.id {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }

    private var sortedAdditionalGraphs: [AdditionalGraph] {
        profileViewModel.additionalGraphs.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    @ViewBuilder
    private func buttonLabel(text: String, showGraphIcon: Bool = false) -> some View {
        HStack {
            Text(text)
                .lineLimit(1)
            if showGraphIcon {
                Image(systemName: "square.3.layers.3d")
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.accentColor)
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// Preserve the custom full-width label while still showing pressed feedback.
struct SendButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// MARK: - Preview

#Preview("Single Graph") {
    let previewViewModel = ProfileViewModel()
    previewViewModel.graphName = "my-graph"
    previewViewModel.multiGraphEnabled = false

    return GraphAwareSendButton { graphId, graphName in
        print("Send to \(graphName) (id: \(graphId ?? "primary"))")
    }
    .environmentObject(previewViewModel)
    .padding()
}

#Preview("Multi-Graph No Default") {
    let previewViewModel = ProfileViewModel()
    previewViewModel.graphName = "my-graph"
    previewViewModel.multiGraphEnabled = true
    previewViewModel.multiGraphDefaultToLast = false
    previewViewModel.additionalGraphs = [
        AdditionalGraph(id: "1", name: "Work Graph"),
        AdditionalGraph(id: "2", name: "Personal Graph")
    ]

    return GraphAwareSendButton { graphId, graphName in
        print("Send to \(graphName) (id: \(graphId ?? "primary"))")
    }
    .environmentObject(previewViewModel)
    .padding()
}

#Preview("Multi-Graph With Default") {
    let previewViewModel = ProfileViewModel()
    previewViewModel.graphName = "my-graph"
    previewViewModel.multiGraphEnabled = true
    previewViewModel.multiGraphDefaultToLast = true
    previewViewModel.lastUsedGraphId = "1"
    previewViewModel.additionalGraphs = [
        AdditionalGraph(id: "1", name: "Work Graph"),
        AdditionalGraph(id: "2", name: "Personal Graph")
    ]

    return GraphAwareSendButton { graphId, graphName in
        print("Send to \(graphName) (id: \(graphId ?? "primary"))")
    }
    .environmentObject(previewViewModel)
    .padding()
}
