/// This app struct is CAPTURR's entry point. iOS starts it via @main; it creates
/// the shared SwiftData container, shows `ContentView`, and keeps `SyncManager`
/// alive for the whole session. Two small delegates store Home Screen quick-action
/// choices for `ContentView` to pick up, and the background-task handlers wake the
/// app between launches to drain the capture outbox and refresh TODOs with no UI.

import SwiftUI
import SwiftData
import BackgroundTasks
import OSLog

private let appLogger = Logger(category: "App")

// MARK: - Quick Action Handling

class QuickActionDelegate: NSObject, UIApplicationDelegate {

    // Runs on every process launch — including background launches where no
    // scene ever connects (WCSession file delivery, App Intents). WCSession
    // activation must live here, not in SwiftUI .task, or watch recordings
    // delivered in the background would go unhandled.
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let container = SharedModelContainer()
        WatchSessionManager.shared.activate(container: container)
        Task { @MainActor in
            AudioImportCoordinator.recoverAbandonedScheduledItems(
                modelContext: container.mainContext
            )
            let transcriptionWorker = TranscriptionWorker(
                modelContext: container.mainContext
            )
            await transcriptionWorker.processPendingItems()
            let syncWorker = SyncWorker(modelContext: container.mainContext)
            await syncWorker.drainPendingItems()
        }
        return true
    }

    // Cold launch — shortcut arrives via scene connection options.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let shortcutItem = options.shortcutItem,
           CaptureRoute(rawValue: shortcutItem.type) != nil {
            let defaults = UserDefaults(suiteName: AppConstants.appGroupSuite)
            defaults?.set(shortcutItem.type, forKey: DefaultsKey.intentCaptureMode)
        }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = QuickActionSceneDelegate.self
        return config
    }
}

// Warm launch — app was suspended, shortcut arrives via scene delegate.
class QuickActionSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard CaptureRoute(rawValue: shortcutItem.type) != nil else {
            completionHandler(false)
            return
        }
        let defaults = UserDefaults(suiteName: AppConstants.appGroupSuite)
        defaults?.set(shortcutItem.type, forKey: DefaultsKey.intentCaptureMode)
        NotificationCenter.default.post(name: .intentCaptureRouteChanged, object: nil)
        completionHandler(true)
    }
}

@main
struct CaptureApp: App {
    private enum BackgroundDrainResult: Equatable {
        case success
        case offline
        case failure
    }

    @UIApplicationDelegateAdaptor(QuickActionDelegate.self) private var appDelegate

    private let container: ModelContainer = SharedModelContainer()
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var profileViewModel = ProfileViewModel()
    // Strong reference so the worker lives for the session
    @State private var syncManager: SyncManager?

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    @State private var showingOnboarding: Bool = false

