/// This manager loads or creates the single local profile stored in SwiftData.
/// `ContentView`, App Intents, and sync paths create it with their model context when
/// they need profile settings. It also migrates the temporary timestamp preferences
/// written by an older app build before returning the profile.

import Foundation
import SwiftData

private enum LegacyTimestampPreferenceKey {
    static let position = "timestamp.position"
    static let formatting = "timestamp.formatting"
}

class ProfileManager {
    private let modelContext: ModelContext
    
    // Device UUID storage for consistent user identification
    static var deviceUUID: String {
        if let storedUUID = UserDefaults.standard.string(forKey: DefaultsKey.deviceUUID) {
            return storedUUID
        } else {
            let newUUID = UUID().uuidString
            UserDefaults.standard.set(newUUID, forKey: DefaultsKey.deviceUUID)
            return newUUID
        }
    }
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // Returns the current user profile, creating one if it doesn't exist
    func getCurrentProfile() throws -> UserProfile {
        // Try to fetch existing profile
        let deviceID = ProfileManager.deviceUUID
        let descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { profile in
                profile.id == deviceID
            }
        )
        
        let existingProfiles = try modelContext.fetch(descriptor)
        
        // If profile exists, migrate any timestamp settings stored by build 100.
        if let profile = existingProfiles.first {
            try migrateLegacyTimestampPreferences(in: profile)
            return profile
        }
        
        // Otherwise create new profile
        let newProfile = UserProfile(
            id: ProfileManager.deviceUUID,
            appAppearance: Appearance.dark,
        )
        modelContext.insert(newProfile)
        let migratedLegacyPreferences = try migrateLegacyTimestampPreferences(in: newProfile)
        if !migratedLegacyPreferences {
            try modelContext.save()
        }
        
        return newProfile
    }

    // Imports timestamp settings written to app-group UserDefaults by build 100.
    // Existing SwiftData values always win. Legacy keys are removed only after
    // their imported values have been saved successfully.
    @discardableResult
    func migrateLegacyTimestampPreferences(in profile: UserProfile) throws -> Bool {
        guard let defaults = UserDefaults(suiteName: AppConstants.appGroupSuite) else {
            return false
        }

        var migratedKeys: [String] = []

        if profile.timestampPositionRaw == nil,
           let rawPosition = defaults.string(forKey: LegacyTimestampPreferenceKey.position),
           TimestampPosition(rawValue: rawPosition) != nil {
            profile.timestampPositionRaw = rawPosition
            migratedKeys.append(LegacyTimestampPreferenceKey.position)
        }

        if profile.timestampFormattingRaw == nil,
           defaults.object(forKey: LegacyTimestampPreferenceKey.formatting) != nil {
            profile.timestampFormattingRaw = defaults.integer(
                forKey: LegacyTimestampPreferenceKey.formatting
            )
            migratedKeys.append(LegacyTimestampPreferenceKey.formatting)
        }

        guard !migratedKeys.isEmpty else { return false }

        try modelContext.save()
        for key in migratedKeys {
            defaults.removeObject(forKey: key)
        }
        return true
    }
}
