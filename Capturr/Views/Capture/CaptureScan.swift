/// This view coordinates document capture, OCR progress, result review, and sending.
/// `CaptureHome` opens it for the scan route. It presents `DocumentCameraView`,
/// gives captured pages to `CaptureScanViewModel`, overlays `QuickReviewView`,
/// and saves the selected nodes as Roam blocks for the chosen graph.

import Foundation
import SwiftData
import SwiftUI
import UIKit

private enum ScanConstants {
    static let progressViewScale: CGFloat = 1.2
}

struct CaptureScan: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CaptureScanViewModel()
    @Environment(\.modelContext) private var modelContext: ModelContext
    @EnvironmentObject private var profileViewModel: ProfileViewModel

    @State private var showingCamera = false                  // Document camera trigger

    var body: some View {
        documentTab
        .overlay(reviewOverlay)
        .navigationTitle("Scan")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.stage == .reviewing {
                    graphAwareSendToolbarButton
                } else {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("CancelButton")
                    .accessibilityLabel("Close")
                }
            }

            ToolbarItem(placement: .status) {
                if viewModel.stage == .reviewing {
                    let pageCount = countPages(viewModel.topLevelNodes)
                    if pageCount > 1 {
                        Text("\(pageCount) pages")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .animation(.default, value: viewModel.stage)
        .alert("", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { _ in viewModel.errorMessage = nil })) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Helpers

    private func countPages(_ nodes: [DocumentNode]) -> Int {
        nodes.filter { node in
            if case .page = node.kind { return true }
            return false
        }.count
    }

    // MARK: - Graph-Aware Send

    @ViewBuilder
    private var graphAwareSendToolbarButton: some View {
        let isMultiGraphEnabled = profileViewModel.multiGraphEnabled && !profileViewModel.additionalGraphs.isEmpty

        if !isMultiGraphEnabled {
            // Without additional graphs there is no destination choice to present.
            Button(action: { sendToGraph(graphId: nil, graphName: profileViewModel.graphName ?? "Primary Graph") }) {
                Image(systemName: "checkmark")
            }
            .disabled(viewModel.includedIDs.isEmpty)
            .buttonStyle(.borderedProminent)
        } else if !profileViewModel.multiGraphDefaultToLast {
            // No default means every send should ask for a graph explicitly.
            Menu {
                graphMenuContent()
            } label: {
                Image(systemName: "checkmark")
            }
            .disabled(viewModel.includedIDs.isEmpty)
            .buttonStyle(.borderedProminent)
        } else {
            // Repeat the last destination on tap while keeping alternatives in the context menu.
            Button(action: {
                let effectiveGraphId = profileViewModel.effectiveLastUsedGraphId()
                let name = profileViewModel.graphDisplayName(for: effectiveGraphId)
                sendToGraph(graphId: effectiveGraphId, graphName: name)
            }) {
                Image(systemName: "checkmark")
            }
            .disabled(viewModel.includedIDs.isEmpty)
            .buttonStyle(.borderedProminent)
            .contextMenu {
                graphMenuContent()
            }
        }
    }

    @ViewBuilder
    private func graphMenuContent() -> some View {
        let primaryName = profileViewModel.graphName ?? "Primary Graph"
        let lastUsedGraphId = profileViewModel.effectiveLastUsedGraphId()

        Button {
            sendToGraph(graphId: nil, graphName: primaryName)
        } label: {
            HStack {
                Text("\(primaryName)")
                if lastUsedGraphId == nil {
                    Image(systemName: "checkmark")
                }
            }
        }

        Divider()

        ForEach(profileViewModel.additionalGraphs.sorted { $0.name.lowercased() < $1.name.lowercased() }) { graph in
            Button {
                sendToGraph(graphId: graph.id, graphName: graph.name)
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

    private func sendToGraph(graphId: String?, graphName: String) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        var insertedItem: OutboxItem?

        // Keep page wrappers only when they still contain selected results.
        let selectedNodes: [DocumentNode]
        let isMultiPage = viewModel.topLevelNodes.contains { node in
            if case .page = node.kind { return true }
            return false
        }

        if isMultiPage {
            selectedNodes = viewModel.topLevelNodes.compactMap { pageNode in
                guard case .page(let number) = pageNode.kind else { return nil }
                let selectedChildren = pageNode.children.filter { viewModel.includedIDs.contains($0.id) }
                guard !selectedChildren.isEmpty else { return nil }
                return DocumentNode(kind: .page(number: number), children: selectedChildren)
            }
        } else {
            selectedNodes = viewModel.topLevelNodes.filter { viewModel.includedIDs.contains($0.id) }
        }

        let blocks = RoamTransformer.blocks(fromTopLevel: selectedNodes)
        do {
            let data = try JSONEncoder().encode(blocks)
            guard let json = String(data: data, encoding: .utf8) else {
                viewModel.errorMessage = "Failed to encode blocks."
                return
            }
            let item = OutboxItem(content: json, type: .note)
            item.targetGraphId = graphId
            item.targetGraphName = graphName

            profileViewModel.lastUsedGraphId = graphId

            modelContext.insert(item)
            insertedItem = item
            try profileViewModel.saveChanges(context: modelContext)
            BackgroundSyncScheduler.scheduleAfterEnqueue(itemIDs: [item.id])
            dismiss()
        } catch {
            if let insertedItem { modelContext.delete(insertedItem) }
            viewModel.errorMessage = "Failed to prepare or save capture."
        }
    }

    // MARK: - Subviews

    private var documentTab: some View {
        VStack {
            ContentUnavailableView {
                Label("Scan Document", systemImage: "doc.viewfinder")
            } description: {
                Text("Point and capture. We’ll extract paragraphs, lists, and tables. Supports multiple pages.")
            } actions: {
                Button {
                    showingCamera = true
                } label: {
                    Text("Start Scanning")
                        .font(.system(.callout, weight: .semibold))
                        .padding()
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .foregroundStyle(.white)
                        .background(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .opacity(viewModel.stage == .idle ? 1 : 0)
        .allowsHitTesting(viewModel.stage == .idle)
        .sheet(isPresented: $showingCamera) {
            DocumentCameraView { images in
                showingCamera = false
                guard !images.isEmpty else { return }
                Task { await viewModel.startRecognition(from: images) }
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var reviewOverlay: some View {
        switch viewModel.stage {
        case .reviewing:
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                VStack(spacing: 0) {
                    QuickReviewView(
                        nodes: viewModel.topLevelNodes,
                        includedIDs: $viewModel.includedIDs,
                        autoExcludedIDs: viewModel.autoExcludedIDs
                    )
                }
                .transition(.move(edge: .bottom))
            }
        case .recognizing:
            ZStack {
                Color.white.opacity(1).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(ScanConstants.progressViewScale)
                    Text("Analyzing document…")
                        .font(.headline)
                    if !viewModel.topLevelNodes.isEmpty {
                        Text("Found \(viewModel.topLevelNodes.count) elements")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        default:
            EmptyView()
        }
    }
}
