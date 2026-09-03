/// This coordinator turns an audio file chosen by the user into durable capture work.
/// `CaptureVoice` starts new imports and `HistoryHome` retries failed ones; the coordinator
/// validates and copies the file, creates its `OutboxItem`, and arranges continued processing.
/// `CapturrApp` also registers its background-task handler during application launch.

import AVFoundation
import BackgroundTasks
import Foundation
import OSLog
import SwiftData

private let audioImportLogger = Logger(category: "AudioImport")

enum AudioImportError: LocalizedError {
    case tooLong
    case insufficientCapacity
    case invalidAudio
    case fileProvider
    case persistence

    var errorDescription: String? {
        switch self {
        case .tooLong:
            return "Choose an audio file that is 60 minutes or shorter."
        case .insufficientCapacity:
            return "Not enough free storage to import this audio file."
        case .invalidAudio:
            return "That file isn’t a supported audio format."
        case .fileProvider:
            return "Couldn’t download or read this file. Try downloading it in Files first."
        case .persistence:
            return "Couldn’t save this audio import. Please try again."
        }
    }
}

struct PreparedAudioImport: Sendable {
    let id: UUID
    let incomingURL: URL
    let finalFilename: String
    let duration: TimeInterval
}

enum AudioImportPreparer {
    static let maximumDuration: TimeInterval = 60 * 60
    private static let storageReserve: Int64 = 100 * 1_024 * 1_024

    // Coordinates file-provider access, validates, preflights capacity, and
    // stages the complete file away from the main actor.
    static func prepare(sourceURL: URL, id: UUID) async throws -> PreparedAudioImport {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try prepareSynchronously(sourceURL: sourceURL, id: id)
        }.value
    }

    static func duration(of url: URL) async throws -> TimeInterval {
        try await Task.detached(priority: .userInitiated) {
            try validatedDuration(at: url)
        }.value
    }

    private static func prepareSynchronously(sourceURL: URL, id: UUID) throws -> PreparedAudioImport {
        let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var preparedImportResult: Result<PreparedAudioImport, Error>?

        coordinator.coordinate(
            readingItemAt: sourceURL,
            options: [.withoutChanges],
            error: &coordinationError
        ) { coordinatedURL in
            preparedImportResult = Result {
                try Task.checkCancellation()
                let duration = try validatedDuration(at: coordinatedURL)
                guard duration <= maximumDuration else {
                    throw AudioImportError.tooLong
                }

                try preflightCapacity(for: coordinatedURL)

                let sourceExtension = coordinatedURL.pathExtension
                let incomingURL = AudioStorage.incomingURL(
                    for: id,
                    sourceExtension: sourceExtension
                )
                let finalFilename = AudioStorage.finalFilename(
                    for: id,
                    sourceExtension: sourceExtension
                )

                do {
                    try FileManager.default.copyItem(at: coordinatedURL, to: incomingURL)
                    try Task.checkCancellation()
                    let stagedDuration = try validatedDuration(at: incomingURL)
                    guard stagedDuration <= maximumDuration else {
                        throw AudioImportError.tooLong
                    }
                } catch {
                    try? FileManager.default.removeItem(at: incomingURL)
                    if isOutOfSpace(error) {
                        throw AudioImportError.insufficientCapacity
                    }
                    if error is AudioImportError {
                        throw error
                    }
                    throw AudioImportError.fileProvider
                }

                return PreparedAudioImport(
                    id: id,
                    incomingURL: incomingURL,
                    finalFilename: finalFilename,
                    duration: duration
                )
            }
        }

        if let preparedImportResult {
            do {
                return try preparedImportResult.get()
            } catch let error as AudioImportError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw AudioImportError.fileProvider
            }
        }

        if let coordinationError {
            audioImportLogger.error(
                "File coordination failed: \(coordinationError.domain, privacy: .public) \(coordinationError.code): \(coordinationError.localizedDescription, privacy: .public)"
            )
        }
        throw AudioImportError.fileProvider
    }

    private static func validatedDuration(at url: URL) throws -> TimeInterval {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let sampleRate = audioFile.processingFormat.sampleRate
            guard audioFile.length > 0, sampleRate > 0 else {
                throw AudioImportError.invalidAudio
            }

            let frameCount = AVAudioFrameCount(min(audioFile.length, 4_096))
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: audioFile.processingFormat,
                frameCapacity: frameCount
            ) else {
                throw AudioImportError.invalidAudio
            }
            try audioFile.read(into: buffer, frameCount: frameCount)
            guard buffer.frameLength > 0 else {
                throw AudioImportError.invalidAudio
            }
            return Double(audioFile.length) / sampleRate
        } catch let error as AudioImportError {
            throw error
        } catch {
            if isFileProviderAccessError(error) {
                throw AudioImportError.fileProvider
            }
            throw AudioImportError.invalidAudio
        }
    }

    private static func preflightCapacity(for sourceURL: URL) throws {
        let sourceValues = try? sourceURL.resourceValues(forKeys: [
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey,
        ])
        let allocatedSize = Int64(
            sourceValues?.totalFileAllocatedSize
                ?? sourceValues?.fileAllocatedSize
                ?? sourceValues?.fileSize
                ?? 0
        )
        guard allocatedSize > 0 else { return }

        let destinationValues = try? AudioStorage.directory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        guard let availableCapacity = destinationValues?.volumeAvailableCapacityForImportantUsage else {
            return
        }
        guard availableCapacity >= allocatedSize + storageReserve else {
            throw AudioImportError.insufficientCapacity
        }
    }

    private static func isOutOfSpace(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == CocoaError.fileWriteOutOfSpace.rawValue {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isOutOfSpace(underlying)
        }
        return false
    }

    private static func isFileProviderAccessError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == "NSFileProviderErrorDomain" {
            return true
        }
        if nsError.domain == NSCocoaErrorDomain {
            let fileAccessCodes = [
                CocoaError.fileNoSuchFile.rawValue,
                CocoaError.fileReadNoPermission.rawValue,
                CocoaError.fileReadUnknown.rawValue,
            ]
            if fileAccessCodes.contains(nsError.code) {
                return true
            }
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isFileProviderAccessError(underlying)
        }
        return false
    }
}

