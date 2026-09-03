/// This suite checks how a finished Roam request changes a saved outbox item.
/// Swift Testing gives `SyncWorker` an in-memory store plus fixed errors, dates,
/// and backoff delays without contacting the network. The cases protect offline
/// deferral, counted failures, auth hard errors, and successful delivery.

import Foundation
import SwiftData
import Testing
@testable import Capturr

@MainActor
struct SyncRetryPolicyTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: - Offline and Transport Failures

    @Test
    func knownOfflineErrorsPreserveHistoryAndDeferForSixtySeconds() throws {
        let offlineErrors = [
            URLError(.notConnectedToInternet),
            URLError(.dataNotAllowed),
            URLError(.internationalRoamingOff),
        ]

        for error in offlineErrors {
            let (worker, item) = try makeWorkerAndItem(
                attemptCount: 2,
                lastError: "Previous response",
                nextAttemptAt: now.addingTimeInterval(-10)
            )

            let result = worker.persistSendResult(
                .failure(error),
                for: item,
                now: now,
                retryDelay: { _, _ in 999 }
            )

            #expect(result == .offline)
            #expect(item.status == SyncStatus.pending.rawValue)
            #expect(item.attemptCount == 2)
            #expect(item.lastError == "Previous response")
            #expect(item.nextAttemptAt == now.addingTimeInterval(60))
            #expect(item.hardError == false)
        }
    }

    @Test
    func wrappedReaderOfflineErrorIsStillRecognized() throws {
        let (worker, _) = try makeWorkerAndItem(attemptCount: 0, lastError: nil)
        let wrappedError = LinkMetadataError.fetchFailed(
            URLError(.notConnectedToInternet)
        )

        #expect(worker.isKnownOfflineError(wrappedError))
    }

    @Test
    func ambiguousTransportErrorsRemainCountedFailures() throws {
        let transportErrors = [
            URLError(.networkConnectionLost),
            URLError(.timedOut),
            URLError(.dnsLookupFailed),
            URLError(.cannotConnectToHost),
        ]

        for error in transportErrors {
            let (worker, item) = try makeWorkerAndItem(
                attemptCount: 1,
                lastError: nil
            )

            let result = worker.persistSendResult(
                .failure(error),
                for: item,
                now: now,
                retryDelay: { _, _ in 20 }
            )

            #expect(result == .sendFailure)
            #expect(item.attemptCount == 2)
            #expect(item.lastError == error.localizedDescription)
            #expect(item.nextAttemptAt == now.addingTimeInterval(20))
            #expect(item.hardError == false)
        }
    }

    // MARK: - Delivery Results

    @Test
    func authResponseRetriesBeforeSharedAttemptThreshold() throws {
        let (worker, item) = try makeWorkerAndItem(attemptCount: 1, lastError: nil)
        let error = RoamAPIError(message: "HTTP 401", statusCode: 401)

        let result = worker.persistSendResult(
            .failure(error),
            for: item,
            now: now,
            retryDelay: { _, statusCode in
                #expect(statusCode == 401)
                return 60
            }
        )

        #expect(result == .sendFailure)
        #expect(item.attemptCount == 2)
        #expect(item.nextAttemptAt == now.addingTimeInterval(60))
        #expect(item.hardError == false)
    }

    @Test
    func authResponseBecomesHardOnThirdCountedAttempt() throws {
        let (worker, item) = try makeWorkerAndItem(attemptCount: 2, lastError: nil)
        let error = RoamAPIError(message: "HTTP 403", statusCode: 403)

        let result = worker.persistSendResult(
            .failure(error),
            for: item,
            now: now,
            retryDelay: { _, _ in 60 }
        )

        #expect(result == .sendFailure)
        #expect(item.attemptCount == 3)
        #expect(item.nextAttemptAt == nil)
        #expect(item.hardError == true)
    }

    @Test
    func serverFailureUsesCountedAttemptBackoff() throws {
        let (worker, item) = try makeWorkerAndItem(attemptCount: 0, lastError: nil)
        let error = RoamAPIError(message: "HTTP 503", statusCode: 503)

        let result = worker.persistSendResult(
            .failure(error),
            for: item,
            now: now,
            retryDelay: { attemptCount, statusCode in
                #expect(attemptCount == 1)
                #expect(statusCode == 503)
                return 12
            }
        )

        #expect(result == .sendFailure)
        #expect(item.attemptCount == 1)
        #expect(item.lastError == "HTTP 503")
        #expect(item.nextAttemptAt == now.addingTimeInterval(12))
    }

    @Test
    func successRecordsDeliveryAndClearsRetryState() throws {
        let (worker, item) = try makeWorkerAndItem(
            attemptCount: 2,
            lastError: "HTTP 500",
            nextAttemptAt: now.addingTimeInterval(30)
        )

        let result = worker.persistSendResult(
            .success(()),
            for: item,
            now: now,
            retryDelay: { _, _ in 999 }
        )

        #expect(result == .success)
        #expect(item.status == SyncStatus.success.rawValue)
        #expect(item.attemptCount == 3)
        #expect(item.sentAt == now)
        #expect(item.lastError == "OK")
        #expect(item.nextAttemptAt == nil)
        #expect(item.hardError == false)
    }

    private func makeWorkerAndItem(
        attemptCount: Int,
        lastError: String?,
        nextAttemptAt: Date? = nil
    ) throws -> (worker: SyncWorker, item: OutboxItem) {
        let container = try InMemoryModelContainer.make()
        let context = ModelContext(container)
        let item = OutboxItem(content: "Test capture")
        item.attemptCount = attemptCount
        item.lastError = lastError
        item.nextAttemptAt = nextAttemptAt
        item.hardError = false
        context.insert(item)
        try context.save()
        return (SyncWorker(modelContext: context), item)
    }
}
