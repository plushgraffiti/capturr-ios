/// This suite checks which background wake CAPTURR should request next.
/// Swift Testing gives `BackgroundSyncScheduler` fixed queue states and dates without
/// submitting real iOS tasks. The cases protect immediate work, retry timing, TODO
/// refreshes, hard-error exclusion, transcription ownership, and fallback scheduling.

import Foundation
import Testing
@testable import Capturr

@MainActor
struct BackgroundSyncSchedulingTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: - Queue and TODO Timing

    @Test
    func pendingItemWithoutRetryDateIsImmediatelyEligible() {
        let item = OutboxItem(content: "Ready")

        let decision = BackgroundSyncScheduler.nextScheduleDecision(
            items: [item],
            todosEnabled: false,
            now: now
        )

        #expect(decision == .submit(earliestBeginDate: now))
    }

    @Test
    func offlineRetryRunsBeforeTodoRefresh() {
        let item = OutboxItem(content: "Offline")
        item.nextAttemptAt = now.addingTimeInterval(60)

        let decision = BackgroundSyncScheduler.nextScheduleDecision(
            items: [item],
            todosEnabled: true,
            now: now
        )

        #expect(decision == .submit(earliestBeginDate: now.addingTimeInterval(60)))
    }

    @Test
    func todoRefreshRunsBeforeLaterOutboxRetry() {
        let item = OutboxItem(content: "Retry later")
        item.nextAttemptAt = now.addingTimeInterval(20 * 60)

        let decision = BackgroundSyncScheduler.nextScheduleDecision(
            items: [item],
            todosEnabled: true,
            now: now
        )

        #expect(decision == .submit(earliestBeginDate: now.addingTimeInterval(15 * 60)))
    }

    @Test
    func todoRefreshSchedulesWithoutOutboxWork() {
        let enabledDecision = BackgroundSyncScheduler.nextScheduleDecision(
            items: [],
            todosEnabled: true,
            now: now
        )
        let disabledDecision = BackgroundSyncScheduler.nextScheduleDecision(
            items: [],
            todosEnabled: false,
            now: now
        )

        #expect(enabledDecision == .submit(earliestBeginDate: now.addingTimeInterval(15 * 60)))
        #expect(disabledDecision == .cancel)
    }

    // MARK: - Eligibility Filters

    @Test
    func hardErrorsDoNotScheduleOutboxWork() {
        let item = OutboxItem(content: "Bad credentials")
        item.hardError = true

        let decision = BackgroundSyncScheduler.nextScheduleDecision(
            items: [item],
            todosEnabled: false,
            now: now
        )

        #expect(decision == .cancel)
    }

    @Test
    func transcriptionStateControlsWhetherAudioIsReady() {
        let awaitingItem = OutboxItem(content: "Transcribing")
        awaitingItem.transcriptionState = TranscriptionState.awaiting.rawValue

        let failedItem = OutboxItem(content: "Failed")
        failedItem.transcriptionState = TranscriptionState.failed.rawValue

        let scheduledItem = OutboxItem(content: "System owned")
        scheduledItem.transcriptionState = TranscriptionState.scheduled.rawValue

        let awaitingDecision = BackgroundSyncScheduler.nextScheduleDecision(
            items: [awaitingItem],
            todosEnabled: false,
            now: now
        )
        let failedDecision = BackgroundSyncScheduler.nextScheduleDecision(
            items: [failedItem],
            todosEnabled: false,
            now: now
        )
        let scheduledDecision = BackgroundSyncScheduler.nextScheduleDecision(
            items: [scheduledItem],
            todosEnabled: false,
            now: now
        )

        #expect(awaitingDecision == .submit(earliestBeginDate: now))
        #expect(failedDecision == .cancel)
        #expect(scheduledDecision == .cancel)
    }

    // MARK: - Retry and Fallback Timing

    @Test
    func inProgressItemUsesShortRecoveryGap() {
        let item = OutboxItem(content: "Interrupted")
        item.status = SyncStatus.inProgress.rawValue
        item.lastAttemptAt = now

        let decision = BackgroundSyncScheduler.nextScheduleDecision(
            items: [item],
            todosEnabled: false,
            now: now
        )

        #expect(decision == .submit(earliestBeginDate: now.addingTimeInterval(5)))
    }

    @Test
    func earliestOutboxRetryWinsAcrossSeveralItems() {
        let laterItem = OutboxItem(content: "Later")
        laterItem.nextAttemptAt = now.addingTimeInterval(120)

        let earlierItem = OutboxItem(content: "Earlier")
        earlierItem.nextAttemptAt = now.addingTimeInterval(30)

        let decision = BackgroundSyncScheduler.nextScheduleDecision(
            items: [laterItem, earlierItem],
            todosEnabled: false,
            now: now
        )

        #expect(decision == .submit(earliestBeginDate: now.addingTimeInterval(30)))
    }

    @Test
    func handlerFallbackIsFifteenMinutesAfterEntry() {
        #expect(
            BackgroundSyncScheduler.handlerFallbackDate(from: now)
                == now.addingTimeInterval(15 * 60)
        )
    }
}
