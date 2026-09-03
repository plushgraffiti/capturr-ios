/// This intent lets Siri and Shortcuts queue a note or TODO without showing a capture screen.
/// App Intents exposes it as an action, while `CapturrShortcuts` registers ready-made note
/// and TODO phrases. It validates the shared profile and saves an `OutboxItem` with any
/// shortcut-specific choices; `SyncWorker` later applies defaults and sends it to Roam.

import AppIntents
import SwiftData

struct CaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture"
    static var description = IntentDescription("Capture a note or todo to Roam Research")
    static var openAppWhenRun: Bool = false

    init() {}

    init(type: CaptureType) {
        self.type = type
    }

    // MARK: - Parameters

    @Parameter(title: "Content")
    var content: String

    @Parameter(title: "Type", default: .note)
    var type: CaptureType

    @Parameter(title: "Graph")
    var graph: GraphEntity?

    @Parameter(title: "Page")
    var page: String?

    @Parameter(title: "Nest Under")
    var nestUnder: String?

    @Parameter(title: "Tags")
    var tags: String?

    @Parameter(title: "Add Timestamp", default: .appDefault)
    var addTimestamp: TimestampOption

    // MARK: - Parameter Summary

    static var parameterSummary: some ParameterSummary {
        Summary("Capture \(\.$content) as \(\.$type)") {
            \.$graph
            \.$page
            \.$nestUnder
            \.$tags
            \.$addTimestamp
        }
    }

    // MARK: - Execution

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<CaptureResult> {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            throw $content.needsValueError("What would you like to capture?")
        }

        let container = SharedModelContainer()
        let context = ModelContext(container)
        let manager = ProfileManager(modelContext: context)

        // A profile record confirms that Capturr has completed its initial setup.
        do {
            _ = try manager.getCurrentProfile()
        } catch {
            throw CaptureIntentError.notConfigured
        }

        let resolvedType: OutboxItemType = (type == .todo) ? .todo : .note

        // The outbox uses nil for the primary graph; additional graphs keep their stable ID.
        let resolvedGraphId: String? = (graph == nil || graph?.id == "primary") ? nil : graph?.id
        let resolvedGraphName: String? = graph?.name

        let item = OutboxItem(content: trimmedContent, type: resolvedType)
        item.targetGraphId = resolvedGraphId
        item.targetGraphName = resolvedGraphName

        // Leaving an override nil tells SyncWorker to use the profile default at send time.
        if let overrideTags = tags {
            item.overrideTags = overrideTags
        }
        if addTimestamp != .appDefault {
            item.overrideTimestamp = (addTimestamp == .yes)
        }
        if let overridePage = page {
            item.overridePage = overridePage
        }
        if let overrideNest = nestUnder {
            item.overrideNestUnder = overrideNest
        }

        context.insert(item)
        try context.save()

        // Re-arm the BG sync task. The main app schedules this on launch and on
        // backgrounding, but a user who only ever triggers Capturr via shortcuts
        // (never opens the app) wouldn't have one queued otherwise.
        BackgroundSyncScheduler.scheduleAfterEnqueue(itemIDs: [item.id])

        let result = CaptureResult(
            id: item.id.uuidString,
            content: trimmedContent,
            status: "queued"
        )

        return .result(value: result)
    }
}

// Main-app execution gives the intent direct access to the shared model container.
extension CaptureIntent {
    static var supportedModes: IntentModes { .foreground(.dynamic) }
}

enum CaptureIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notConfigured

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notConfigured:
            "Please configure Capturr first"
        }
    }
}
