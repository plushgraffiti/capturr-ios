/// This view shows the current state of one permission used by voice capture.
/// `OnboardingPermissions` creates a row for microphone access and another for
/// speech recognition, passing the display state produced by
/// `PermissionsViewModel`.

import SwiftUI

struct PermissionRow: View {
    let icon: String
    let title: String
    let state: DisplayState
    let onEnable: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                switch state {
                case .authorized:
                    Label("Enabled", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.callout)
                        .foregroundStyle(.green)
                        .contentTransition(.opacity)
                        .padding(.top, 4)
                case .notDetermined:
                    Label("Not Enabled", systemImage: "questionmark.circle.dashed")
                        .labelStyle(.titleAndIcon)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                        .padding(.top, 4)
                case .denied, .restricted:
                    Label("Enable via Settings", systemImage: "exclamationmark.triangle")
                        .labelStyle(.titleAndIcon)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .contentTransition(.opacity)
                        .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 10)
        
    }
}
