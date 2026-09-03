/// This helper supplies sample scan trees and Xcode previews for the scan UI.
/// It keeps preview examples away from the production workflow code
/// while exercising single-page, multi-page, empty-selection, and full-screen states.

import SwiftUI

extension DocumentNode {
    static func sampleParagraph(_ text: String) -> DocumentNode {
        DocumentNode(kind: .paragraph, text: text)
    }

    static func sampleList(items: [String], ordered: Bool = false) -> DocumentNode {
        let children = items.map { DocumentNode(kind: .paragraph, text: $0) }
        return DocumentNode(kind: .list(isOrdered: ordered), children: children)
    }

    static func sampleTable(headers: [String], rows: [[String]]) -> DocumentNode {
        let rowNodes = rows.map { rowData -> DocumentNode in
            let cellNodes = rowData.map { DocumentNode(kind: .paragraph, text: $0) }
            return DocumentNode(kind: .paragraph, text: nil, children: cellNodes)
        }
        return DocumentNode(kind: .table(headers: headers), children: rowNodes)
    }

    static func samplePage(number: Int, children: [DocumentNode]) -> DocumentNode {
        DocumentNode(kind: .page(number: number), children: children)
    }

    static var sampleSinglePageNodes: [DocumentNode] {
        [
            sampleParagraph("Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."),
            sampleParagraph("Short text"),
            sampleList(items: [
                "First list item with some content",
                "Second item",
                "Third item with more detailed information"
            ]),
            sampleTable(
                headers: ["Name", "Email", "Phone"],
                rows: [
                    ["John Smith", "john@example.com", "555-0123"],
                    ["Jane Doe", "jane@example.com", "555-0124"]
                ]
            ),
            sampleParagraph("•"), // Noise that should be auto-excluded
        ]
    }

    static var sampleMultiPageNodes: [DocumentNode] {
        [
            samplePage(number: 1, children: [
                sampleParagraph("Introduction: This is the first page of a multi-page document scan."),
                sampleList(items: ["First objective", "Second objective", "Third objective"])
            ]),
            samplePage(number: 2, children: [
                sampleTable(
                    headers: ["Item", "Quantity", "Price"],
                    rows: [
                        ["Widget", "5", "$10.00"],
                        ["Gadget", "2", "$25.00"]
                    ]
                ),
                sampleParagraph("Total amount due: $75.00")
            ]),
            samplePage(number: 3, children: [
                sampleParagraph("Conclusion and final remarks."),
                sampleParagraph("Thank you for your attention.")
            ])
        ]
    }
}

#Preview("Single Page Review") {
    @Previewable @State var includedIDs: Set<UUID> = Set(DocumentNode.sampleSinglePageNodes.map { $0.id })
    @Previewable @State var autoExcludedIDs: Set<UUID> = Set([DocumentNode.sampleSinglePageNodes.last!.id])

    NavigationStack {
        QuickReviewView(
            nodes: DocumentNode.sampleSinglePageNodes,
            includedIDs: $includedIDs,
            autoExcludedIDs: autoExcludedIDs
        )
        .navigationTitle("Scan")
    }
}

#Preview("Multi-Page Review") {
    @Previewable @State var includedIDs: Set<UUID> = {
        let allNodes = DocumentNode.sampleMultiPageNodes.flatMap { $0.children }
        return Set(allNodes.map { $0.id })
    }()
    @Previewable @State var autoExcludedIDs: Set<UUID> = []

    QuickReviewView(
        nodes: DocumentNode.sampleMultiPageNodes,
        includedIDs: $includedIDs,
        autoExcludedIDs: autoExcludedIDs
    )
}

#Preview("Empty Selection") {
    @Previewable @State var includedIDs: Set<UUID> = []
    @Previewable @State var autoExcludedIDs: Set<UUID> = Set(DocumentNode.sampleSinglePageNodes.map { $0.id })

    QuickReviewView(
        nodes: DocumentNode.sampleSinglePageNodes,
        includedIDs: $includedIDs,
        autoExcludedIDs: autoExcludedIDs
    )
}

#Preview("Full Scan View") {
    NavigationStack {
        CaptureScan()
            .environmentObject(ProfileViewModel())
    }
}
