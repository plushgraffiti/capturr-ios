/// This App Entity carries the outbox summary returned by `GetCaptureStatusIntent`.
/// Shortcuts workflows can inspect its pending count, failed count, and latest successful
/// sync time. The value exists only for that intent run; `CaptureStatusResultQuery` fulfills
/// App Intents' entity requirement but has no saved results to retrieve.

import AppIntents

struct CaptureStatusResult: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Capture Status" }
    static var defaultQuery = CaptureStatusResultQuery()

    var id: String = UUID().uuidString
    var pendingCount: Int
    var failedCount: Int
    var lastSyncTime: Date?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(pendingCount) pending, \(failedCount) failed")
    }
}

struct CaptureStatusResultQuery: EntityQuery {
    // Status summaries are returned directly and never stored as queryable entities.
    func entities(for identifiers: [String]) async throws -> [CaptureStatusResult] {
        []
    }
}
