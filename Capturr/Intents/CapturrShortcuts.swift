/// This shortcut provider publishes Capturr's ready-made actions to Siri and Shortcuts.
/// App Intents discovers it through `AppShortcutsProvider` and registers phrases for queuing
/// notes and TODOs, opening voice or general capture, and checking sync status. Each phrase
/// creates one of the intent values declared in this directory.

import AppIntents

struct CapturrShortcuts: AppShortcutsProvider {
    // Siri phrases can interpolate AppEnum or AppEntity values, but not free-form
    // strings. CaptureIntent therefore asks for content after a phrase matches.
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureIntent(type: .note),
            phrases: [
                "Capture in \(.applicationName)",
                "Add note in \(.applicationName)",
                "Quick note in \(.applicationName)"
            ],
            shortTitle: "Capture Note",
            systemImageName: "text.badge.plus"
        )

        AppShortcut(
            intent: CaptureIntent(type: .todo),
            phrases: [
                "Add todo in \(.applicationName)",
                "Quick todo in \(.applicationName)"
            ],
            shortTitle: "Capture Todo",
            systemImageName: "checklist"
        )

        AppShortcut(
            intent: OpenCaptureIntent(mode: .voice),
            phrases: [
                "Start voice capture in \(.applicationName)",
                "Voice note in \(.applicationName)"
            ],
            shortTitle: "Capture Voice",
            systemImageName: "mic"
        )

        AppShortcut(
            intent: GetCaptureStatusIntent(),
            phrases: [
                "Capture status in \(.applicationName)",
                "Check sync in \(.applicationName)"
            ],
            shortTitle: "Get Sync Status",
            systemImageName: "arrow.triangle.2.circlepath"
        )

        AppShortcut(
            intent: OpenCaptureIntent(),
            phrases: [
                "Open capture in \(.applicationName)",
                "Scan document in \(.applicationName)",
                "Scan to \(.applicationName)"
            ],
            shortTitle: "Open CAPTURR",
            systemImageName: "app.badge"
        )
    }
}
