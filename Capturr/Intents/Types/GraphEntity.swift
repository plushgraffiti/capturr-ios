/// This App Entity represents one destination in `CaptureIntent`'s Shortcuts graph picker.
/// `GraphEntityQuery` reads the primary and additional graphs from the shared `UserProfile`
/// whenever App Intents needs suggestions or identifier lookup. It uses a special primary
/// identifier that the capture intent converts to the outbox's normal nil destination.

import AppIntents
import SwiftData

struct GraphEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Graph" }
    static var defaultQuery = GraphEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct GraphEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [GraphEntity] {
        let allGraphs = try getAllGraphs()
        return allGraphs.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [GraphEntity] {
        try getAllGraphs()
    }

    private func getAllGraphs() throws -> [GraphEntity] {
        let container = SharedModelContainer()
        let context = ModelContext(container)
        let manager = ProfileManager(modelContext: context)
        let profile = try manager.getCurrentProfile()

        var graphs: [GraphEntity] = []
        // The primary sentinel makes the default graph selectable like every additional graph.
        if let name = profile.graphName {
            graphs.append(GraphEntity(id: "primary", name: name))
        }

        for graph in profile.additionalGraphs {
            graphs.append(GraphEntity(id: graph.id, name: graph.name))
        }

        return graphs
    }
}
