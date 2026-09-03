/// This view model translates microphone and speech permissions into simple display states.
/// `OnboardingPermissions` owns it while presenting the permission checklist and
/// passes its display states to `PermissionRow` for the microphone and speech rows.
/// It asks the system for access only in response to the onboarding flow.

import Foundation
import AVFAudio
import Speech

enum DisplayState: Equatable {
    case authorized
    case notDetermined
    case denied
    case restricted
}

@MainActor
final class PermissionsViewModel: ObservableObject {
    @Published var speechStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    var micDisplayState: DisplayState {
        let permission = AVAudioApplication.shared.recordPermission
        switch permission {
        case .granted: return .authorized
        case .undetermined: return .notDetermined
        case .denied: return .denied
        @unknown default: return .denied
        }
    }

    var speechDisplayState: DisplayState {
        switch speechStatus {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    var allGranted: Bool { micDisplayState == .authorized && speechStatus == .authorized }
    var isAnyRestricted: Bool { (micDisplayState == .denied || micDisplayState == .restricted) || speechStatus == .denied || speechStatus == .restricted }

    func refresh() {
        speechStatus = SFSpeechRecognizer.authorizationStatus()
    }

    func requestMic(completion: (() -> Void)? = nil) {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined:
            AVAudioApplication.requestRecordPermission { _ in
                Task { @MainActor in
                    completion?()
                }
            }
        default:
            Task { @MainActor in
                completion?()
            }
        }
    }

    func requestSpeech(completion: (() -> Void)? = nil) {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.speechStatus = status
                    completion?()
                }
            }
        default:
            Task { @MainActor in
                self.speechStatus = SFSpeechRecognizer.authorizationStatus()
                completion?()
            }
        }
    }

    func requestBoth(completion: @escaping () -> Void) {
        requestMic { [weak self] in
            guard let self else { completion(); return }
            let permission = AVAudioApplication.shared.recordPermission
            switch permission {
            case .granted:
                self.requestSpeech { completion() }
            default:
                completion()
            }
        }
    }
}
