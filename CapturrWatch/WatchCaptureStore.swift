/// This store is the Watch app's durable outbox for finished voice recordings.
/// `WatchRecorder` adds files, and `WatchAppDelegate` activates or retries transfers across
/// launches. Each audio file and its JSON metadata remain on the Watch until the phone's
/// `WatchSessionManager` confirms a matching SwiftData outbox item; capture UUIDs make retries
/// safe because the phone can recognize duplicate deliveries.

import Foundation
import CryptoKit
import WatchConnectivity
import OSLog

private let logger = Logger(subsystem: "com.capturr.app", category: "WatchCaptureStore")

final class WatchCaptureStore: NSObject, ObservableObject {
    static let shared = WatchCaptureStore()

    // MARK: - Persisted State

    // Includes recordings queued, transferring, or awaiting durable phone acknowledgement.
    @Published private(set) var pendingCount = 0

    struct Entry: Codable {
        var createdAt: TimeInterval
        var duration: TimeInterval
        // Older index entries decode missing integrity values as nil and fill them on retry.
        var fileSize: Int64? = nil
        var sha256: String? = nil
        // A fresh value means Watch Connectivity staged a phone-side inbox copy,
        // so ordinary wrist activations should not create another transfer.
        var awaitingAcknowledgementSince: TimeInterval? = nil
        // Handles a phone rejection arriving before the sender-side completion callback.
        var retryRequested: Bool? = nil
    }

    private var index: [String: Entry] = [:]   // capture UUID → metadata

    // A lost acknowledgement falls back to a sparse retry because a terminated
    // phone app can legitimately leave its staged inbox file waiting for hours.
    private let acknowledgementRetryInterval: TimeInterval = 6 * 60 * 60

    static var recordingsDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var indexURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("outbox-index.json")
    }

    override init() {
        super.init()
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            index = decoded
        }
        refreshPendingCount()
    }

    // MARK: - Session

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Outbox

    // Registers a finalized recording before asking Watch Connectivity to transfer it.
    func add(id: UUID, fileURL: URL, duration: TimeInterval) {
        index[id.uuidString] = Entry(
            createdAt: Date().timeIntervalSince1970,
            duration: duration,
            fileSize: Self.fileSize(at: fileURL),
            sha256: Self.sha256(at: fileURL)
        )
        saveIndex()
        queueTransfer(id: id.uuidString, fileURL: fileURL)
        refreshPendingCount()
    }

    // Reconciles disk, the JSON index, and Watch Connectivity's live queue after interruptions.
    func requeueStale() {
        guard WCSession.default.activationState == .activated else {
            logger.debug("Deferring stale transfer scan until WCSession activates")
            refreshPendingCount()
            return
        }

        let queued = Set(WCSession.default.outstandingFileTransfers.map {
            $0.file.fileURL.deletingPathExtension().lastPathComponent
        })
        let onDisk = (try? FileManager.default.contentsOfDirectory(
            at: Self.recordingsDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let now = Date().timeIntervalSince1970

        for url in onDisk where url.pathExtension == "m4a" {
            let id = url.deletingPathExtension().lastPathComponent
            guard !queued.contains(id) else { continue }
            // File without an index entry = crash between finalize and add()
            if index[id] == nil {
                let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? Date()
                index[id] = Entry(
                    createdAt: mtime.timeIntervalSince1970,
                    duration: -1,
                    fileSize: Self.fileSize(at: url),
                    sha256: Self.sha256(at: url)
                )
                saveIndex()
                logger.warning("Adopted orphaned recording \(id)")
            }

            if let awaitingSince = index[id]?.awaitingAcknowledgementSince,
               now - awaitingSince < acknowledgementRetryInterval {
                continue
            }
            if index[id]?.awaitingAcknowledgementSince != nil {
                logger.warning("Phone acknowledgement timed out; retrying transfer: \(id)")
            }
            queueTransfer(id: id, fileURL: url)
        }
        refreshPendingCount()
    }

    private func queueTransfer(id: String, fileURL: URL) {
        guard WCSession.default.activationState == .activated else {
            // The file and index are already durable. activationDidComplete
            // invokes requeueStale(), so no polling or lossy fallback is needed.
            logger.debug("Transfer retained until WCSession activates: \(id)")
            return
        }

        if var entry = index[id] {
            entry.awaitingAcknowledgementSince = nil
            entry.retryRequested = nil
            index[id] = entry
            saveIndex()
        }

        var entry = index[id]
        if entry?.fileSize == nil || entry?.sha256 == nil {
            entry?.fileSize = Self.fileSize(at: fileURL)
            entry?.sha256 = Self.sha256(at: fileURL)
            if let entry {
                index[id] = entry
                saveIndex()
            }
        }

        var metadata: [String: Any] = [
            "kind": "audio",
            "id": id,
            "createdAt": entry?.createdAt ?? Date().timeIntervalSince1970,
            "duration": entry?.duration ?? -1,
        ]
        if let fileSize = entry?.fileSize { metadata["fileSize"] = fileSize }
        if let sha256 = entry?.sha256 { metadata["sha256"] = sha256 }
        WCSession.default.transferFile(fileURL, metadata: metadata)
        logger.info("Transfer queued: \(id)")
    }

    private static func fileSize(at url: URL) -> Int64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value
    }

    private static func sha256(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // transferFile remains the durable transport. This best-effort message only
    // asks a reachable iPhone app to wake and drain its staged inbox file sooner.
    private func nudgePhoneForReceipt(id: String, using session: WCSession) {
        guard session.activationState == .activated, session.isReachable else {
            logger.debug("Phone unavailable for immediate receipt request: \(id)")
            return
        }

        session.sendMessage([
            "kind": "audioPending",
            "id": id,
        ], replyHandler: nil) { error in
            logger.debug("Immediate phone receipt request failed for \(id): \(error.localizedDescription)")
        }
        logger.info("Immediate phone receipt requested: \(id)")
    }

    // Removes the Watch source only after the phone commits the matching OutboxItem.
    private func confirmDurableReceipt(id: String) {
        let fileURL = Self.recordingsDir.appendingPathComponent("\(id).m4a")
        guard index[id] != nil || FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.debug("Duplicate phone acknowledgement ignored: \(id)")
            return
        }
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            index[id] = nil
            saveIndex()
            logger.info("Delivered and acknowledged: \(id)")
        } catch {
            // Keep both the file and index so a later acknowledgement or launch
            // can retry cleanup without sacrificing the recording.
            logger.error("Couldn't remove acknowledged recording \(id): \(error.localizedDescription)")
        }
        refreshPendingCount()
    }

    // A phone rejection clears the acknowledgement wait and retries without deleting the source.
    private func retryRejectedReceipt(id: String) {
        let fileURL = Self.recordingsDir.appendingPathComponent("\(id).m4a")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.error("Phone rejected \(id), but the watch source is missing")
            return
        }

        if var entry = index[id] {
            entry.awaitingAcknowledgementSince = nil
            entry.retryRequested = true
            index[id] = entry
            saveIndex()
        }

        let alreadyQueued = WCSession.default.outstandingFileTransfers.contains {
            $0.file.fileURL.deletingPathExtension().lastPathComponent == id
        }
        if !alreadyQueued {
            logger.warning("Phone rejected durable receipt; retrying transfer: \(id)")
            queueTransfer(id: id, fileURL: fileURL)
        } else {
            logger.warning("Phone rejected durable receipt; retry armed after current transfer: \(id)")
        }
        refreshPendingCount()
    }

    private func saveIndex() {
        if let data = try? JSONEncoder().encode(index) {
            try? data.write(to: indexURL)
        }
    }

    private func refreshPendingCount() {
        let count = index.count
        DispatchQueue.main.async { self.pendingCount = count }
    }
}

