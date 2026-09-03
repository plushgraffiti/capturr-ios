/// This view chooses the app's light, dark, or system-controlled appearance.
/// `SettingsHome` presents it and supplies the shared `ProfileViewModel` through
/// the environment. Each selection is saved to the user's SwiftData profile and
/// then applied by `ContentView` to the whole app.

import SwiftUI
import OSLog

private let logger = Logger(category: "Settings")

struct SettingAppearance: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var profileViewModel: ProfileViewModel

    var body: some View {
        NavigationStack {
            List {
                Section(
                    header: Text("Choose Appearance"),
                    footer: Text("Select your preferred app appearance: Light, Dark, or System (follows your device setting).")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                ) {
                    ForEach(Appearance.allCases) { mode in
                        Button(action: {
                            profileViewModel.appAppearance = mode
                        }) {
                            HStack {
                                Image(systemName: iconName(for: mode))
                                Text(mode.title)
                                Spacer()
                                if profileViewModel.appAppearance == mode {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Appearance")
                        .font(.headline)
                }
            }
            .listStyle(.insetGrouped)
            .onChange(of: profileViewModel.appAppearance) { oldValue, newValue in
                // Persist immediately because tapping a row changes the shared setting before leaving.
                do {
                    try profileViewModel.saveChanges(context: context)
                } catch {
                    logger.error("Failed to save profile changes: \(error.localizedDescription)")
                }
            }
        }
    }

    // Give each appearance choice a visual cue in the list.
    private func iconName(for appearance: Appearance) -> String {
        switch appearance {
        case .light: return "lightbulb"
        case .dark: return "lightbulb.fill"
        case .system: return "gear"
        }
    }
}

#Preview {
    let mockViewModel = ProfileViewModel()
    return SettingAppearance()
        .environmentObject(mockViewModel)
}
