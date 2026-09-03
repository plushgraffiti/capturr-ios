/// This persistence helper creates the main app's shared SwiftData container once.
/// `CapturrApp` and background entry points use the same container so captures, profiles,
/// and TODOs live in the app-group store also seen by the share extension. Its explicit
/// configuration prevents entitlement changes from silently moving the database.

import Foundation
import SwiftData

private let _sharedContainer: ModelContainer = {
    // Explicit app group: same location .automatic already resolves to (both
    // targets carry exactly one group entitlement — that's how the share
    // extension sees this store today), pinned so a second entitlement or a
    // background-launched consumer can never silently move it.
    let config = ModelConfiguration(
        isStoredInMemoryOnly: false,
        groupContainer: .identifier(AppConstants.appGroupSuite),
        cloudKitDatabase: .none
    )
    do {
        return try ModelContainer(
            for: OutboxItem.self, UserProfile.self, TodoItem.self, TodoSection.self,
            configurations: config
        )
    } catch {
        fatalError("Failed to create ModelContainer: \(error.localizedDescription)")
    }
}()

public func SharedModelContainer() -> ModelContainer {
    _sharedContainer
}
