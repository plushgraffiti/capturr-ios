/// This manager is the small front door for the app's two-stage outbox pipeline.
/// `CapturrApp` creates it with the shared model context and asks it to kick the queue.
/// Each pass transcribes waiting audio first, then gives sendable captures to `SyncWorker`.

import Foundation
import SwiftData

@MainActor
final class SyncManager {
    let syncWorker: SyncWorker
    let transcriptionWorker: TranscriptionWorker

    init(modelContext: ModelContext) {
        self.syncWorker = SyncWorker(
            modelContext: modelContext,
            monitorsForegroundConnectivity: true
        )
        self.transcriptionWorker = TranscriptionWorker(modelContext: modelContext)
    }

    func kickQueue() {
        Task {
            await transcriptionWorker.processPendingItems()
            await syncWorker.drainPendingItems()
        }
    }
}
