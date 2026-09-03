/// This test helper creates an isolated SwiftData store that lives only in memory.
/// `ModelTests` and `TodoSyncManagerTests` call `make()` to exercise the production
/// models without reading or changing the app's shared on-disk store. The container
/// includes every model those suites insert or fetch.

import SwiftData
@testable import Capturr

enum InMemoryModelContainer {
    @MainActor
    static func make() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: OutboxItem.self,
            UserProfile.self,
            TodoItem.self,
            TodoSection.self,
            configurations: configuration
        )
    }
}
