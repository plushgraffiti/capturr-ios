/// This view is the app's root screen: a tab bar holding Capture, History, an
/// optional TODOs tab, and Settings. `CaptureApp` places it in the main window.
/// On first appearance it connects `ProfileViewModel` to SwiftData and loads the
/// stored Roam credentials. It also listens for capture requests arriving from
/// deep links, quick actions, and App Intents, and routes them to the Capture tab.

import SwiftUI
import SwiftData
import Combine
import OSLog

private let profileLogger = Logger(category: "Profile")

struct ContentView: View {
    @EnvironmentObject private var profileViewModel: ProfileViewModel
    @Environment(\.modelContext) private var modelContext

    enum AppTab: Hashable {
        case capture
        case history
        case todos
        case settings
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .capture
    @State private var pendingCaptureRoute: CaptureRoute?
    
    private var resolvedScheme: ColorScheme? {
        guard profileViewModel.isProfileReady else { return nil }
        switch profileViewModel.appAppearance {
            case .light: return .light
            case .dark: return .dark
            case .system: return nil
        }
    }

    // nil hides the TODOs tab badge entirely; large counts display as 99+.
    private var badgeText: String? {
        guard profileViewModel.todosBadgeEnabled && profileViewModel.todosEnabled else { return nil }
        let count = profileViewModel.todosBadgeCount
        if count == 0 { return nil }
        return count >= 99 ? "99+" : "\(count)"
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            CaptureHome(pendingRoute: $pendingCaptureRoute)
                .tabItem { Label("Capture", systemImage: "plus.app") }
                .tag(AppTab.capture)

            HistoryHome()
                .tabItem { Label("History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") }
                .tag(AppTab.history)

            if profileViewModel.todosEnabled {
                TodosHome()
                    .tabItem { Label("TODOs", systemImage: "checklist") }
                    .tag(AppTab.todos)
                    .badge(badgeText)
            }

            SettingsHome()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(AppTab.settings)

        }
        .task {
            profileViewModel.modelContext = modelContext
            initializeProfile(using: modelContext)
            await CredentialsManager.shared.loadCredentials()
        }
        .onOpenURL { url in
            guard let route = CaptureRoute.from(url: url) else { return }
            selectedTab = .capture
            pendingCaptureRoute = route
        }
        // Intent route pickup — three paths to handle all app launch states:
        // Written by OpenCaptureIntent, read and cleared by readIntentRoute().
        .onAppear {
            readIntentRoute()                   // Cold launch
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                readIntentRoute()               // Warm return from background
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .intentCaptureRouteChanged)) { _ in
            readIntentRoute()                   // App already active in foreground
        }
        .preferredColorScheme(resolvedScheme)
    }

    // Reads and clears the capture mode written by OpenCaptureIntent.
    // Clearing immediately after reading prevents stale routing on later manual launches.
    private func readIntentRoute() {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupSuite)
        guard let modeString = defaults?.string(forKey: DefaultsKey.intentCaptureMode) else { return }
        defaults?.removeObject(forKey: DefaultsKey.intentCaptureMode)

        if let route = CaptureRoute(rawValue: modeString) {
            selectedTab = .capture
            pendingCaptureRoute = route
        }
    }

    private func initializeProfile(using modelContext: ModelContext) {
        guard profileViewModel.profileManager == nil else { return }

        let manager = ProfileManager(modelContext: modelContext)
        profileViewModel.profileManager = manager

        do {
            let profile = try manager.getCurrentProfile()
            profileViewModel.updateViewModel(with: profile)
        } catch {
            profileLogger.error("Failed to initialize profile: \(error.localizedDescription)")
        }
    }
}

#Preview {
    let mockViewModel = ProfileViewModel()
    mockViewModel.todosEnabled = true
    return ContentView()
        .environmentObject(mockViewModel)
}
