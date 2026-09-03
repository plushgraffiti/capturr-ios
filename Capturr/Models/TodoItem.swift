/// This model caches one TODO fetched from Roam so the TODO screen can work from local data.
/// `TodoSyncManager` creates and refreshes these SwiftData records, `TodosViewModel` filters
/// them into the visible lists and sections, and `TodoRow` uses the original Roam block data
/// when it queues a completion change through the outbox.

import Foundation
import SwiftData

@Model
final class TodoItem {
    // The local UUID identifies the cached record, while the Roam UID lets refreshes
    // merge the same remote block and lets completion changes target it later.
    var id: UUID
    var roamBlockUid: String

    // The UI shows the cleaned text, but syncing a toggle needs the untouched block
    // string so SyncWorker can replace its TODO or DONE marker.
    var text: String
    var originalString: String
    var isCompleted: Bool

    var createdAt: Date             // When this local cache record was created.
    var updatedAt: Date             // Roam's edit time, used to sort the TODO list.
    var parentPageTitle: String?
    var rawData: String?            // Reserved for a full response; the current parser leaves it nil.

    init(roamBlockUid: String, text: String, originalString: String, isCompleted: Bool = false) {
        self.id = UUID()
        self.roamBlockUid = roamBlockUid
        self.text = text
        self.originalString = originalString
        self.isCompleted = isCompleted
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
