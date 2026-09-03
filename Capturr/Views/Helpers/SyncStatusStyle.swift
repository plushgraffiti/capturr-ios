/// This helper gives an outbox item a consistent status icon, color, and label.
/// `HistoryHome` and `TodoPendingRow` use these values to explain whether a capture
/// is transcribing, waiting to sync, complete, or failed. For audio captures, the
/// transcription stage takes priority over the underlying sync status.

import SwiftUI

enum SyncStatusStyle {
    // Awaiting or failed audio still carries a pending sync status, which would mislead the user.
    private static func transcription(for item: OutboxItem) -> TranscriptionState? {
        guard let raw = item.transcriptionState else { return nil }
        return TranscriptionState(rawValue: raw)
    }

    static func icon(for item: OutboxItem) -> String {
        switch transcription(for: item) {
        case .scheduled: return "clock.badge"
        case .awaiting: return "waveform"
        case .failed: return "waveform.badge.exclamationmark"
        default: break
        }
        switch SyncStatus(rawValue: item.status) {
        case .some(.success): return "checkmark.circle"
        case .some(.pending): return "clock"
        case .some(.inProgress): return "arrow.triangle.2.circlepath"
        case .some(.failed): return "xmark.circle"
        default: return "questionmark.circle"
        }
    }

    static func color(for item: OutboxItem) -> Color {
        switch transcription(for: item) {
        case .scheduled: return .blue
        case .awaiting: return .blue
        case .failed: return .orange
        default: break
        }
        switch SyncStatus(rawValue: item.status) {
        case .some(.success): return .green
        case .some(.pending): return .yellow
        case .some(.inProgress): return .blue
        case .some(.failed): return .red
        default: return .gray
        }
    }

    static func label(for item: OutboxItem) -> String {
        switch transcription(for: item) {
        case .scheduled: return "Waiting to transcribe."
        case .awaiting: return "Transcribing…"
        case .failed: return "Transcription failed"
        default: break
        }
        return SyncStatus(rawValue: item.status)?.displayName ?? "Unknown"
    }
}
