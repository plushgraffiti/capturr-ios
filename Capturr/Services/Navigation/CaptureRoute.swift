/// This route model names the four capture modes and their shared navigation metadata.
/// Capture menus, App Intents, and `ContentView` use it to agree on titles,
/// icons, and `capturr://capture/...` deep links without duplicating route rules.

import Foundation

enum CaptureRoute: String, CaseIterable, Codable, Hashable, Identifiable {
    case note
    case todo
    case voice
    case scan

    // Deep-link scheme and host: capturr://capture/...
    static let urlScheme = "capturr"
    static let urlHost = "capture"

    var id: String { rawValue }

    // Title used for buttons inside the app.
    var menuTitle: String {
        switch self {
        case .note: return "Write"
        case .todo: return "Todo"
        case .voice: return "Voice"
        case .scan: return "Scan"
        }
    }

    // Title presented to users in widgets and quick actions.
    var widgetTitle: String {
        switch self {
        case .note: return "Note"
        case .todo: return "Todo"
        case .voice: return "Voice"
        case .scan: return "Scan"
        }
    }

    // SF Symbol name for the mode.
    var systemImageName: String {
        switch self {
        case .note: return "list.bullet.rectangle"
        case .todo: return "checklist"
        case .voice: return "waveform"
        case .scan: return "document.viewfinder"
        }
    }

    // Parses a capturr://capture/<mode> URL back into a route; nil if the scheme, host, or mode don't match.
    static func from(url: URL) -> CaptureRoute? {
        guard url.scheme?.lowercased() == urlScheme else { return nil }

        if let host = url.host?.lowercased(), host != urlHost {
            return nil
        }

        let trimmedPathComponents = url.pathComponents.filter { $0 != "/" }
        guard let first = trimmedPathComponents.first else { return nil }
        return CaptureRoute(rawValue: first.lowercased())
    }
}
