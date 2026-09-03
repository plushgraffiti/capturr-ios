/// This App Intent enum supplies the capture-mode picker used by `OpenCaptureIntent`.
/// Shortcuts displays the four friendly case names, while each raw value deliberately
/// matches a `CaptureRoute`. The intent stores that value and `ContentView` converts it
/// back into the route for the requested capture screen.

import AppIntents

enum CaptureMode: String, AppEnum {
    case note
    case todo
    case voice
    case scan

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Capture Mode"
    }

    static var caseDisplayRepresentations: [CaptureMode: DisplayRepresentation] {
        [
            .note: "Note",
            .todo: "Todo",
            .voice: "Voice",
            .scan: "Scan"
        ]
    }
}
