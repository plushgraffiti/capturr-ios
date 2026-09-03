/// This model is the shared SwiftData record for the app's capture and display settings.
/// `ProfileManager` loads or creates the single record, and `ProfileViewModel` exposes it
/// to onboarding and settings screens. Sync workers, background tasks, App Intents, and
/// the share extension read the same saved preferences when they work without those screens.

import Foundation
import SwiftData

@Model
class UserProfile {
    // MARK: - Capture and Display Preferences

    var id: String
    
    var appAppearanceRaw: String = Appearance.system.rawValue
    var appAppearance: Appearance {
        get { Appearance(rawValue: appAppearanceRaw) ?? .system }
        set { appAppearanceRaw = newValue.rawValue }
    }
    var graphName: String?
    var defaultTag: String?
    var addTimestamp: Bool = false

    // nil raw values preserve the standard timestamp defaults for older saved profiles.
    var timestampPositionRaw: String?
    var timestampFormattingRaw: Int?

    var useDailyNotes: Bool = true
    var customLocation: String?
    var customBlock: String?
    var shareFormatLinks: Bool = false
    var roamReaderEnabled: Bool = false
    var voiceLanguage: String = "en-US"

    // MARK: - TODO Preferences

    var todosEnabled: Bool = false
    var todosTagFilter: String?
    var todosExcludeTagFilter: String?
    var todosTimePeriod: Int = 30
    var todosShowCompleted: Bool = true
    var todosBadgeEnabled: Bool = false

    // MARK: - Multiple Graph Preferences

    // Optional fields give profiles saved before multi-graph support safe false/empty defaults.
    var multiGraphEnabled: Bool?
    var multiGraphDefaultToLast: Bool?

    // Graph names and IDs are JSON encoded here; their API tokens stay in Keychain.
    var additionalGraphsData: Data?
    var lastUsedGraphId: String?           // Supports the "default to last" capture choice.

    // MARK: - Typed Timestamp Settings

    var timestampPosition: TimestampPosition {
        get {
            guard let rawValue = timestampPositionRaw else { return .append }
            return TimestampPosition(rawValue: rawValue) ?? .append
        }
        set {
            timestampPositionRaw = newValue.rawValue
        }
    }

    var timestampFormatting: TimestampFormatOptions {
        get {
            TimestampFormatOptions(rawValue: timestampFormattingRaw ?? 0)
        }
        set {
            timestampFormattingRaw = newValue.rawValue
        }
    }

    init(
        id: String = UUID().uuidString,
        appAppearance: Appearance = .dark
    ) {
        self.id = id
        self.appAppearanceRaw = appAppearance.rawValue
    }

    // Views work with normal graph values while this accessor handles their encoded storage.
    var additionalGraphs: [AdditionalGraph] {
        get {
            guard let data = additionalGraphsData else { return [] }
            do {
                return try JSONDecoder().decode([AdditionalGraph].self, from: data)
            } catch {
                // A damaged graph list must not prevent the rest of the profile from loading.
                return []
            }
        }
        set {
            additionalGraphsData = try? JSONEncoder().encode(newValue)
        }
    }

}

// MARK: - Supporting Types

// Describes an additional capture destination. CredentialsManager stores its token
// separately in Keychain under this stable ID.
struct AdditionalGraph: Codable, Identifiable, Equatable {
    var id: String
    var name: String

    init(id: String = UUID().uuidString, name: String) {
        self.id = id
        self.name = name
    }
}

// Settings screens use these values for the app-wide preferred color scheme.
enum Appearance: String, Codable, CaseIterable, Identifiable {
    case light
    case dark
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light:
            let message = NSLocalizedString("Light", comment: "Light mode for app appearance")
            return message
            
        case .dark:
            let message = NSLocalizedString("Dark", comment: "Dark mode for app appearance")
            return message
            
        case .system:
            let message = NSLocalizedString("System", comment: "System mode for app appearance")
            return message
            
        }
    }
}

enum TimestampPosition: String, Codable, CaseIterable, Identifiable {
    case append
    case prepend

    var id: String { rawValue }

    var title: String {
        switch self {
        case .append:
            return "Append"
        case .prepend:
            return "Prepend"
        }
    }
}

struct TimestampFormatOptions: OptionSet {
    // The bitmask allows several pieces of Roam formatting to be enabled together.
    let rawValue: Int

    static let bold = TimestampFormatOptions(rawValue: 1 << 0)
    static let italic = TimestampFormatOptions(rawValue: 1 << 1)
    static let highlight = TimestampFormatOptions(rawValue: 1 << 2)
}
