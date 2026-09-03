/// This view lets the user choose which recognized document elements to keep.
/// `CaptureScan` presents it after OCR finishes and binds it to the scan view
/// model's selected identifiers. It preserves camera-page groupings and offers
/// bulk choices for all results, the quality-filtered results, or none.

import SwiftUI

private enum ScanConstants {
    static let paragraphLabelMaxWords = 6
    static let listItemPreviewMaxWords = 4
    static let listPreviewMaxItems = 3
    static let tableHeaderPreviewMaxColumns = 2
}

// Multi-page results remain grouped by their camera page.
struct QuickReviewView: View {
    let nodes: [DocumentNode]
    @Binding var includedIDs: Set<UUID>
    let autoExcludedIDs: Set<UUID>

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            quickActionsBar

            if isMultiPage {
                multiPageList
            } else {
                singlePageList
            }
        }
    }

    // MARK: - List Rendering

    private var isMultiPage: Bool {
        nodes.contains { node in
            if case .page = node.kind { return true }
            return false
        }
    }

    private var singlePageList: some View {
        List(nodes) { node in
            itemRow(node)
        }
        .listStyle(.plain)
    }

    private var multiPageList: some View {
        List {
            ForEach(nodes) { pageNode in
                if case .page(let number) = pageNode.kind {
                    Section {
                        ForEach(pageNode.children) { childNode in
                            itemRow(childNode)
                        }
                    } header: {
                        Text("Page \(number)")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func itemRow(_ node: DocumentNode) -> some View {
        Button {
            toggle(node)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName(for: node))
                    .imageScale(.large)
                    .foregroundStyle(iconColor(for: node))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title(for: node))
                        .font(.headline)

                    if let preview = previewText(for: node), preview.isEmpty == false {
                        Text(preview)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }

                    HStack(spacing: 12) {
                        if let charCount = characterCount(for: node) {
                            Label("\(charCount) chars", systemImage: "textformat.size")
                        }

                        if autoExcludedIDs.contains(node.id) {
                            Label("Auto-excluded", systemImage: "info.circle")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .opacity(includedIDs.contains(node.id) ? 1.0 : 0.5)
    }

    // MARK: - Quick Actions

    private var quickActionsBar: some View {
        HStack {
            Button {
                includedIDs = Set(selectableNodes.map { $0.id })
                hapticFeedback(.light)
            } label: {
                Label("All", systemImage: "checkmark.circle")
                    .font(.caption)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Select all results")
            .accessibilityHint("Replaces your current selection with all items.")
            .accessibilityIdentifier("allResultsButton")

            Button {
                includedIDs = Set(selectableNodes.filter { !autoExcludedIDs.contains($0.id) }.map { $0.id })
                hapticFeedback(.light)
            } label: {
                Label("Best", systemImage: "sparkles")
                    .font(.caption)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Select high-confidence results")
            .accessibilityHint("Replaces your current selection with only items the scanner is very confident are correct.")
            .accessibilityIdentifier("highConfidenceResultsButton")

            Button {
                includedIDs = []
                hapticFeedback(.light)
            } label: {
                Label("None", systemImage: "circle")
                    .font(.caption)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Deselects all results")
            .accessibilityHint("Removes all current selections.")
            .accessibilityIdentifier("noResultsButton")

            Spacer()

            Text("\(includedIDs.count) of \(selectableNodes.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // Page wrappers organize the UI but are not selectable results themselves.
    private var selectableNodes: [DocumentNode] {
        if isMultiPage {
            return nodes.flatMap { $0.children }
        } else {
            return nodes
        }
    }

    // MARK: - Helper Methods

    private func toggle(_ node: DocumentNode) {
        hapticFeedback(.medium)
        if includedIDs.contains(node.id) {
            includedIDs.remove(node.id)
        } else {
            includedIDs.insert(node.id)
        }
    }

    private func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    private func iconName(for node: DocumentNode) -> String {
        if autoExcludedIDs.contains(node.id) && !includedIDs.contains(node.id) {
            return "xmark.circle"
        }
        return includedIDs.contains(node.id) ? "checkmark.circle.fill" : "circle"
    }

    private func iconColor(for node: DocumentNode) -> Color {
        if autoExcludedIDs.contains(node.id) && !includedIDs.contains(node.id) {
            return .orange
        }
        return includedIDs.contains(node.id) ? .blue : .gray
    }

    // MARK: - Label Generation

    private func title(for node: DocumentNode) -> String {
        switch node.kind {
        case .paragraph:
            return smartParagraphLabel(node)
        case .list(let ordered):
            return smartListLabel(node, ordered: ordered)
        case .table:
            return smartTableLabel(node)
        case .page(let number):
            return "Page \(number)"
        }
    }

    private func smartParagraphLabel(_ node: DocumentNode) -> String {
        guard let text = node.text, !text.isEmpty else {
            return "Empty paragraph"
        }

        let words = text.split(separator: " ")

        if words.count <= ScanConstants.paragraphLabelMaxWords {
            return text
        } else {
            let preview = words.prefix(ScanConstants.paragraphLabelMaxWords).joined(separator: " ")
            return "\(preview)…"
        }
    }

    private func smartListLabel(_ node: DocumentNode, ordered: Bool) -> String {
        let count = node.children.count
        let type = ordered ? "Ordered list" : "List"

        if let firstItem = node.children.first?.text, !firstItem.isEmpty {
            let preview = firstItem.split(separator: " ")
                .prefix(ScanConstants.listItemPreviewMaxWords)
                .joined(separator: " ")
            return "\(type) (\(count) items): \(preview)…"
        }

        return "\(type) (\(count) items)"
    }

    private func smartTableLabel(_ node: DocumentNode) -> String {
        let rowCount = node.children.count
        let colCount = node.children.first?.children.count ?? 0

        switch node.kind {
        case .table(let headers):
            if let headers = headers, !headers.isEmpty {
                let headerPreview = headers
                    .prefix(ScanConstants.tableHeaderPreviewMaxColumns)
                    .joined(separator: " | ")
                return "Table (\(rowCount) × \(colCount)): \(headerPreview)…"
            } else {
                return "Table: \(rowCount) rows × \(colCount) columns"
            }
        default:
            return "Table"
        }
    }

    private func previewText(for node: DocumentNode) -> String? {
        switch node.kind {
        case .paragraph:
            return node.text
        case .list:
            return node.children
                .prefix(ScanConstants.listPreviewMaxItems)
                .compactMap { $0.text }
                .joined(separator: " • ")
        case .table(let headers):
            return (headers ?? []).joined(separator: " | ")
        case .page:
            return nil  // Pages don't have preview text (children are shown in sections)
        }
    }

    private func characterCount(for node: DocumentNode) -> Int? {
        switch node.kind {
        case .paragraph:
            return node.text?.count
        case .list:
            let total = node.children.compactMap { $0.text?.count }.reduce(0, +)
            return total > 0 ? total : nil
        case .table:
            return nil  // Too complex to count meaningfully
        case .page:
            return nil  // Pages don't have character count
        }
    }
}
