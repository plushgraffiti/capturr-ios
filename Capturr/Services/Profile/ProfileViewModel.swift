/// This view model exposes profile settings in a form that SwiftUI views can observe and edit.
/// `CapturrApp` creates the shared instance, `ContentView` loads the SwiftData profile into it,
/// and capture, onboarding, settings, History, and TODO screens read or update its values.
/// It copies changes back to the underlying profile and model context when asked to save.

import Foundation
import SwiftUI
import SwiftData

class ProfileViewModel: ObservableObject {
    @Published var appAppearance: Appearance = .system
    @Published var isProfileReady: Bool = false
    @Published var graphName: String?
    @Published var defaultTag: String?
    @Published var addTimestamp: Bool = false
    @Published var timestampPosition: TimestampPosition = .append
    @Published var timestampFormatting = TimestampFormatOptions(rawValue: 0)
    @Published var useDailyNotes: Bool = true
    @Published var customLocation: String?
    @Published var customBlock: String?
    @Published var shareFormatLinks: Bool = false
    @Published var roamReaderEnabled: Bool = false
    @Published var voiceLanguage: String = "en-US"

    // TODOs feature settings
    @Published var todosEnabled: Bool = false
    @Published var todosTagFilter: String?
    @Published var todosExcludeTagFilter: String?
    @Published var todosTimePeriod: Int = 30
    @Published var todosShowCompleted: Bool = true
    @Published var todosBadgeEnabled: Bool = false

    // Badge count (updated by TodosHome, read by ContentView)
    @Published var todosBadgeCount: Int = 0

    // Multi-graph feature
    @Published var multiGraphEnabled: Bool = false
    @Published var multiGraphDefaultToLast: Bool = false
    @Published var additionalGraphs: [AdditionalGraph] = []
    @Published var lastUsedGraphId: String?

    var modelContext: ModelContext!
    var profileManager: ProfileManager?
    
    // Reference to the actual profile model
    private var profileModel: UserProfile?
    
    // Updates view model with data from the profile
    func updateViewModel(with profile: UserProfile) {
        self.profileModel = profile
        self.appAppearance = profile.appAppearance
        self.graphName = profile.graphName
        self.defaultTag = profile.defaultTag
        self.addTimestamp = profile.addTimestamp
        self.timestampPosition = profile.timestampPosition
        self.timestampFormatting = profile.timestampFormatting
        self.useDailyNotes = profile.useDailyNotes
        self.customLocation = profile.customLocation
        self.customBlock = profile.customBlock
        self.shareFormatLinks = profile.shareFormatLinks
        self.roamReaderEnabled = profile.roamReaderEnabled
        self.voiceLanguage = profile.voiceLanguage
        self.todosEnabled = profile.todosEnabled
        self.todosTagFilter = profile.todosTagFilter
        self.todosExcludeTagFilter = profile.todosExcludeTagFilter
        self.todosTimePeriod = profile.todosTimePeriod
        self.todosShowCompleted = profile.todosShowCompleted
        self.todosBadgeEnabled = profile.todosBadgeEnabled
        self.multiGraphEnabled = profile.multiGraphEnabled ?? false
        self.multiGraphDefaultToLast = profile.multiGraphDefaultToLast ?? false
        self.additionalGraphs = profile.additionalGraphs
        self.lastUsedGraphId = profile.lastUsedGraphId
        self.isProfileReady = true
    }
    
    // Updates the profile model with current view model data
    func saveChanges(context: ModelContext) throws {
        guard let profile = profileModel else {
            return
        }
        
        // Update and save regardless to ensure consistency
        profile.appAppearance = appAppearance
        profile.graphName = graphName
        profile.defaultTag = defaultTag
        profile.addTimestamp = addTimestamp
        profile.timestampPosition = timestampPosition
        profile.timestampFormatting = timestampFormatting
        profile.useDailyNotes = useDailyNotes
        profile.customLocation = customLocation
        profile.customBlock = customBlock
        profile.shareFormatLinks = shareFormatLinks
        profile.roamReaderEnabled = roamReaderEnabled
        profile.voiceLanguage = voiceLanguage
        profile.todosEnabled = todosEnabled
        profile.todosTagFilter = todosTagFilter
        profile.todosExcludeTagFilter = todosExcludeTagFilter
        profile.todosTimePeriod = todosTimePeriod
        profile.todosShowCompleted = todosShowCompleted
        profile.todosBadgeEnabled = todosBadgeEnabled
        profile.multiGraphEnabled = multiGraphEnabled
        profile.multiGraphDefaultToLast = multiGraphDefaultToLast
        profile.additionalGraphs = additionalGraphs
        profile.lastUsedGraphId = lastUsedGraphId
        try context.save()
    }

    // MARK: - Multi-graph helpers

    // Check if a graph name is unique (for validation in add/edit forms)
    func isGraphNameUnique(_ name: String, excludingId: String? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        // Check against primary graph
        if let primaryName = graphName, primaryName.lowercased() == trimmed.lowercased() {
            return false
        }
        // Check against additional graphs (excluding the one being edited)
        return !additionalGraphs.contains { graph in
            graph.id != excludingId && graph.name.lowercased() == trimmed.lowercased()
        }
    }

    // Get the effective last used graph ID (falls back to nil/primary if graph deleted)
    func effectiveLastUsedGraphId() -> String? {
        guard let lastId = lastUsedGraphId else { return nil }
        // Verify the graph still exists
        if additionalGraphs.contains(where: { $0.id == lastId }) {
            return lastId
        }
        // Graph was deleted, fall back to primary
        return nil
    }

    // Get display name for a graph ID (nil = primary)
    func graphDisplayName(for graphId: String?) -> String {
        if let id = graphId, let graph = additionalGraphs.first(where: { $0.id == id }) {
            return graph.name
        }
        return graphName ?? "Primary Graph"
    }
}
