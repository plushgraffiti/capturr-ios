/// This error type gives known live-voice failures clear messages for the person recording.
/// `VoiceInput` throws these errors while it prepares dictation, converts microphone audio,
/// or finishes a session, and `CaptureVoice` displays their localized descriptions.

import Foundation

public enum VoiceCaptureError: LocalizedError {
    case notRecording
    case dictationModelCapacityExceeded
    case dictationModelUnavailable
    case analyzerIncompatibleFormat
    case converterCreationFailed
    case bufferAllocationFailed

    public var errorDescription: String? {
        switch self {
        case .notRecording:
            return "Not recording"
        case .dictationModelCapacityExceeded:
            return "Apple Dictation supports up to 5 languages. To install a new language, remove one first in Settings (App) > General > Keyboard > Dictation Languages."
        case .dictationModelUnavailable:
            return "Apple Dictation model is unavailable for this language"
        case .analyzerIncompatibleFormat:
            return "Audio input isn't compatible with the analyzer's required format"
        case .converterCreationFailed:
            return "Could not create an audio converter for the required format"
        case .bufferAllocationFailed:
            return "Could not allocate an audio buffer for conversion"
        }
    }
}
