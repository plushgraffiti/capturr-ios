/// This view offers the microphone and speech-recognition permissions used by voice capture.
/// `OnboardingView` presents it as the final, optional page. A `PermissionsViewModel`
/// translates the system authorization values for `PermissionRow`, requests access,
/// and lets the parent flow finish when the user grants or skips the permissions.

import SwiftUI
import AVFAudio
import Speech
import UIKit

struct OnboardingPermissions: View {
    let onNext: () -> Void
    @StateObject private var permissionsViewModel = PermissionsViewModel()
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 80, height: 80)
                    Image(systemName: "hand.raised")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.white)
                        .offset(x: 1, y: -1)
                }
                .padding(.top)

                Text("Setup: Permissions")
                    .font(.title2)
                    .bold()
                    .multilineTextAlignment(.center)

                Text("In order to send **Voice** notes to your Graph we will need to enable some permissions. **This step is optional.**")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 12) {
                    PermissionRow(
                        icon: "mic.fill",
                        title: "Microphone",
                        state: permissionsViewModel.micDisplayState,
                        onEnable: { permissionsViewModel.requestMic() },
                        onOpenSettings: openSettings
                    )

                    PermissionRow(
                        icon: "speaker.wave.2.bubble",
                        title: "Speech Recognition",
                        state: permissionsViewModel.speechDisplayState,
                        onEnable: { permissionsViewModel.requestSpeech() },
                        onOpenSettings: openSettings
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
            .padding()
            .background(Color(UIColor.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("**We Respect Your Privacy:** Outside of what is sent to your Roam Research graph all data remains on this device. **No tracking, no targeting, no ads.**")
                .font(.footnote)
                .foregroundStyle(.secondary)
            
            Spacer()

            VStack(spacing: 12) {
                Button {
                    if permissionsViewModel.allGranted {
                        onNext()
                    } else if permissionsViewModel.isAnyRestricted {
                        // iOS does not show its prompt again after denial; the user must change Settings.
                        openSettings()
                    } else {
                        permissionsViewModel.requestBoth {
                            if permissionsViewModel.allGranted { onNext() }
                        }
                    }
                } label: {
                    Text(permissionsViewModel.allGranted ? "Finish" : (permissionsViewModel.isAnyRestricted ? "Open Settings" : "Enable Permissions"))
                        .frame(maxWidth: .infinity)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .padding(8)
                }
                .buttonStyle(.borderedProminent)
                .mask { RoundedRectangle(cornerRadius: 16, style: .continuous) }

                if !permissionsViewModel.allGranted {
                    Button {
                        onNext()
                    } label: {
                        Text("Skip This Step")
                            .frame(maxWidth: .infinity)
                            .font(.callout)
                            .padding(8)
                    }
                    .buttonStyle(.bordered)
                    .mask { RoundedRectangle(cornerRadius: 16, style: .continuous) }
                }
            }
            .padding(.bottom, 60)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .task { permissionsViewModel.refresh() }
    }

    private func openSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            openURL(settingsURL)
        }
    }
}

#Preview {
    OnboardingPermissions(onNext: { })
        .padding()
}
