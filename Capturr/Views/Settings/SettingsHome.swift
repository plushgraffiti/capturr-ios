/// This view is the app's main settings hub for graph, capture, sharing, and TODO options.
/// `ContentView` installs it as the Settings tab, and TODO empty state can link here
/// when setup is incomplete. It presents focused settings screens, saves quick toggles,
/// and checks Keychain-backed credentials without exposing their values.

import SwiftUI
import SwiftData
import UserNotifications

struct SettingsHome: View {
    // MARK: - State

    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @EnvironmentObject private var profileViewModel: ProfileViewModel
    @Environment(\.openURL) private var openURL
    
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    @State private var showResetOnboardingAlert: Bool = false
    @State private var hasAppendToken: Bool = false
    @State private var hasBackendToken: Bool = false

    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

    private var isPrimaryGraphConfigured: Bool {
        guard let name = profileViewModel.graphName, !name.isEmpty else { return false }
        return hasAppendToken
    }

    var body: some View {
        NavigationStack {
            List {
                Section {

                    NavigationLink {
                        SettingGraph(viewModel: profileViewModel)
                    } label: {
                        HStack {
                            Label("Graph Name", systemImage: "chart.bar.xaxis").foregroundColor(.primary)
                            Spacer()
                            Text("\(profileViewModel.graphName ?? "Not Set")").foregroundColor(.secondary)
                        }
                    }

                    NavigationLink {
                        SettingApiToken(viewModel: profileViewModel)
                    } label: {
                        HStack {
                            Label("Append API Token", systemImage: "key").foregroundColor(.primary)
                            Spacer()
                            Text(hasAppendToken ? "Set" : "Not Set")
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle(isOn: $profileViewModel.multiGraphEnabled) {
                        Label("Enable Multiple Graphs", systemImage: "square.stack.3d.up")
                            .foregroundColor(isPrimaryGraphConfigured ? .primary : .secondary)
                    }
                    .onChange(of: profileViewModel.multiGraphEnabled) {
                        try? profileViewModel.saveChanges(context: context)
                    }
                    .disabled(!isPrimaryGraphConfigured)

                    if profileViewModel.multiGraphEnabled {
                        NavigationLink {
                            ManageGraphsView(viewModel: profileViewModel)
                        } label: {
                            HStack {
                                Label("Manage Additional Graphs", systemImage: "gear")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("\(profileViewModel.additionalGraphs.count)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                } header: {
                    Text("Graph Settings")
                }

                Section {

                    NavigationLink {
                        SettingLocation(viewModel: profileViewModel)
                    } label: {
                        HStack {
                            Label("Default Location", systemImage: "list.bullet.rectangle.portrait").foregroundColor(.primary)
                            Spacer()
                            Text(
                                profileViewModel.useDailyNotes
                                ? "Daily Notes"
                                : (profileViewModel.customLocation?.isEmpty == false ? profileViewModel.customLocation! : "Daily Notes")
                            )
                            .foregroundColor(.secondary)
                                
                        }
                    }
                    
                    NavigationLink {
                        SettingBlock(viewModel: profileViewModel)
                    } label: {
                        HStack {
                            Label("Default Block", systemImage: "list.bullet.indent").foregroundColor(.primary)
                            Spacer()
                            Text(profileViewModel.customBlock?.isEmpty == false ? "Set" : "Not Set")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    NavigationLink {
                        SettingTag(viewModel: profileViewModel)
                    } label: {
                        HStack {
                            Label("Default Tag", systemImage: "tag").foregroundColor(.primary)
                            Spacer()
                            Text(profileViewModel.defaultTag?.isEmpty == false ? "Set" : "Not Set")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    NavigationLink {
                        SettingTimestamps(viewModel: profileViewModel)
                    } label: {
                        HStack {
                            Label("Manage Timestamps", systemImage: "clock")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(
                                profileViewModel.addTimestamp
                                ? profileViewModel.timestampPosition.title
                                : "Off"
                            )
                            .foregroundColor(.secondary)
                        }
                    }
                    
                    NavigationLink {
                        SettingVoiceLanguage(viewModel: profileViewModel)
                    } label: {
                        HStack {
                            Label("Dictation Language", systemImage: "globe").foregroundColor(.primary)
                            Spacer()
                            Text(profileViewModel.voiceLanguage)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                } header: {
                    Text("Capture Preferences")
                }
                
                Section {

                    Toggle(isOn: $profileViewModel.shareFormatLinks) {
                        Label("Format URLs for Roam", systemImage: "link")
                            .foregroundColor(.primary)
                    }
                    .onChange(of: profileViewModel.shareFormatLinks) {
                        try? profileViewModel.saveChanges(context: context)
                    }

                    Toggle(isOn: $profileViewModel.roamReaderEnabled) {
                        Label("Enable Roam Reader", systemImage: "book")
                            .foregroundColor(.primary)
                    }
                    .onChange(of: profileViewModel.roamReaderEnabled) {
                        try? profileViewModel.saveChanges(context: context)
                    }

                } header: {
                    Text("Share Preferences")
                }

                Section {

                    Toggle(isOn: $profileViewModel.todosEnabled) {
                        Label("Enable TODOs", systemImage: "checklist.checked")
                            .foregroundColor(.primary)
                    }
                    .onChange(of: profileViewModel.todosEnabled) { _, newValue in
                        if !newValue {
                            // Disabling the feature removes its cached data and app icon state too.
                            let syncManager = TodoSyncManager(modelContext: context)
                            try? syncManager.clearAllTodos()

                            Task {
                                try? await UNUserNotificationCenter.current().setBadgeCount(0)
                            }
                        }
                        try? profileViewModel.saveChanges(context: context)
                    }

                    if profileViewModel.todosEnabled {
                        NavigationLink {
                            SettingTodosApiToken(viewModel: profileViewModel)
                        } label: {
                            HStack {
                                Label("Backend API Token", systemImage: "key").foregroundColor(.primary)
                                Spacer()
                                Text(hasBackendToken ? "Set" : "Not Set")
                                    .foregroundColor(.secondary)
                            }
                        }

                        NavigationLink {
                            SettingTodosQuery(viewModel: profileViewModel)
                        } label: {
                            HStack {
                                Label("TODO Filtering", systemImage: "slider.horizontal.3").foregroundColor(.primary)
                                Spacer()

                            }
                        }

                        Toggle(isOn: $profileViewModel.todosBadgeEnabled) {
                            Label("Show Badge Count", systemImage: "app.badge")
                                .foregroundColor(.primary)
                        }
                        .onChange(of: profileViewModel.todosBadgeEnabled) { _, newValue in
                            if newValue {
                                requestNotificationPermission()
                            } else {
                                clearBadges()
                            }
                            try? profileViewModel.saveChanges(context: context)
                        }
                    }

                } header: {
                    Text("TODO Preferences")
                } footer: {
                    Text("Functionality not available for encrypted graphs")
                }
                
                Section {
                    NavigationLink {
                        SettingAppearance()
                    } label: {
                        HStack {
                            Label("Appearance", systemImage: "sun.max").foregroundColor(.primary)
                            Spacer()
                            Text("\(profileViewModel.appAppearance.title)").foregroundColor(.secondary)
                        }
                    }
                    
                    Button {
                        // The onboarding flow reads this AppStorage flag on the next launch.
                        hasSeenOnboarding = false
                        showResetOnboardingAlert = true
                    } label: {
                        HStack {
                            Label("Reset Onboarding", systemImage: "arrowshape.turn.up.backward.badge.clock").foregroundColor(.primary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        let buttonURL = "https://github.com/plushgraffiti/capturr-ios/issues"
                        openURL(URL(string: buttonURL)!)
                    } label: {
                        HStack {
                            Label("Report Issue", systemImage: "ladybug").foregroundColor(.primary)
                            Spacer()
                            
                        }
                    }
                    .buttonStyle(.plain)
                    
                    HStack{
                        Label("Version", systemImage: "info.circle").foregroundColor(.primary)
                        Spacer()
                        Text("\(version) (\(build))")
                            .foregroundStyle(.secondary)
                    }
                    
                }
                header: {
                    Text("General")
                }
                
            }
            .navigationTitle("Settings")
            .listStyle(.insetGrouped)
            .alert("Onboarding reset. Close the app, reopen and you will see onboarding again.", isPresented: $showResetOnboardingAlert) {
                Button("OK", role: .cancel) { }
            }
            .onAppear {
                hasAppendToken = CredentialsManager.shared.hasPrimaryAppendToken
                hasBackendToken = CredentialsManager.shared.hasPrimaryBackendToken
            }
        }
    }

    // MARK: - Badge Helpers

    private func requestNotificationPermission() {
        Task {
            do {
                let center = UNUserNotificationCenter.current()

                // Avoid prompting again when badge access is already available.
                let settings = await center.notificationSettings()

                if settings.badgeSetting == .enabled {
                    return
                }

                let granted = try await center.requestAuthorization(options: [.badge])

                if !granted {
                    // Keep the saved toggle consistent with the permission the system denied.
                    await MainActor.run {
                        profileViewModel.todosBadgeEnabled = false
                        try? profileViewModel.saveChanges(context: context)
                    }
                }
            } catch {
                // A failed request cannot support badges, so restore the toggle to off.
                await MainActor.run {
                    profileViewModel.todosBadgeEnabled = false
                    try? profileViewModel.saveChanges(context: context)
                }
            }
        }
    }

    private func clearBadges() {
        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(0)
        }
    }
}

#Preview {
    let mockViewModel = ProfileViewModel()
    mockViewModel.defaultTag = "#capture"
    return SettingsHome()
        .environmentObject(mockViewModel)
        .environment(\.locale, .init(identifier: "en"))
}
