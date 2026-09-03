/// This App Intent enum gives `CaptureIntent` an explicit three-way timestamp choice.
/// Shortcuts can request yes, no, or App Default instead of showing an unexplained blank.
/// The default case leaves the outbox override unset, so `SyncWorker` uses the saved profile
/// preference when it eventually sends the capture.

import AppIntents

enum TimestampOption: String, AppEnum {
    case appDefault
    case yes
    case no

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Timestamp"
    }

    static var caseDisplayRepresentations: [TimestampOption: DisplayRepresentation] {
        [
            .appDefault: "App Default",
            .yes: "Yes",
            .no: "No"
        ]
    }
}
