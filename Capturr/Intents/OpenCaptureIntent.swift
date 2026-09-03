/// This intent opens Capturr directly to a chosen interactive capture mode.
/// `CapturrShortcuts` registers it for voice and general capture phrases, and App Intents
/// launches the app because microphone and camera flows need their UI. It passes the route
/// through app-group defaults, then `ContentView` reads and clears it when the app activates.

import AppIntents

struct OpenCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Open CAPTURR"
    static var description = IntentDescription("Open CAPTURR to a specific capture mode")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Mode")
    var mode: CaptureMode

    init() {}

    init(mode: CaptureMode) {
        self.mode = mode
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$mode) capture")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // Persisting the route covers cold and background launches. The notification
        // handles the case where ContentView is already active in the foreground.
        let defaults = UserDefaults(suiteName: AppConstants.appGroupSuite)
        defaults?.set(mode.rawValue, forKey: DefaultsKey.intentCaptureMode)

        NotificationCenter.default.post(name: .intentCaptureRouteChanged, object: nil)

        return .result()
    }
}

extension Notification.Name {
    static let intentCaptureRouteChanged = Notification.Name("intentCaptureRouteChanged")
}
