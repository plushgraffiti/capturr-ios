/// This model represents one structured result from document recognition.
/// Scan recognition builds a tree of paragraphs, lists, tables, and pages;
/// `CaptureScanViewModel`, `QuickReviewView`, and `RoamTransformer` share that
/// tree while the scan moves from OCR through review to Roam block creation.

import Foundation

enum DocumentNodeKind: Equatable {
    case paragraph
    case list(isOrdered: Bool)
    case table(headers: [String]?)
    case page(number: Int)
}

// A selectable OCR result. Containers keep their list items, rows, cells, or page contents as children.
struct DocumentNode: Identifiable, Equatable {
    var id = UUID()
    var kind: DocumentNodeKind
    var text: String?
    var children: [DocumentNode] = []
}
