/// This helper schedules CAPTURR's background app-refresh task.
/// The main app, App Intents, and Share extension call it after durable saves,
/// while the background handler uses it before and after each work pass to keep
/// a fallback wake queued and then replace it with the next required time.

import BackgroundTasks
import Foundation
import OSLog
import SwiftData

enum BackgroundSyncScheduleDecision: Equatable {
    case submit(earliestBeginDate: Date?)
    case cancel
}

enum BackgroundSyncScheduler {
    private static let logger = Logger(
        subsystem: "com.capturr.app",
        category: "BackgroundSyncScheduler"
    )
    private static let todoRefreshIntervalSeconds: TimeInterval = 15 * 60
    private static let handlerFallbackDelaySeconds: TimeInterval = 15 * 60
    private static let inProgressRetryGapSeconds: TimeInterval = 5

    static func scheduleAfterEnqueue(itemIDs: [UUID]) {
        guard !itemIDs.isEmpty else { return }
        let itemIDStrings = itemIDs.map(\.uuidString).joined(separator: ",")
        logger.info("Scheduling background sync for item IDs: \(itemIDStrings, privacy: .public)")
        replacePendingRequest(earliestBeginDate: nil)
    }

    @discardableResult
    static func scheduleHandlerFallback() -> Bool {
        logger.info("Scheduling background sync handler fallback")
        return replacePendingRequest(
            earliestBeginDate: handlerFallbackDate(from: Date())
        )
    }

    static func handlerFallbackDate(from now: Date) -> Date {
        now.addingTimeInterval(handlerFallbackDelaySeconds)
    }

    @discardableResult
    @MainActor
    static func scheduleNext(modelContext: ModelContext) -> Bool {
        let items: [OutboxItem]
        let profile: UserProfile?
        do {
            items = try modelContext.fetch(FetchDescriptor<OutboxItem>())
            profile = try modelContext.fetch(FetchDescriptor<UserProfile>()).first
        } catch {
            logger.error("Failed to inspect background work: \(error.localizedDescription, privacy: .public)")
            return false
        }

        switch nextScheduleDecision(
            items: items,
            todosEnabled: profile?.todosEnabled == true,
            now: Date()
        ) {
        case .submit(let earliestBeginDate):
            return replacePendingRequest(earliestBeginDate: earliestBeginDate)
        case .cancel:
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: AppConstants.bgSyncTaskIdentifier)
            return true
        }
    }

    static func nextScheduleDecision(
        items: [OutboxItem],
        todosEnabled: Bool,
        now: Date
    ) -> BackgroundSyncScheduleDecision {
        let earliestOutboxAttemptAt = items.compactMap { item -> Date? in
            guard !(item.hardError ?? false),
                  item.status == SyncStatus.pending.rawValue || item.status == SyncStatus.inProgress.rawValue else {
                return nil
            }
            if let transcriptionState = item.transcriptionState {
                if transcriptionState == TranscriptionState.awaiting.rawValue { return now }
                if transcriptionState != TranscriptionState.done.rawValue { return nil }
            }
            if item.status == SyncStatus.inProgress.rawValue {
                return (item.lastAttemptAt ?? .distantPast)
                    .addingTimeInterval(inProgressRetryGapSeconds)
            }
            return item.nextAttemptAt ?? now
        }.min()

        let nextTodoRefreshAt = todosEnabled
            ? now.addingTimeInterval(todoRefreshIntervalSeconds)
            : nil

        let earliestBeginDate: Date?
        switch (earliestOutboxAttemptAt, nextTodoRefreshAt) {
        case (let outboxAttemptAt?, let todoRefreshAt?):
            earliestBeginDate = min(outboxAttemptAt, todoRefreshAt)
        case (let outboxAttemptAt?, nil):
            earliestBeginDate = outboxAttemptAt
        case (nil, let todoRefreshAt?):
            earliestBeginDate = todoRefreshAt
        case (nil, nil):
            return .cancel
        }

        return .submit(earliestBeginDate: earliestBeginDate)
    }

    @discardableResult
    private static func replacePendingRequest(earliestBeginDate: Date?) -> Bool {
        let request = BGAppRefreshTaskRequest(identifier: AppConstants.bgSyncTaskIdentifier)
        request.earliestBeginDate = earliestBeginDate
        do {
            // Submitting the same identifier replaces the queued request.
            // Do not cancel first: a failed submit should leave the fallback wake intact.
            try BGTaskScheduler.shared.submit(request)
            logger.info("Background sync request submitted")
            return true
        } catch {
            logger.error("Background sync scheduling failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
