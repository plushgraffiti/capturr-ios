/// This value model represents a Roam block and its child blocks as a small tree.
/// The block editor and scan transformer build these trees, and capture views encode
/// them inside an `OutboxItem`. `SyncWorker` decodes them and gives them to `RoamAPI`, which
/// turns the hierarchy into the request format Roam expects.

import Foundation

// string matches Roam's API field name, while children preserves the nested outline.
struct RoamBlock: Codable, Equatable {
    var string: String
    var children: [RoamBlock] = []
}

// The block editor uses this wrapper so SyncWorker can distinguish its content
// from document scans, which are stored as a bare [RoamBlock] array.
struct NestedCapture: Codable {
    var blocks: [RoamBlock]
    var source: String  // Currently "write"; SyncWorker checks it before sending.
}
