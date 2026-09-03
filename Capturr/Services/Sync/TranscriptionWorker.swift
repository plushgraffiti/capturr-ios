/// This worker turns waiting audio captures into text that the normal sync queue can send.
/// `SyncManager`, audio-import background tasks, and Watch recovery paths call it with
/// durable `OutboxItem` records. It transcribes on-device, saves the transcript before
/// deleting audio, and leaves completed items for `SyncWorker` while retaining failures.

import Foundation
import SwiftData
import OSLog
import UIKit

final class TranscriptionWorker {
    private let modelContext: ModelContext
    private let logger = Logger(category: "TranscriptionWorker")

    private static var inFlight: Set<UUID> = []
    private static var isTicking = false
    // In-memory retry backoff — resets on relaunch, which is the desired
    // "try again next launch" behavior for model-download failures.
    private static var retryState: [UUID: (attempts: Int, nextAt: Date)] = [:]

    private var loop: Task<Void, Never>?
    private let tickIntervalSeconds: UInt64 = 10
    private let maxAttempts = 3

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        let interval = tickIntervalSeconds
        // Weak self so transient workers (background receive, BG refresh) deinit
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.processPendingItems()
                try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
            }
        }
    }

    deinit {
        loop?.cancel()
    }

    @MainActor
    func processPendingItems() async {
        if Self.isTicking { return }
        Self.isTicking = true
        defer { Self.isTicking = false }

        // Every pass, not once per process: orphans can appear at any time
        // (e.g. a background receive whose item-creation task never got to run)
        reconcile()

        let descriptor = FetchDescriptor<OutboxItem>()
        guard let items = try? modelContext.fetch(descriptor) else { return }

        let profile = try? modelContext.fetch(FetchDescriptor<UserProfile>()).first
        let localeTag = profile?.voiceLanguage ?? "en-US"

        let now = Date()
        let candidates = items.filter { item in
            guard item.transcriptionState == TranscriptionState.awaiting.rawValue else { return false }
            if Self.inFlight.contains(item.id) { return false }
            if let retry = Self.retryState[item.id], retry.nextAt > now { return false }
            return true
        }

        for item in candidates {
            await transcribe(item, localeTag: localeTag)
        }
    }

    // Runs only the OutboxItem owned by a per-import continued-processing
    // task. Scheduled items are deliberately invisible to the polling pass.
    @MainActor
    func processScheduledItem(
        itemID: UUID,
        progress: @escaping FileTranscriptionService.ProgressHandler
    ) async -> Bool {
        let items = (try? modelContext.fetch(FetchDescriptor<OutboxItem>())) ?? []
        guard let item = items.first(where: { $0.id == itemID }),
              item.transcriptionState == TranscriptionState.scheduled.rawValue else {
            return false
        }
        guard let filename = item.audioFilename, AudioStorage.exists(filename) else {
            item.transcriptionState = TranscriptionState.failed.rawValue
            item.lastError = "Audio file missing"
            do {
                try modelContext.save()
            } catch {
                logger.error(
                    "Failed to persist missing scheduled audio \(item.id): \(error.localizedDescription)"
                )
            }
            return false
        }
        guard !Self.inFlight.contains(item.id) else { return false }

        let profile = try? modelContext.fetch(FetchDescriptor<UserProfile>()).first
        let localeTag = profile?.voiceLanguage ?? "en-US"
        let originalContent = item.content

        Self.inFlight.insert(item.id)
        defer { Self.inFlight.remove(item.id) }

        let bgTask = TranscriptionBackgroundTask()
        bgTask.begin()
        defer { bgTask.end() }

        for attempt in 1...maxAttempts {
            do {
                try Task.checkCancellation()
                let transcript = try await FileTranscriptionService.transcribe(
                    url: AudioStorage.url(for: filename),
                    localeTag: localeTag,
                    progress: progress
                )
                try Task.checkCancellation()

                if transcript.isEmpty {
                    item.transcriptionState = TranscriptionState.failed.rawValue
                    item.lastError = "No speech detected"
                    try modelContext.save()
                    progress(1)
                    return false
                }

                item.content = transcript
                item.transcriptionState = TranscriptionState.done.rawValue
                item.lastError = nil
                progress(0.96)

                // Transcript durability always precedes deletion of the only
                // audio copy.
                try modelContext.save()
                progress(0.98)
                logger.info("Continued transcription completed \(item.id)")

                do {
                    try AudioStorage.remove(filename)
                    progress(0.99)
                    item.audioFilename = nil
                    try modelContext.save()
                } catch {
                    logger.warning(
                        "Transcript saved but audio cleanup failed for \(item.id): \(error.localizedDescription)"
                    )
                }
                progress(1)
                return true
            } catch is CancellationError {
                // Apple uses the same expiration callback for user cancellation
                // and system expiration. Keep the audio for explicit Retry/Delete.
                if item.transcriptionState != TranscriptionState.done.rawValue {
                    item.content = originalContent
                    item.transcriptionState = TranscriptionState.failed.rawValue
                    item.lastError = "Transcription interrupted"
                    do {
                        try modelContext.save()
                    } catch {
                        logger.error(
                            "Failed to persist interrupted transcription \(item.id): \(error.localizedDescription)"
                        )
                    }
                }
                return false
            } catch {
                if attempt == maxAttempts {
                    item.content = originalContent
                    item.transcriptionState = TranscriptionState.failed.rawValue
                    item.lastError = error.localizedDescription
                    do {
                        try modelContext.save()
                    } catch {
                        logger.error(
                            "Failed to persist transcription failure \(item.id): \(error.localizedDescription)"
                        )
                    }
                    logger.error(
                        "Continued transcription failed for \(item.id): \(error.localizedDescription)"
                    )
                    return false
                }

                item.content = originalContent
                item.transcriptionState = TranscriptionState.scheduled.rawValue
                item.lastError = nil
                logger.warning(
                    "Continued transcription attempt \(attempt) failed, retrying: \(error.localizedDescription)"
                )
                do {
                    try await Task.sleep(for: .seconds(2 * attempt))
                } catch {
                    item.transcriptionState = TranscriptionState.failed.rawValue
                    item.lastError = "Transcription interrupted"
                    do {
                        try modelContext.save()
                    } catch {
                        logger.error(
                            "Failed to persist interrupted transcription \(item.id): \(error.localizedDescription)"
                        )
                    }
                    return false
                }
            }
        }
        return false
    }

    @MainActor
    private func transcribe(_ item: OutboxItem, localeTag: String) async {
        guard let filename = item.audioFilename, AudioStorage.exists(filename) else {
            item.transcriptionState = TranscriptionState.failed.rawValue
            item.lastError = "Audio file missing"
            try? modelContext.save()
            return
        }

        Self.inFlight.insert(item.id)
        defer { Self.inFlight.remove(item.id) }

        let originalContent = item.content
        let originalLastError = item.lastError

        // Hold an assertion across transcription + save — a watch delivery may
        // be the only runtime this process gets (same rationale as SyncWorker).
        let bgTask = TranscriptionBackgroundTask()
        bgTask.begin()
        defer { bgTask.end() }

        do {
            let transcript = try await FileTranscriptionService.transcribe(
                url: AudioStorage.url(for: filename), localeTag: localeTag)

            if transcript.isEmpty {
                // Never silently drop a memo: keep the audio, surface in History
                item.transcriptionState = TranscriptionState.failed.rawValue
                item.lastError = "No speech detected"
                try modelContext.save()
            } else {
                item.content = transcript
                item.transcriptionState = TranscriptionState.done.rawValue
                item.lastError = nil

                // This save is the durability boundary: never remove the only
                // copy of the audio until the completed transcript is committed.
                try modelContext.save()
                Self.retryState[item.id] = nil
                logger.info("Transcribed \(item.id)")

                // Cleanup is deliberately a second transaction. If either the
                // file removal or this save fails, the durable transcript still
                // remains sendable and reconciliation can clean up later.
                do {
                    try AudioStorage.remove(filename)
                    item.audioFilename = nil
                    try modelContext.save()
                } catch {
                    logger.warning("Transcript saved but audio cleanup failed for \(item.id): \(error.localizedDescription)")
                }
            }
        } catch {
            let attempts = (Self.retryState[item.id]?.attempts ?? 0) + 1
            if attempts >= maxAttempts {
                item.transcriptionState = TranscriptionState.failed.rawValue
                item.lastError = error.localizedDescription
                Self.retryState[item.id] = nil
                try? modelContext.save()
                logger.error("Transcription failed for \(item.id): \(error.localizedDescription)")
            } else {
                // A failed persistence attempt may have changed the in-memory
                // model even though the store still contains the awaiting item.
                // Restore the retryable state while retaining the audio.
                item.content = originalContent
                item.transcriptionState = TranscriptionState.awaiting.rawValue
                item.lastError = originalLastError
                let delay = TimeInterval(10 * (1 << attempts))
                Self.retryState[item.id] = (attempts, Date().addingTimeInterval(delay))
                logger.warning("Transcription attempt \(attempts) failed, retrying: \(error.localizedDescription)")
            }
        }
    }

    // Crash-window cleanup in both directions. A matching hidden import stage
    // is published for its already-durable item, stale unmatched stages are
    // removed, visible Watch orphans are adopted, and genuinely missing audio
    // is surfaced instead of being silently dropped.
    @MainActor
    private func reconcile() {
        let descriptor = FetchDescriptor<OutboxItem>()
        guard let items = try? modelContext.fetch(descriptor) else { return }
        var referenced = Set(items.compactMap { $0.audioFilename })
        let knownIds = Set(items.map { $0.id })

        let onDisk = (try? FileManager.default.contentsOfDirectory(
            at: AudioStorage.directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []

        let incomingFiles = onDisk.filter {
            $0.lastPathComponent.hasPrefix(".") &&
                $0.lastPathComponent.contains(".incoming")
        }
        let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for incomingURL in incomingFiles {
            if let id = AudioStorage.incomingItemID(for: incomingURL),
               let item = itemsByID[id],
               let filename = item.audioFilename {
                do {
                    try AudioStorage.publishIncomingFile(at: incomingURL, as: filename)
                    referenced.insert(filename)
                    if item.transcriptionState == TranscriptionState.failed.rawValue,
                       item.lastError == "Audio file missing" {
                        item.transcriptionState = TranscriptionState.awaiting.rawValue
                        item.lastError = nil
                    }
                    logger.info("Published recovered audio import \(id)")
                    continue
                } catch {
                    logger.warning(
                        "Could not publish recovered audio import \(id): \(error.localizedDescription)"
                    )
                }
            }

            let values = try? incomingURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            )
            if let modifiedAt = values?.contentModificationDate,
               Date().timeIntervalSince(modifiedAt) >= 24 * 60 * 60 {
                do {
                    try FileManager.default.removeItem(at: incomingURL)
                    logger.info("Removed stale incoming audio \(incomingURL.lastPathComponent)")
                } catch {
                    logger.warning(
                        "Could not remove stale incoming audio \(incomingURL.lastPathComponent): \(error.localizedDescription)"
                    )
                }
            }
        }

        for url in onDisk where
            !url.lastPathComponent.hasPrefix(".") &&
            !referenced.contains(url.lastPathComponent) {
            let base = url.deletingPathExtension().lastPathComponent
            if let id = UUID(uuidString: base), knownIds.contains(id) {
                // Item exists without a file reference (already transcribed;
                // delete must have failed, or a duplicate delivery) — clean up
                try? FileManager.default.removeItem(at: url)
                continue
            }
            let item = OutboxItem(content: AppConstants.transcribingPlaceholder, type: .note)
            if let id = UUID(uuidString: base) { item.id = id }
            item.audioFilename = url.lastPathComponent
            item.transcriptionState = TranscriptionState.awaiting.rawValue
            item.sourceDevice = "watch"
            modelContext.insert(item)
            logger.warning("Adopted orphaned audio file \(url.lastPathComponent)")
        }

        for item in items where
            item.transcriptionState == TranscriptionState.awaiting.rawValue ||
            item.transcriptionState == TranscriptionState.scheduled.rawValue {
            if let filename = item.audioFilename, !AudioStorage.exists(filename) {
                item.transcriptionState = TranscriptionState.failed.rawValue
                item.lastError = "Audio file missing"
            }
        }

        // A crash between the durable transcript save and best-effort cleanup
        // can leave a done item carrying an obsolete audio reference.
        for item in items where item.transcriptionState == TranscriptionState.done.rawValue {
            guard let filename = item.audioFilename else { continue }
            do {
                try AudioStorage.remove(filename)
                item.audioFilename = nil
            } catch {
                logger.warning("Deferred audio cleanup failed for \(item.id): \(error.localizedDescription)")
            }
        }
        do {
            try modelContext.save()
        } catch {
            logger.error("Audio reconciliation save failed: \(error.localizedDescription)")
        }
    }
}

// Owns a UIKit background-task assertion without capturing a mutable local in
// the sendable expiration handler. All state changes are serialized on the
// main actor, and end() is idempotent for expiration/completion races.
@MainActor
private final class TranscriptionBackgroundTask: @unchecked Sendable {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    func begin() {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "voice.transcription") { [weak self] in
            Task { @MainActor in
                self?.end()
            }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        let activeIdentifier = identifier
        identifier = .invalid
        UIApplication.shared.endBackgroundTask(activeIdentifier)
    }
}
