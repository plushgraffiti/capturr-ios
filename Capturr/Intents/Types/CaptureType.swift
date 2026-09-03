/// This App Intent enum supplies the note-or-TODO picker used by `CaptureIntent`.
/// Shortcuts displays these friendly names, then the intent maps the selected case to an
/// `OutboxItemType`. `SyncWorker` and `RoamAPI` later use that saved type to choose the
/// correct Roam block format.

import AppIntents

enum CaptureType: String, AppEnum {
    case note
    case todo

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Capture Type"
    }

    static var caseDisplayRepresentations: [CaptureType: DisplayRepresentation] {
        [.note: "Note", .todo: "Todo"]
    }
}