@MainActor
enum AudioImportCoordinator {
    private static var registeredTaskIdentifiers: Set<String> = []

    // Makes the import durable before publishing its staged audio file. This
    // ordering lets reconciliation finish the rename after any crash window.
    static func importAudio(
        from sourceURL: URL,
        targetGraphId: String?,
        targetGraphName: String,
        modelContext: ModelContext
    ) async throws {
        let id = UUID()
        let prepared = try await AudioImportPreparer.prepare(sourceURL: sourceURL, id: id)
        let item = OutboxItem(content: AppConstants.transcribingPlaceholder, type: .note)
        item.id = id
        item.audioFilename = prepared.finalFilename
        item.transcriptionState = TranscriptionState.awaiting.rawValue
        item.sourceDevice = "import"
        item.targetGraphId = targetGraphId
        item.targetGraphName = targetGraphName

        modelContext.insert(item)
        do {
            try modelContext.save()
            BackgroundSyncScheduler.scheduleAfterEnqueue(itemIDs: [item.id])
        } catch {
            modelContext.delete(item)
            try? modelContext.save()
            try? FileManager.default.removeItem(at: prepared.incomingURL)
            AudioStorage.delete(prepared.finalFilename)
            audioImportLogger.error("Failed to persist audio import \(id): \(error.localizedDescription)")
            throw AudioImportError.persistence
        }

        do {
            try AudioStorage.publishIncomingFile(
                at: prepared.incomingURL,
                as: prepared.finalFilename
            )
        } catch {
            // Keep the hidden staged file for launch reconciliation, but make
            // the current failure visible rather than claiming the import is ready.
            item.transcriptionState = TranscriptionState.failed.rawValue
            item.lastError = "Audio file missing"
            do {
                try modelContext.save()
            } catch {
                audioImportLogger.error(
                    "Failed to persist publish failure \(id): \(error.localizedDescription)"
                )
            }
            audioImportLogger.error("Failed to publish audio import \(id): \(error.localizedDescription)")
            throw AudioImportError.persistence
        }

        _ = schedule(
            item: item,
            duration: prepared.duration,
            modelContext: modelContext
        )
    }

    // Explicit History retry: continued processing is valid because it is
    // directly initiated by the person tapping Retry.
    static func retry(item: OutboxItem, modelContext: ModelContext) async {
        guard let filename = item.audioFilename, AudioStorage.exists(filename) else {
            item.transcriptionState = TranscriptionState.failed.rawValue
            item.lastError = "Audio file missing"
            do {
                try modelContext.save()
            } catch {
                audioImportLogger.error(
                    "Failed to persist missing retry audio \(item.id): \(error.localizedDescription)"
                )
            }
            return
        }

        do {
            let duration = try await AudioImportPreparer.duration(of: AudioStorage.url(for: filename))
            _ = schedule(item: item, duration: duration, modelContext: modelContext)
        } catch {
            item.transcriptionState = TranscriptionState.failed.rawValue
            item.lastError = error.localizedDescription
            do {
                try modelContext.save()
            } catch {
                audioImportLogger.error(
                    "Failed to persist retry validation failure \(item.id): \(error.localizedDescription)"
                )
            }
        }
    }