extension WatchCaptureStore: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        if let error {
            logger.error("WCSession activation failed: \(error.localizedDescription)")
            return
        }
        DispatchQueue.main.async {
            self.requeueStale()
        }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let url = fileTransfer.file.fileURL
        let id = url.deletingPathExtension().lastPathComponent
        DispatchQueue.main.async {
            if let error {
                // Leave file + index in place — requeueStale retries on next launch
                logger.error("Transfer failed for \(id): \(error.localizedDescription)")
                if self.index[id]?.retryRequested == true {
                    logger.warning("Executing phone-requested retry after transfer error: \(id)")
                    self.queueTransfer(id: id, fileURL: url)
                }
            } else {
                // Delivery into the phone's temporary WC inbox is not yet durable.
                // Persist this state so wrist wakes do not generate duplicates.
                if self.index[id]?.retryRequested == true {
                    logger.warning("Executing phone-requested retry: \(id)")
                    self.queueTransfer(id: id, fileURL: url)
                } else if var entry = self.index[id] {
                    entry.awaitingAcknowledgementSince = Date().timeIntervalSince1970
                    self.index[id] = entry
                    self.saveIndex()
                    logger.info("Transfer finished; awaiting phone acknowledgement: \(id)")
                    self.nudgePhoneForReceipt(id: id, using: session)
                }
            }
            self.refreshPendingCount()
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handleReceiptStatus(userInfo)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleReceiptStatus(message)
    }

    private func handleReceiptStatus(_ status: [String: Any]) {
        guard let kind = status["kind"] as? String,
              let id = status["id"] as? String,
              UUID(uuidString: id) != nil else {
            return
        }
        DispatchQueue.main.async {
            switch kind {
            case "audioAck":
                self.confirmDurableReceipt(id: id)
            case "audioNack":
                self.retryRejectedReceipt(id: id)
            default:
                break
            }
        }
    }
}
