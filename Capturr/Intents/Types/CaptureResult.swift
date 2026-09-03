/// This App Entity is the temporary result returned after `CaptureIntent` queues an item.
/// Shortcuts receives its identifier, content, and queue status so later workflow steps can
/// inspect them. The value exists only for that intent run; `CaptureResultQuery` satisfies
/// App Intents' entity requirement but has no saved results to retrieve.

import AppIntents

struct CaptureResult: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Capture Result" }
    static var defaultQuery = CaptureResultQuery()

    var id: String
    var content: String
    var status: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(content)", subtitle: "\(status)")
    }
}

struct CaptureResultQuery: EntityQuery {
    // Capture results are returned directly and never stored as queryable entities.
    func entities(for identifiers: [String]) async throws -> [CaptureResult] {
        []
    }
}
