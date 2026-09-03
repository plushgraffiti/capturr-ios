/// This manager receives voice-memo files sent from the paired Apple Watch.
/// The app delegate activates it so deliveries work even when no SwiftUI scene is running.
/// It copies each temporary inbox file before the system removes it, creates durable
/// transcription work in SwiftData, and starts the transcription and sync pipeline.

import Foundation
import AVFoundation
import CryptoKit
import UIKit
import SwiftData
import WatchConnectivity
import OSLog

final class WatchSessionManager: NSObject {
    static let shared = WatchSessionManager()

    private let logger = Logger(category: "WatchSession")
    private var container: ModelContainer?

    func activate(container: ModelContainer) {
        self.container = container
        guard WCSession.isSupported() else {
            logger.info("WCSession not supported on this device")
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    @discardableResult
    private func sendReceiptStatus(
        _ kind: String,
        captureId: UUID,
        using session: WCSession
    ) -> Bool {
        guard session.activationState == .activated else {
            logger.warning("Receipt status \(kind) deferred while WCSession is inactive: \(captureId)")
            return false
        }
        let status: [String: Any] = [
            "kind": kind,
            "id": captureId.uuidString,
        ]

        // The watch is normally still active and showing its pending state, so
        // provide immediate feedback when reachable. Always queue the same
        // status below as a durable fallback for suspension or radio loss.
        if session.isReachable {
            session.sendMessage(status, replyHandler: nil) { [logger] error in
                logger.debug("Immediate receipt status \(kind) failed for \(captureId): \(error.localizedDescription)")
            }
        }
        session.transferUserInfo(status)
        return true
    }

    // Transport completion only proves that Watch Connectivity delivered the
    // temporary inbox file. Tell the watch it may delete its durable copy only
    // after the phone has committed a corresponding OutboxItem.
    private func acknowledgeDurableReceipt(_ captureId: UUID, using session: WCSession) {
        if sendReceiptStatus("audioAck", captureId: captureId, using: session) {
            logger.info("Durable receipt acknowledged: \(captureId)")
        }
    }

    // Ask the watch to retry immediately when the phone could not take durable
    // custody, instead of waiting for the sparse lost-ack fallback timeout.
    private func rejectDurableReceipt(_ captureId: UUID, using session: WCSession) {
        if sendReceiptStatus("audioNack", captureId: captureId, using: session) {
            logger.warning("Durable receipt rejected: \(captureId)")
        }
    }

    // Copies the WC inbox file through a same-volume temporary path, verifies
    // its end-to-end integrity, and proves AVFoundation can decode audio before
    // it becomes the durable destination. An interrupted copy can therefore
    // leave only an ignored .incoming file, never a poisoned destination.
    private func persistValidatedAudio(
        from source: URL,
        to destination: URL,
        metadata: [String: Any]
    ) throws {
        let expectedSize = (metadata["fileSize"] as? NSNumber)?.int64Value
        let expectedHash = (metadata["sha256"] as? String)?.lowercased()

        if FileManager.default.fileExists(atPath: destination.path) {
            do {
                try validateAudio(
                    at: destination,
                    expectedSize: expectedSize,
                    expectedHash: expectedHash
                )
                logger.info("Existing validated audio retained: \(destination.lastPathComponent)")
                return
            } catch {
                let nsError = error as NSError
                logger.warning("Replacing invalid existing audio \(destination.lastPathComponent): \(nsError.domain, privacy: .public) \(nsError.code): \(nsError.localizedDescription, privacy: .public)")
            }
        }

        let temporary = destination.deletingLastPathComponent().appendingPathComponent(
            ".\(destination.lastPathComponent).\(UUID().uuidString).incoming"
        )
        defer { try? FileManager.default.removeItem(at: temporary) }

        try FileManager.default.copyItem(at: source, to: temporary)
        try validateAudio(
            at: temporary,
            expectedSize: expectedSize,
            expectedHash: expectedHash
        )

        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(
                destination,
                withItemAt: temporary,
                backupItemName: nil,
                options: []
            )
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }

    private func validateAudio(
        at url: URL,
        expectedSize: Int64?,
        expectedHash: String?
    ) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let actualSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard actualSize > 0 else { throw ReceivedAudioError.emptyFile }
        if let expectedSize, actualSize != expectedSize {
            throw ReceivedAudioError.sizeMismatch(expected: expectedSize, actual: actualSize)
        }

        if let expectedHash {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let actualHash = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
            guard actualHash == expectedHash else { throw ReceivedAudioError.checksumMismatch }
        }

        let audioFile = try AVAudioFile(forReading: url)
        guard audioFile.length > 0, audioFile.processingFormat.sampleRate > 0 else {
            throw ReceivedAudioError.noAudioFrames
        }
        let frameCount = AVAudioFrameCount(min(audioFile.length, 4_096))
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: frameCount
        ) else {
            throw ReceivedAudioError.couldNotAllocateDecodeBuffer
        }
        try audioFile.read(into: buffer, frameCount: frameCount)
        guard buffer.frameLength > 0 else { throw ReceivedAudioError.noAudioFrames }
    }
}

