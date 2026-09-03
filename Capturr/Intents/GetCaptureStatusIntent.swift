/// This read-only intent reports the current state of Capturr's saved outbox to Shortcuts.
/// `CapturrShortcuts` registers spoken status phrases, and automations can also use the
/// returned `CaptureStatusResult`. It reads the shared SwiftData store in the main app
/// process and counts waiting, failed, and most recently completed captures.

import AppIntents
import SwiftData

struct GetCaptureStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Sync Status"
    static var description = IntentDescription("Check the status of pending captures")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<CaptureStatusResult> & ProvidesDialog {
        let container = SharedModelContainer()
        let context = ModelContext(container)

        let allItems = try context.fetch(FetchDescriptor<OutboxItem>())
        let pendingCount = allItems.filter {
            $0.status == SyncStatus.pending.rawValue || $0.status == SyncStatus.inProgress.rawValue
        }.count
        let failedCount = allItems.filter { $0.status == SyncStatus.failed.rawValue }.count
        let lastSuccessfulSyncTime = allItems
            .filter { $0.status == SyncStatus.success.rawValue }
            .compactMap { $0.sentAt }
            .max()

        let result = CaptureStatusResult(
            pendingCount: pendingCount,
            failedCount: failedCount,
            lastSyncTime: lastSuccessfulSyncTime
        )

        let dialog: IntentDialog = pendingCount == 0
            ? "All captures synced"
            : "\(pendingCount) capture\(pendingCount == 1 ? "" : "s") pending sync"

        return .result(value: result, dialog: dialog)
    }
}

// Main-app execution gives the intent direct access to the shared model container.
extension GetCaptureStatusIntent {
    static var supportedModes: IntentModes { .foreground(.dynamic) }
}
