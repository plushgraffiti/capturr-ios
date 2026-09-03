/// This constants helper keeps shared identifiers and preference keys in one place.
/// The app, App Intents, audio import, Watch handling, persistence, and background sync
/// read these values so entitlements, task registration, and stored settings use the
/// same spellings across otherwise separate entry points.

import Foundation

enum AppConstants {
    // App Group suite for shared UserDefaults between the main app and intents.
    // Must match the App Group in Capturr.entitlements.
    static let appGroupSuite = "group.com.pg.capturr.app"

    // Background-refresh task identifier.
    // Must match BGTaskSchedulerPermittedIdentifiers in Capturr/Info.plist.
    static let bgSyncTaskIdentifier = "com.pg.Capturr.bgSync"

    // Cancelled during launch after the background-task identifier rename.
    // Remove after versions using the old identifier are no longer in use.
    static let legacyBgSyncTaskIdentifier = "com.capturr.app.bgSync"

    // Prefix for per-import continued-processing tasks. Each submitted
    // identifier appends the owning OutboxItem UUID.
    static let audioTranscriptionTaskPrefix = "com.pg.Capturr.audioTranscription."

    // History preview text for audio items that haven't been transcribed yet.
    static let transcribingPlaceholder = "Voice note — transcribing…"
}

// UserDefaults key names.
enum DefaultsKey {
    // Capture mode passed from OpenCaptureIntent / quick actions to ContentView.
    // Stored in the app-group suite (AppConstants.appGroupSuite).
    static let intentCaptureMode = "intentCaptureMode"

    // Per-device profile identifier. Stored in UserDefaults.standard.
    static let deviceUUID = "capture.deviceUUID"
}
