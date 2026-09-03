/// This view model owns the document scan state machine and initial review selection.
/// `CaptureScan` gives it camera pages, and it asks `DocumentRecognitionService`
/// to recognize each one. It preserves page structure, applies lightweight quality
/// rules, and publishes the results consumed by `QuickReviewView`.

import Combine
import CoreGraphics
import Foundation

private enum ScanConstants {
    // Excludes stray paragraph symbols such as "•", "1", and "--".
    static let minimumParagraphCharacters = 3

    // Rejects repeated-character artifacts such as "----" and "....".
    static let minimumUniqueCharactersForQuality = 2

    static let minimumListItems = 2
    static let minimumListItemCharacters = 3
    static let minimumTableCellCharacters = 2
}

// Owns the OCR state machine and the default quality-based review selection.
@MainActor
final class CaptureScanViewModel: ObservableObject {
    enum Stage {
        case idle
        case recognizing
        case reviewing
    }

    @Published var stage: Stage = .idle

    // Multi-page scans have page wrappers; a single page keeps its content flat.
    @Published var topLevelNodes: [DocumentNode] = []

    // Good-quality results start selected, but the review UI can change the set.
    @Published var includedIDs: Set<UUID> = []

    @Published var errorMessage: String?

    // Retain automatic exclusions so the review UI can explain its initial choices.
    @Published var autoExcludedIDs: Set<UUID> = []

    // MARK: - Recognition

    // Recognize every camera page, preserve page boundaries, and seed the review selection.
    func startRecognition(from images: [CGImage]) async {
        stage = .recognizing

        guard !images.isEmpty else {
            self.errorMessage = "No images to process."
            self.stage = .idle
            return
        }

        var recognizedTopLevelNodes: [DocumentNode] = []

        for (pageIndex, image) in images.enumerated() {
            do {
                let nodes = try await DocumentRecognitionService.recognize(from: image)

                if images.count == 1 {
                    // A single page does not need an extra level in the review list or Roam output.
                    if nodes.isEmpty {
                        recognizedTopLevelNodes = [DocumentNode(kind: .paragraph, text: "No text found")]
                    } else {
                        recognizedTopLevelNodes = nodes
                    }
                } else {
                    let pageChildren: [DocumentNode] = nodes.isEmpty
                        ? [DocumentNode(kind: .paragraph, text: "No text found")]
                        : nodes

                    let pageNode = DocumentNode(
                        kind: .page(number: pageIndex + 1),
                        children: pageChildren
                    )
                    recognizedTopLevelNodes.append(pageNode)
                }
            } catch {
                // Preserve a failed page's place instead of silently changing later page numbers.
                if images.count > 1 {
                    let errorNode = DocumentNode(
                        kind: .page(number: pageIndex + 1),
                        children: [DocumentNode(kind: .paragraph, text: "Error processing page")]
                    )
                    recognizedTopLevelNodes.append(errorNode)
                }
            }
        }

        guard !recognizedTopLevelNodes.isEmpty else {
            self.errorMessage = "No readable text found. Try again."
            self.stage = .idle
            return
        }

        // Only actual OCR elements are selectable; page wrappers organize them.
        let selectableNodes: [DocumentNode]
        if images.count > 1 {
            selectableNodes = recognizedTopLevelNodes.flatMap { $0.children }
        } else {
            selectableNodes = recognizedTopLevelNodes
        }

        let goodQualityNodes = selectableNodes.filter { isGoodQuality($0) }
        let excludedNodeIDs = Set(selectableNodes.map { $0.id }).subtracting(Set(goodQualityNodes.map { $0.id }))

        self.topLevelNodes = recognizedTopLevelNodes
        self.includedIDs = Set(goodQualityNodes.map { $0.id })
        self.autoExcludedIDs = excludedNodeIDs
        self.stage = .reviewing
    }

    // MARK: - Quality Classification

    // Choose which results start selected without removing anything from manual review.
    private func isGoodQuality(_ node: DocumentNode) -> Bool {
        switch node.kind {
        case .paragraph:
            return isGoodParagraph(node)
        case .list:
            return isGoodList(node)
        case .table:
            return isGoodTable(node)
        case .page:
            return node.children.contains { isGoodQuality($0) }
        }
    }

    // Reject empty, tiny, non-letter, repeated-character, and common page-noise paragraphs.
    private func isGoodParagraph(_ node: DocumentNode) -> Bool {
        guard let text = node.text else { return false }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return false }
        guard trimmed.count >= ScanConstants.minimumParagraphCharacters else { return false }
        guard trimmed.rangeOfCharacter(from: .letters) != nil else { return false }

        let uniqueChars = Set(trimmed)
        guard uniqueChars.count > ScanConstants.minimumUniqueCharactersForQuality else { return false }

        let noisePatterns = [
            "^\\d+$",                    // Just numbers: "42"
            "^[•·\\-*]+$",              // Just bullets: "• • •"
            "^[\\[\\]\\(\\)]+$",        // Just brackets: "[][]"
            "^page \\d+$"               // Page numbers: "page 1"
        ]

        for pattern in noisePatterns {
            if trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return false
            }
        }

        return true
    }

    // A useful list needs multiple items and at least one meaningful text entry.
    private func isGoodList(_ node: DocumentNode) -> Bool {
        guard node.children.count >= ScanConstants.minimumListItems else { return false }

        return node.children.contains { child in
            if let text = child.text {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.count >= ScanConstants.minimumListItemCharacters
                    && trimmed.rangeOfCharacter(from: .letters) != nil
            }
            return false
        }
    }

    // A useful table needs a row and at least one non-trivial cell.
    private func isGoodTable(_ node: DocumentNode) -> Bool {
        guard !node.children.isEmpty else { return false }

        return node.children.contains { row in
            row.children.contains { cell in
                if let text = cell.text {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.count >= ScanConstants.minimumTableCellCharacters
                }
                return false
            }
        }
    }
}
