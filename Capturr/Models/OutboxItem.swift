/// This model is the durable queue record for a capture or TODO update headed to Roam.
/// Capture screens, App Intents, the share extension, and audio workflows save these
/// records in the shared SwiftData store. `SyncWorker` sends them and records the result,
/// while the History and TODO screens read the same state to show progress.

import Foundation
import SwiftData

enum SyncStatus: Int, Codable {
    case pending = 0
    case success = 1
    case failed = 2
    case inProgress = 3

    var displayName: String {
            switch self {
            case .pending: return "Pending"
            case .success: return "Success"
            case .failed: return "Failed"
            case .inProgress: return "In Progress"
            }
        }
}

enum OutboxItemType: Int, Codable {
  case note = 0
  case todo = 1
}

// Tracks an audio item until it becomes normal text that SyncWorker can send.
// A nil OutboxItem.transcriptionState means the item did not enter through an audio workflow.
enum TranscriptionState: Int {
    case awaiting = 0   // audio persisted, transcript not yet produced — not sendable
    case done = 1       // transcript written to content — normal sync applies
    case failed = 2     // transcription failed / no speech — audio kept, retry via History
    case scheduled = 3  // owned by a continued-processing task — polling worker must skip
}

@Model
class OutboxItem {
    // MARK: - Capture and Sync State

    @Attribute(.unique) var id: UUID
    var content: String
    var type: OutboxItemType
    var createdAt: Date
    var sentAt: Date?
    var status: Int
    var lastError: String?
    var attemptCount: Int

    // MARK: - Retry and TODO Update Metadata

    // These remain optional so records saved before the fields were added retain safe defaults.
    var stampAt: Date?          // Legacy redundant field; use createdAt for capture time.
    var lastAttemptAt: Date?    // Most recent send attempt.
    var nextAttemptAt: Date?    // Earliest time a backoff retry may run.
    var hardError: Bool?        // nil is false; true pauses retries until credentials change.

    // TODO toggles use the outbox too: the UID locates the Roam block and the action selects its state.
    var roamBlockUid: String?
    var action: String?         // "mark-done" or "mark-todo"

    // MARK: - Destination

    // A nil graph ID routes to the primary graph; the name is a snapshot for History display.
    var targetGraphId: String?
    var targetGraphName: String?

    // MARK: - Shortcut Overrides

    // CaptureIntent stores only choices made by a shortcut. nil deliberately tells
    // SyncWorker to use the current profile default when it eventually sends the item.
    var overrideTags: String?
    var overrideTimestamp: Bool?
    var overridePage: String?
    var overrideNestUnder: String?

    // MARK: - Audio Transcription

    // TranscriptionWorker owns audio items until their transcript replaces content;
    // completed items then enter the regular sync path without creating a second record.
    var audioFilename: String?        // Stored in AudioStorage.directory.
    var transcriptionState: Int?      // A TranscriptionState raw value; nil means not audio.
    var sourceDevice: String?         // "watch" or "import", used by History.

    // MARK: - Roam Reader Enrichment

    // Reader shares keep the original URL and fetched metadata across retries before
    // SyncWorker builds the final block for Roam's Reading List: Inbox page.
    var isRoamReader: Bool?           // nil is false.
    var rawURL: String?
    var enrichmentAttempts: Int?      // nil is zero.
    var enrichedTitle: String?
    var enrichedDescription: String?
    var enrichedImageURL: String?

    init(content: String, type: OutboxItemType = .note) {
        self.id = UUID()
        self.content = content
        self.type = type
        self.createdAt = Date()
        self.sentAt = nil
        self.status = SyncStatus.pending.rawValue
        self.lastError = nil
        self.attemptCount = 0
    }
}