    init() {
        // BGTaskScheduler.register must happen before any submit, and on every
        // process launch — including background launches by App Intents where
        // the UI never appears and .task never fires.
        registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
            .environmentObject(profileViewModel)
            .task {
                if syncManager == nil {
                    syncManager = SyncManager(modelContext: container.mainContext)
                }
                registerQuickActions()
                // Defensive re-arm: force-quitting an app cancels iOS's willingness
                // to run BG tasks until the next launch, so schedule on launch too.
                Self.scheduleBackgroundSync(modelContext: container.mainContext)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    syncManager?.kickQueue()
                }
                if newPhase == .background {
                    Self.scheduleBackgroundSync(modelContext: container.mainContext)
                }
            }
            .onAppear {
                if !hasSeenOnboarding {
                    showingOnboarding = true
                }
            }
            .fullScreenCover(isPresented: $showingOnboarding) {
                OnboardingView(viewModel: profileViewModel)
                    .onDisappear {
                        hasSeenOnboarding = true
                    }
            }
        }
        .modelContainer(container)
    }

    // MARK: - Quick Actions

    private func registerQuickActions() {
        UIApplication.shared.shortcutItems = CaptureRoute.allCases.map { route in
            UIApplicationShortcutItem(
                type: route.rawValue,
                localizedTitle: route.widgetTitle,
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: route.systemImageName)
            )
        }
    }

    // MARK: - Background Refresh

    func registerBackgroundTasks() {
        // Requests submitted by versions before the identifier was aligned
        // with the app bundle ID must not remain queued without a handler.
        BGTaskScheduler.shared.cancel(
            taskRequestWithIdentifier: AppConstants.legacyBgSyncTaskIdentifier
        )

        let didRegister = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: AppConstants.bgSyncTaskIdentifier,
            using: nil
        ) { task in
            Self.handleBackgroundSync(task: task as! BGAppRefreshTask, container: self.container)
        }
        if didRegister {
            appLogger.info("Registered background sync handler")
        } else {
            appLogger.error("Background sync handler registration failed")
        }
    }

    static func handleBackgroundSync(task: BGAppRefreshTask, container: ModelContainer) {
        BackgroundSyncScheduler.scheduleHandlerFallback()
        appLogger.info("Background sync handler started")

        let workTask = Task { @MainActor in
            // 1. Drain the capture outbox. This is the user-visible work — pending
            //    captures from in-app, share extension, and Shortcuts all flow through
            //    the same outbox, so this single drain serves all entry points.
            let drainResult = await drainCaptureOutbox(container: container)
            var didSucceed = drainResult != .failure

            // 2. Refresh TODOs (only if enabled and configured).
            if drainResult != .offline && !Task.isCancelled {
                do {
                    let descriptor = FetchDescriptor<UserProfile>()
                    if let profile = try container.mainContext.fetch(descriptor).first,
                       profile.todosEnabled,
                       let graphName = profile.graphName,
                       let apiToken = await CredentialsManager.shared.primaryBackendToken {
                        let todoSyncManager = TodoSyncManager(modelContext: container.mainContext)
                        try await todoSyncManager.fetchTodos(
                            graphName: graphName,
                            tagFilter: profile.todosTagFilter,
                            excludeFilter: profile.todosExcludeTagFilter,
                            timePeriodDays: profile.todosTimePeriod,
                            apiToken: apiToken
                        )
                    }
                } catch {
                    appLogger.error("Background TODO refresh failed: \(error.localizedDescription)")
                    didSucceed = false
                }
            }

            let didExpire = Task.isCancelled
            let didScheduleNextRefresh = BackgroundSyncScheduler.scheduleNext(
                modelContext: container.mainContext
            )
            didSucceed = didSucceed && !didExpire && didScheduleNextRefresh
            task.setTaskCompleted(success: didSucceed)
            appLogger.info("Background sync handler completed successfully: \(didSucceed)")
        }

        task.expirationHandler = {
            appLogger.warning("Background sync handler expired")
            workTask.cancel()
        }
    }

    // Drains pending OutboxItems by repeatedly invoking SyncWorker.syncNextPendingItem(),
    // which processes one item per call. Bounded by the BG task's expiration via
    // Task.isCancelled, plus a safety cap on iterations.
    @MainActor
    private static func drainCaptureOutbox(container: ModelContainer) async -> BackgroundDrainResult {
        // Transcribe first: awaiting audio items become sendable text, so the
        // sync drain below can pick them up in the same background window.
        let transcriptionWorker = TranscriptionWorker(modelContext: container.mainContext)
        await transcriptionWorker.processPendingItems()

        let worker = SyncWorker(modelContext: container.mainContext)
        let maxItemsPerDrain = 100
        var didSucceed = true
        for _ in 0..<maxItemsPerDrain {
            if Task.isCancelled { return .failure }
            switch await worker.syncNextPendingItem() {
            case .noWork:
                return didSucceed ? .success : .failure
            case .success:
                break
            case .offline:
                return didSucceed ? .offline : .failure
            case .sendFailure:
                didSucceed = false
            case .persistenceFailure:
                return .failure
            }

            // Stop early if nothing remains that would be picked up on the next pass.
            let now = Date()
            let descriptor = FetchDescriptor<OutboxItem>()
            guard let items = try? container.mainContext.fetch(descriptor) else { return .failure }
            let stillDue = items.contains { item in
                if item.hardError ?? false { return false }
                // Un-transcribed items aren't sendable — don't let them spin the drain loop
                if let transcriptionState = item.transcriptionState, transcriptionState != TranscriptionState.done.rawValue { return false }
                let pending = item.status == SyncStatus.pending.rawValue
                let inProgress = item.status == SyncStatus.inProgress.rawValue
                guard pending || inProgress else { return false }
                if let next = item.nextAttemptAt { return next <= now }
                return true
            }
            if !stillDue { return didSucceed ? .success : .failure }
        }
        return .failure
    }

    static func scheduleBackgroundSync(modelContext: ModelContext) {
        BackgroundSyncScheduler.scheduleNext(modelContext: modelContext)
    }
}
