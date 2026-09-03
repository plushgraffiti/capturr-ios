/// This helper converts reviewed document nodes into Roam's nested block format.
/// `CaptureScan` gives it only the selected OCR results, and it preserves page and
/// list hierarchy while translating tables into the child-chain structure expected
/// by Roam's `{{table}}` syntax.

import Foundation

enum RoamTransformer {
    // Remove whitespace and bullet artifacts that OCR commonly leaves in table cells.
    private static func cleanCell(_ rawText: String) -> String {
        let collapsed = rawText.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                          .replacingOccurrences(of: "•", with: "")
                          .replacingOccurrences(of: "·", with: "")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func blocks(fromTopLevel nodes: [DocumentNode]) -> [RoamBlock] {
        nodes.flatMap { block(from: $0) }
    }

    // Recursion preserves the hierarchy while allowing invalid empty tables to produce no block.
    private static func block(from node: DocumentNode) -> [RoamBlock] {
        switch node.kind {
        case .paragraph:
            return [.init(string: node.text ?? "")]
        case .list(let isOrdered):
            let title = isOrdered ? "List (ordered)" : "List"
            let items = node.children.map { RoamBlock(string: $0.text ?? "") }
            return [.init(string: title, children: items)]
        case .page(let number):
            let children = node.children.flatMap { block(from: $0) }
            return [.init(string: "Page \(number)", children: children)]
        case .table(let headers):
            // A row such as ["A", "B", "C"] becomes A → B → C through nested children.
            func chain(_ strings: [String]) -> RoamBlock? {
                let cleanedCells = strings.map(cleanCell).filter { !$0.isEmpty }
                guard !cleanedCells.isEmpty else { return nil }

                // Build right-to-left so each cell can own the already-built remainder.
                var nestedBlock: RoamBlock? = nil
                for cellText in cleanedCells.reversed() {
                    nestedBlock = RoamBlock(string: cellText, children: nestedBlock.map { [$0] } ?? [])
                }
                return nestedBlock
            }

            var children: [RoamBlock] = []

            if let headerCells = headers, let headerRow = chain(headerCells) {
                children.append(headerRow)
            }

            for row in node.children {
                let cells = row.children.map { cleanCell($0.text ?? "") }
                if let rowBlock = chain(cells) {
                    children.append(rowBlock)
                }
            }

            guard !children.isEmpty else { return [] }
            return [RoamBlock(string: "{{table}}", children: children)]
        }
    }
}