private enum ReceivedAudioError: LocalizedError {
    case emptyFile
    case sizeMismatch(expected: Int64, actual: Int64)
    case checksumMismatch
    case noAudioFrames
    case couldNotAllocateDecodeBuffer

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "The transferred recording is empty"
        case let .sizeMismatch(expected, actual):
            return "Recording size mismatch (expected \(expected) bytes, received \(actual))"
        case .checksumMismatch:
            return "Recording checksum mismatch"
        case .noAudioFrames:
            return "The recording contains no decodable audio frames"
        case .couldNotAllocateDecodeBuffer:
            return "Could not allocate an audio validation buffer"
        }
    }
}

extension WatchSessionManager: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        if let error {
            logger.error("WCSession activation failed: \(error.localizedDescription)")
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Required after the user switches to a different paired watch
        WCSession.default.activate()
    }

    // A successful file transfer can sit in the iPhone's Watch Connectivity
    // inbox until the companion app gets execution time. A reachable watch
    // sends this lightweight message after transfer completion to prompt that
    // wake-up; the file delegate remains the sole ingestion path.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard message["kind"] as? String == "audioPending",
              let id = message["id"] as? String,
              UUID(uuidString: id) != nil else {
            return
        }
        logger.info("Immediate receipt requested for pending watch audio: \(id)")
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // Take the assertion BEFORE returning from the delegate — a background-
        // resumed process can re-suspend the moment this method returns, and the
        // OutboxItem creation below runs in an async task after that point.
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        DispatchQueue.main.sync {
            bgTask = UIApplication.shared.beginBackgroundTask(withName: "watch.receive") {
                UIApplication.shared.endBackgroundTask(bgTask)
            }
        }
        func release() {
            DispatchQueue.main.async {
                if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask) }
            }
        }

        let metadata = file.metadata ?? [:]

        // The watch capture UUID doubles as OutboxItem id and filename, so
        // duplicate deliveries (re-queued transfers whose completion callback
        // was lost) collapse into one item.
        let idString = (metadata["id"] as? String) ?? UUID().uuidString
        let captureId = UUID(uuidString: idString) ?? UUID()
        let filename = "\(captureId.uuidString).m4a"
        let dest = AudioStorage.url(for: filename)

        // Synchronous copy + validation BEFORE returning — the WC inbox file
        // dies with the delegate. Do not acknowledge until the durable copy is
        // byte-complete and AVFoundation has decoded at least one buffer.
        do {
            try persistValidatedAudio(from: file.fileURL, to: dest, metadata: metadata)
        } catch {
            let nsError = error as NSError
            logger.error("Failed to persist valid received audio \(captureId): \(nsError.domain, privacy: .public) \(nsError.code): \(nsError.localizedDescription, privacy: .public)")
            rejectDurableReceipt(captureId, using: session)
            release()
            return
        }

        // Stamp with the CAPTURE time from the watch, not the delivery time
        let createdAt = (metadata["createdAt"] as? TimeInterval)
            .map { Date(timeIntervalSince1970: $0) } ?? Date()

        guard let container else {
            rejectDurableReceipt(captureId, using: session)
            release() // audio is safe on disk; reconcile can still adopt it next run
            return
        }

        Task { @MainActor in
            defer { release() }

            let context = container.mainContext
            let existing = (try? context.fetch(FetchDescriptor<OutboxItem>())) ?? []
            guard !existing.contains(where: { $0.id == captureId }) else {
                self.logger.info("Duplicate watch delivery ignored: \(captureId)")
                // The existing unique-id match proves a prior receive was
                // committed, so this duplicate can safely acknowledge it too.
                self.acknowledgeDurableReceipt(captureId, using: session)
                return
            }

            let item = OutboxItem(content: AppConstants.transcribingPlaceholder, type: .note)
            item.id = captureId
            item.createdAt = createdAt
            item.audioFilename = filename
            item.transcriptionState = TranscriptionState.awaiting.rawValue
            item.sourceDevice = "watch"   // watch v1 targets the primary graph (targetGraphId nil)
            context.insert(item)
            do {
                try context.save()
                BackgroundSyncScheduler.scheduleAfterEnqueue(itemIDs: [item.id])
            } catch {
                // Do not acknowledge an in-memory-only item. The copied audio
                // remains available for orphan reconciliation and the watch
                // retains its source file for a later re-delivery.
                context.delete(item)
                try? context.save()
                self.logger.error("Failed to persist received watch recording \(captureId): \(error.localizedDescription)")
                self.rejectDurableReceipt(captureId, using: session)
                return
            }
            self.logger.info("Watch recording received: \(captureId)")
            self.acknowledgeDurableReceipt(captureId, using: session)

            // Transcribe + sync inside the background grace window; if it runs
            // out, the persisted awaiting state resumes at next launch.
            let transcriber = TranscriptionWorker(modelContext: context)
            await transcriber.processPendingItems()
            let sync = SyncWorker(modelContext: context)
            await sync.drainPendingItems()
        }
    }
}
