/// This view builds the History tab that `ContentView` places beside Capture,
/// TODOs, and Settings. It watches saved `OutboxItem` records, shows what
/// happened to each capture, and lets the user delete entries or recover audio
/// that failed to transcribe. Audio cleanup and retries are handed to
/// `AudioStorage` and `AudioImportCoordinator`.

import SwiftUI
import SwiftData

// These controls appear only for failed transcriptions. Retry hands the saved
// audio back to the import pipeline, while Export gives the user a way to keep
// the recording before deleting or retrying it.
private struct FailedTranscriptionActions: View {
    @Environment(\.modelContext) private var modelContext
    let item: OutboxItem

    var body: some View {
        HStack {
            Button {
                Task {
                    await AudioImportCoordinator.retry(
                        item: item,
                        modelContext: modelContext
                    )
                }
            } label: {
                Label("Retry transcription", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            if let filename = item.audioFilename,
               AudioStorage.exists(filename) {
                ShareLink(item: AudioStorage.url(for: filename)) {
                    Label("Export audio", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.top, 6)
    }
}

struct HistoryHome: View {
    // MARK: - State and Clear Options

    // SwiftData keeps this list current as captures are created or their sync
    // and transcription states change elsewhere in the app.
    @Query(sort: \OutboxItem.createdAt, order: .reverse) var items: [OutboxItem]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var profileViewModel: ProfileViewModel

    // Expansion belongs to this screen rather than the stored capture, so only
    // the IDs of rows currently opened by the user are kept in view state.
    @State private var expandedItemIDs: Set<UUID> = []
    @State private var showClearConfirmation = false
    @State private var selectedClearOption: ClearHistoryOption?

    // A dated option supplies a cutoff; the all case deliberately uses nil so the
    // clearing code can distinguish it from the rolling-day choices.
    enum ClearHistoryOption: Identifiable {
        case olderThan30Days
        case olderThan60Days
        case olderThan90Days
        case all

        var id: Self { self }

        var confirmationMessage: String {
            switch self {
            case .olderThan30Days: return "This will delete all history older than 30 days."
            case .olderThan60Days: return "This will delete all history older than 60 days."
            case .olderThan90Days: return "This will delete all history older than 90 days."
            case .all: return "This will delete all of your history."
            }
        }

        var cutoffDate: Date? {
            let calendar = Calendar.current
            switch self {
            case .olderThan30Days: return calendar.date(byAdding: .day, value: -30, to: Date())
            case .olderThan60Days: return calendar.date(byAdding: .day, value: -60, to: Date())
            case .olderThan90Days: return calendar.date(byAdding: .day, value: -90, to: Date())
            case .all: return nil
            }
        }
    }

    // MARK: - Screen Layout

    var body: some View {
        NavigationView {
            List(items) { item in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedItemIDs.contains(item.id) },
                        set: { isOpen in
                            if isOpen { expandedItemIDs.insert(item.id) } else { expandedItemIDs.remove(item.id) }
                        }
                    )
                ) {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Created:")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(item.createdAt.formatted(.dateTime))
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Sync attempts:")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(item.attemptCount)")
                                .foregroundStyle(.secondary)
                        }
                        if let lastTried = item.lastAttemptAt {
                            HStack {
                                Text("Last tried:")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(lastTried.formatted(.dateTime))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        HStack {
                            Text("Synced:")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(item.sentAt?.formatted(.dateTime) ?? "Not synced")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Graph:")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(graphName(for: item))
                                .foregroundStyle(.secondary)
                        }

                        if item.lastError?.isEmpty == false {
                            VStack(alignment: .leading) {
                                Text("Last response:")
                                    .foregroundStyle(.secondary)

                                Text(item.lastError ?? "")
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .padding(8)
                                    .background(Color.gray.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))

                            }
                            .padding(.top, 10)
                        }

                        if item.transcriptionState == TranscriptionState.failed.rawValue {
                            FailedTranscriptionActions(item: item)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.leading, -16)
                    .font(.subheadline)
                    
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(displayContent(for: item))
                            .font(.body)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        if item.isRoamReader ?? false {
                            Image(systemName: "book")
                                .foregroundStyle(.secondary)
                                .imageScale(.medium)
                                .accessibilityLabel("Roam Reader item")
                        }
                        if item.sourceDevice == "watch" {
                            Image(systemName: "applewatch")
                                .foregroundStyle(.secondary)
                                .imageScale(.medium)
                                .accessibilityLabel("Captured on Apple Watch")
                        }
                        Image(systemName: SyncStatusStyle.icon(for: item))
                            .foregroundStyle(SyncStatusStyle.color(for: item))
                            .imageScale(.medium)
                            .accessibilityLabel(SyncStatusStyle.label(for: item))
                    }
                    .contentShape(Rectangle())
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteItem(item)
                        try? modelContext.save()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
                
            }
            .navigationTitle("History")
            .tint(.primary)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        
                        Button(role: .destructive) {
                            selectedClearOption = .all
                            showClearConfirmation = true
                        } label: {
                            Label("Clear All History", systemImage: "trash")
                        }
                        
                        Divider()
                            
                        Button(role: .destructive) {
                            selectedClearOption = .olderThan30Days
                            showClearConfirmation = true
                        } label: {
                            Label("Older Than 30 Days", systemImage: "trash")
                        }

                        Button(role: .destructive) {
                            selectedClearOption = .olderThan60Days
                            showClearConfirmation = true
                        } label: {
                            Label("Older Than 60 Days", systemImage: "trash")
                        }

                        Button(role: .destructive) {
                            selectedClearOption = .olderThan90Days
                            showClearConfirmation = true
                        } label: {
                            Label("Older Than 90 Days", systemImage: "trash")
                        }

                        
                    } label: {
                        Text("Clear")
                    }
                    .accessibilityLabel("Clear History")
                    .disabled(items.isEmpty)
                }
            }
            .alert("Clear History?", isPresented: $showClearConfirmation, presenting: selectedClearOption) { option in
                Button("Cancel", role: .cancel) {
                    selectedClearOption = nil
                }
                Button("Clear History", role: .destructive) {
                    clearHistory(option: option)
                }
            } message: { option in
                Text(option.confirmationMessage)
            }
        }
    }

    // MARK: - Deletion and Cleanup

    // Deleting a history row also cancels its scheduled transcription and
    // removes any saved recording, preventing invisible work and orphaned audio.
    private func deleteItem(_ item: OutboxItem) {
        AudioImportCoordinator.cancelTask(for: item)
        AudioStorage.delete(item.audioFilename)
        modelContext.delete(item)
    }

    private func clearHistory(option: ClearHistoryOption) {
        // Every selected row uses the same cleanup path as a swipe deletion.
        // A nil cutoff represents the menu's "Clear All History" choice.
        if let cutoffDate = option.cutoffDate {
            let itemsToDelete = items.filter { $0.createdAt < cutoffDate }
            for item in itemsToDelete {
                deleteItem(item)
            }
        } else {
            for item in items {
                deleteItem(item)
            }
        }
        try? modelContext.save()
        selectedClearOption = nil
    }

    // MARK: - Display Formatting

    // Captures remember their destination graph name so History stays readable
    // even for additional graphs; older items fall back to the current primary.
    private func graphName(for item: OutboxItem) -> String {
        if let name = item.targetGraphName, !name.isEmpty {
            return name
        }
        return profileViewModel.graphName ?? "Primary Graph"
    }

    // History needs a short readable preview even though some captures are
    // stored as nested JSON or contain Roam-specific formatting.
    private func displayContent(for item: OutboxItem) -> String {
        // A continued-processing task owns scheduled audio, so there is no
        // transcript available to preview yet.
        if item.transcriptionState == TranscriptionState.scheduled.rawValue {
            return "Waiting to transcribe."
        }

        // Reader imports can appear before enrichment finishes. Prefer the
        // enriched title, then the share-time page title, then the original URL.
        if item.isRoamReader ?? false {
            if let title = item.enrichedTitle, !title.isEmpty { return stripRoamMarkup(title) }
            if !item.content.isEmpty { return stripRoamMarkup(item.content) }
            if let url = item.rawURL, !url.isEmpty { return url }
            return "Roam Reader item"
        }
        return stripRoamMarkup(extractText(from: item.content))
    }

    // Write/scan captures store block trees as JSON. Flatten known formats
    // for the row preview, but leave ordinary note and TODO text unchanged.
    private func extractText(from content: String) -> String {
        guard let data = content.data(using: .utf8) else { return content }

        // The block editor wraps its tree in a NestedCapture value.
        if let capture = try? JSONDecoder().decode(NestedCapture.self, from: data) {
            let texts = capture.blocks.flatMap { flattenBlockText($0) }
            return texts.joined(separator: " / ")
        }

        // Document scanning stores its block tree as a bare RoamBlock array.
        if let blocks = try? JSONDecoder().decode([RoamBlock].self, from: data) {
            let texts = blocks.flatMap { flattenBlockText($0) }
            return texts.joined(separator: " / ")
        }

        return content
    }

    // Walk parent and child blocks in display order, dropping blank nodes so
    // the preview can join the remaining text into one compact line.
    private func flattenBlockText(_ block: RoamBlock) -> [String] {
        var result: [String] = []
        let trimmed = block.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result.append(trimmed)
        }
        for child in block.children {
            result.append(contentsOf: flattenBlockText(child))
        }
        return result
    }

    // History is a plain-text summary, so remove Roam's editing syntax without
    // changing the content stored in the OutboxItem.
    // FIXME: Want to investigate other approaches to this, not a fan
    private func stripRoamMarkup(_ text: String) -> String {
        var cleanedText = text
        // TODO/DONE markers
        cleanedText = cleanedText.replacingOccurrences(of: "{{[[TODO]]}}", with: "TODO:")
        cleanedText = cleanedText.replacingOccurrences(of: "{{[[DONE]]}}", with: "DONE:")
        // Page refs: [[page name]] → page name
        cleanedText = cleanedText.replacingOccurrences(of: "\\[\\[([^\\]]+)\\]\\]", with: "$1", options: .regularExpression)
        // Highlights: ^^text^^ → text
        cleanedText = cleanedText.replacingOccurrences(of: "\\^\\^([^\\^]+)\\^\\^", with: "$1", options: .regularExpression)
        // Bold: **text** → text
        cleanedText = cleanedText.replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "$1", options: .regularExpression)
        // Italics: __text__ → text
        cleanedText = cleanedText.replacingOccurrences(of: "__([^_]+)__", with: "$1", options: .regularExpression)
        // Block refs: ((block-uid)) → (ref)
        cleanedText = cleanedText.replacingOccurrences(of: "\\(\\([a-zA-Z0-9_-]+\\)\\)", with: "(ref)", options: .regularExpression)
        // Roam table marker
        cleanedText = cleanedText.replacingOccurrences(of: "{{table}}", with: "Table:")
        // Collapse whitespace
        cleanedText = cleanedText.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