    static func cancelTask(for item: OutboxItem) {
        BGTaskScheduler.shared.cancel(
            taskRequestWithIdentifier: taskIdentifier(for: item.id)
        )
    }

    // A scheduled value from a prior process no longer has a live registered
    // handler. Restore it to the persisted worker path on the next launch.
    static func recoverAbandonedScheduledItems(modelContext: ModelContext) {
        let items = (try? modelContext.fetch(FetchDescriptor<OutboxItem>())) ?? []
        var changed = false
        for item in items where item.transcriptionState == TranscriptionState.scheduled.rawValue {
            cancelTask(for: item)
            item.transcriptionState = TranscriptionState.awaiting.rawValue
            changed = true
        }
        if changed {
            do {
                try modelContext.save()
            } catch {
                audioImportLogger.error(
                    "Failed to recover scheduled transcriptions: \(error.localizedDescription)"
                )
            }
        }
    }

    private static func schedule(
        item: OutboxItem,
        duration: TimeInterval,
        modelContext: ModelContext
    ) -> Bool {
        item.transcriptionState = TranscriptionState.scheduled.rawValue
        item.lastError = nil
        do {
            try modelContext.save()
        } catch {
            audioImportLogger.error(
                "Failed to mark transcription scheduled \(item.id): \(error.localizedDescription)"
            )
            fallBackToWorker(item: item, modelContext: modelContext)
            return false
        }

        let identifier = taskIdentifier(for: item.id)
        guard registerHandler(
            identifier: identifier,
            itemID: item.id,
            container: SharedModelContainer()
        ) else {
            fallBackToWorker(item: item, modelContext: modelContext)
            return false
        }

        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: "Transcribing audio",
            subtitle: subtitle(for: duration)
        )
        request.strategy = .queue
        request.requiredResources = []

        do {
            try BGTaskScheduler.shared.submit(request)
            audioImportLogger.info("Scheduled continued transcription \(item.id)")
            return true
        } catch {
            audioImportLogger.warning(
                "Continued transcription submission failed for \(item.id): \(error.localizedDescription)"
            )
            fallBackToWorker(item: item, modelContext: modelContext)
            return false
        }
    }

    private static func registerHandler(
        identifier: String,
        itemID: UUID,
        container: ModelContainer
    ) -> Bool {
        if registeredTaskIdentifiers.contains(identifier) {
            return true
        }

        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil
        ) { task in
            guard let continuedTask = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(continuedTask, itemID: itemID, container: container)
        }
        if registered {
            registeredTaskIdentifiers.insert(identifier)
        } else {
            audioImportLogger.error("Registration rejected for \(identifier, privacy: .public)")
        }
        return registered
    }

    private static func handle(
        _ task: BGContinuedProcessingTask,
        itemID: UUID,
        container: ModelContainer
    ) {
        task.progress.totalUnitCount = 1_000
        task.progress.completedUnitCount = 0

        let workTask = Task { @MainActor in
            let worker = TranscriptionWorker(modelContext: container.mainContext)
            let succeeded = await worker.processScheduledItem(itemID: itemID) { fraction in
                task.progress.completedUnitCount = Int64(
                    (min(max(fraction, 0), 1) * 1_000).rounded()
                )
            }

            if succeeded {
                let syncWorker = SyncWorker(modelContext: container.mainContext)
                await syncWorker.drainPendingItems()
            }
            task.setTaskCompleted(success: succeeded)
        }

        task.expirationHandler = {
            workTask.cancel()
        }
    }

    private static func fallBackToWorker(
        item: OutboxItem,
        modelContext: ModelContext
    ) {
        item.transcriptionState = TranscriptionState.awaiting.rawValue
        do {
            try modelContext.save()
        } catch {
            audioImportLogger.error(
                "Failed to persist transcription fallback \(item.id): \(error.localizedDescription)"
            )
            return
        }

        Task { @MainActor in
            let worker = TranscriptionWorker(modelContext: modelContext)
            await worker.processPendingItems()
            let syncWorker = SyncWorker(modelContext: modelContext)
            await syncWorker.drainPendingItems()
        }
    }

    private static func taskIdentifier(for id: UUID) -> String {
        AppConstants.audioTranscriptionTaskPrefix + id.uuidString
    }

    private static func subtitle(for duration: TimeInterval) -> String {
        if duration <= 60 {
            return "Transcribing up to 1 minute of audio"
        }
        let minutes = Int(ceil(duration / 60))
        return "Transcribing \(minutes) minutes of audio"
    }
}
