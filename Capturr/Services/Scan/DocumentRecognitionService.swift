/// This service converts a scanned page image into structured document nodes.
/// `CaptureScanViewModel` calls it for each camera page. It prefers Vision's
/// paragraph, list, and table recognition, then falls back to plain text OCR
/// when structured recognition is unavailable or produces no usable result.

import Foundation
import Vision

private enum ScanConstants {
    // Nearby normalized Y coordinates are treated as one printed row.
    static let geometricSortingTolerance: Double = 0.01
}

// Collapse OCR whitespace so one recognized paragraph becomes one clean Roam block.
private func sanitizeParagraph(_ rawText: String) -> String {
    let collapsed = rawText.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
}

enum DocumentRecognitionService {
    // Both recognition paths return the same review-tree representation.
    static func recognize(from image: CGImage) async throws -> [DocumentNode] {
        do {
            return try await recognizeWithRecognizeDocuments(image: image)
        } catch {
            return try await recognizeWithTextRequest(image: image)
        }
    }

    // Structured recognition deduplicates text already contained in lists or tables,
    // then sorts all remaining elements geometrically to restore reading order.
    private static func recognizeWithRecognizeDocuments(image: CGImage) async throws -> [DocumentNode] {
        let request = RecognizeDocumentsRequest()
        let observations = try await request.perform(on: image)

        guard let document = observations.first?.document else {
            return try await recognizeWithTextRequest(image: image)
        }

        // Vision also reports container text as paragraphs; exact-match sets prevent duplicates.
        let listItemSet: Set<String> = Set(
            document.lists.flatMap { $0.items.map { sanitizeParagraph($0.content.text.transcript) } }
                .filter { !$0.isEmpty }
        )
        let tableCellSet: Set<String> = Set(
            document.tables.flatMap { tbl in
                tbl.rows.flatMap { row in row.map { sanitizeParagraph($0.content.text.transcript) } }
            }.filter { !$0.isEmpty }
        )

        func buildTableNode(_ table: DocumentObservation.Container.Table) -> DocumentNode {
            let rows = table.rows
            // Treat a non-empty first row as headers because Vision does not label headers separately.
            var headers: [String]? = nil
            var bodyRows = rows
            if let first = rows.first {
                let titles = first.map { $0.content.text.transcript.trimmed }
                if titles.contains(where: { !$0.isEmpty }) {
                    headers = titles
                    bodyRows = Array(rows.dropFirst())
                }
            }
            let rowNodes: [DocumentNode] = bodyRows.map { row in
                let cellNodes: [DocumentNode] = row.map { cell in
                    DocumentNode(kind: .paragraph, text: sanitizeParagraph(cell.content.text.transcript))
                }
                return DocumentNode(kind: .paragraph, text: nil, children: cellNodes)
            }
            return DocumentNode(kind: .table(headers: headers), children: rowNodes)
        }

        struct DocumentElement {
            let node: DocumentNode
            let sortY: Double  // Y-coordinate for top-to-bottom sorting
            let sortX: Double  // X-coordinate for left-to-right sorting
        }

        // Vision does not publicly expose these coordinates, so this reflection path is fragile:
        // boundingRegion → originalQuad → topLeft → cgPoint. If an OS update changes that
        // internal shape, returning nil safely places the element in the fallback sort group.
        func extractCoordinates(from region: Any) -> (y: Double, x: Double)? {
            let mirror = Mirror(reflecting: region)

            if let quadValue = mirror.children.first(where: { $0.label == "originalQuad" })?.value {
                let quadMirror = Mirror(reflecting: quadValue)

                if quadMirror.displayStyle == .optional, let some = quadMirror.children.first?.value {
                    let rectMirror = Mirror(reflecting: some)
                    if let topLeftValue = rectMirror.children.first(where: { $0.label == "topLeft" })?.value {
                        let topLeftMirror = Mirror(reflecting: topLeftValue)

                        if let cgPointValue = topLeftMirror.children.first(where: { $0.label == "cgPoint" })?.value as? CGPoint {
                            return (y: Double(cgPointValue.y), x: Double(cgPointValue.x))
                        }
                    }
                }
            }
            return nil
        }

        var elements: [DocumentElement] = []

        // Collect each kind with its page position, excluding duplicate container text.
        for para in document.paragraphs {
            let text = sanitizeParagraph(para.transcript)
            if !text.isEmpty && !listItemSet.contains(text) && !tableCellSet.contains(text) {
                let node = DocumentNode(kind: .paragraph, text: text)
                if let coords = extractCoordinates(from: para.boundingRegion) {
                    elements.append(DocumentElement(node: node, sortY: coords.y, sortX: coords.x))
                } else {
                    elements.append(DocumentElement(node: node, sortY: 0.0, sortX: 0.0))
                }
            }
        }

        for list in document.lists {
            let children: [DocumentNode] = list.items.compactMap { item in
                let listItemText = sanitizeParagraph(item.content.text.transcript)
                return listItemText.isEmpty ? nil : DocumentNode(kind: .paragraph, text: listItemText)
            }
            if !children.isEmpty {
                let node = DocumentNode(kind: .list(isOrdered: false), children: children)
                if let coords = extractCoordinates(from: list.boundingRegion) {
                    elements.append(DocumentElement(node: node, sortY: coords.y, sortX: coords.x))
                } else {
                    elements.append(DocumentElement(node: node, sortY: 0.0, sortX: 0.0))
                }
            }
        }

        for table in document.tables {
            let node = buildTableNode(table)
            if let coords = extractCoordinates(from: table.boundingRegion) {
                elements.append(DocumentElement(node: node, sortY: coords.y, sortX: coords.x))
            } else {
                elements.append(DocumentElement(node: node, sortY: 0.0, sortX: 0.0))
            }
        }

        // Vision's origin is bottom-left: higher Y comes first, then lower X within a row.
        elements.sort { e1, e2 in
            if abs(e1.sortY - e2.sortY) > ScanConstants.geometricSortingTolerance {
                return e1.sortY > e2.sortY  // Higher Y first (top to bottom)
            }
            return e1.sortX < e2.sortX  // Lower X first (left to right)
        }

        let nodes = elements.map { $0.node }

        if nodes.isEmpty {
            return try await recognizeWithTextRequest(image: image)
        }
        return nodes
    }

    // Plain-text fallback joins every recognized line into one paragraph node.
    private static func recognizeWithTextRequest(image: CGImage) async throws -> [DocumentNode] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.revision = VNRecognizeTextRequestRevision3

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let observations = request.results, observations.isEmpty == false else { return [] }

        let full = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        let clean = sanitizeParagraph(full)
        return clean.isEmpty ? [] : [DocumentNode(kind: .paragraph, text: clean)]
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
