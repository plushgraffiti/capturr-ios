/// This widget bundle gives the Home Screen and Lock Screen quick links to Capturr's modes.
/// WidgetKit discovers `CapturrWidgetsBundle`, whose static providers register four individual
/// shortcuts and one combined widget. Each tap opens a `capturr://capture/...` deep link that
/// `ContentView` converts into the matching `CaptureRoute` in the main app.

import SwiftUI
import WidgetKit

// MARK: - Shortcut Metadata

// This widget-only metadata mirrors CaptureRoute. Raw values must stay aligned
// because the main app parses each value from the widget's deep-link path.
enum CaptureShortcut: String, CaseIterable {
    case note
    case todo
    case voice
    case scan

    var displayTitle: String {
        switch self {
        case .note: return "Note"
        case .todo: return "Todo"
        case .voice: return "Voice"
        case .scan: return "Scan"
        }
    }

    var systemImageName: String {
        switch self {
        case .note: return "list.bullet.rectangle"
        case .todo: return "checklist"
        case .voice: return "waveform"
        case .scan: return "document.viewfinder"
        }
    }

    // ContentView handles this capturr://capture/<mode> URL when the main app opens.
    var deepLinkURL: URL {
        URL(string: "capturr://capture/\(rawValue)")!
    }
}

// MARK: - Single Shortcut Widget (Small)

// The shortcut selects the visible mode; WidgetKit requires date even though the content is static.
struct CaptureShortcutEntry: TimelineEntry {
    let date: Date
    let shortcut: CaptureShortcut
}

// The four small widgets share static timeline behavior and differ only by shortcut.
protocol ShortcutTimelineProvider: TimelineProvider where Entry == CaptureShortcutEntry {
    var shortcut: CaptureShortcut { get }
}

extension ShortcutTimelineProvider {
    func placeholder(in context: Context) -> CaptureShortcutEntry {
        CaptureShortcutEntry(date: .now, shortcut: shortcut)
    }

    func getSnapshot(in context: Context, completion: @escaping (CaptureShortcutEntry) -> Void) {
        completion(CaptureShortcutEntry(date: .now, shortcut: shortcut))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaptureShortcutEntry>) -> Void) {
        let entry = CaptureShortcutEntry(date: .now, shortcut: shortcut)
        // The display has no changing data, so WidgetKit never needs a refresh request.
        completion(Timeline(entries: [entry], policy: .never))
    }
}

// MARK: - Concrete Timeline Providers

struct NoteShortcutProvider: ShortcutTimelineProvider {
    let shortcut: CaptureShortcut = .note
}

struct TodoShortcutProvider: ShortcutTimelineProvider {
    let shortcut: CaptureShortcut = .todo
}

struct VoiceShortcutProvider: ShortcutTimelineProvider {
    let shortcut: CaptureShortcut = .voice
}

struct ScanShortcutProvider: ShortcutTimelineProvider {
    let shortcut: CaptureShortcut = .scan
}

// MARK: - Single Shortcut Views

// The small Home Screen layout makes the entire widget one deep-link target.
struct CaptureShortcutWidgetView: View {
    var entry: CaptureShortcutEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("[[+]]")
                .font(.title3)
                .fontWeight(.heavy)
                .accessibilityHidden(true) // Decorative element
                .padding(.bottom, 4)

            Text("Capture \(entry.shortcut.displayTitle)")
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(.primary)

            Spacer()

            Image(systemName: entry.shortcut.systemImageName)
                .imageScale(.large)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(4)
        .containerBackground(Color.clear, for: .widget)
        .widgetURL(entry.shortcut.deepLinkURL)
        .accessibilityLabel("Capture \(entry.shortcut.displayTitle)")
        .accessibilityHint("Opens \(entry.shortcut.displayTitle) capture mode")
    }
}

// The circular Lock Screen layout uses the system tint and the same deep link.
struct CaptureShortcutAccessoryCircularView: View {
    var entry: CaptureShortcutEntry

    var body: some View {
        Image(systemName: entry.shortcut.systemImageName)
            .imageScale(.large)
            .font(.system(size: 32, weight: .medium))
            .containerBackground(Color.clear, for: .widget)
            .widgetAccentable() // Adapts to lock screen tint color
            .widgetURL(entry.shortcut.deepLinkURL)
            .accessibilityLabel("Capture \(entry.shortcut.displayTitle)")
            .accessibilityHint("Opens \(entry.shortcut.displayTitle) capture mode")
    }
}

// WidgetKit supplies the current family so one configuration can support both layouts.
@available(iOS 16.0, *)
struct AdaptiveShortcutWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: CaptureShortcutEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CaptureShortcutAccessoryCircularView(entry: entry)
        default:
            CaptureShortcutWidgetView(entry: entry)
        }
    }
}

// MARK: - Combined Shortcut Widget (Medium)

// The combined widget always shows every mode, so its entry needs only WidgetKit's date.
struct DualShortcutEntry: TimelineEntry {
    let date: Date
}

// The combined widget is also static and never requests another timeline.
struct DualShortcutProvider: TimelineProvider {
    func placeholder(in context: Context) -> DualShortcutEntry {
        DualShortcutEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (DualShortcutEntry) -> Void) {
        completion(DualShortcutEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DualShortcutEntry>) -> Void) {
        let entry = DualShortcutEntry(date: .now)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

// MARK: - Combined Shortcut View

// The medium widget uses separate Link values so each icon can open its own mode.
struct DualShortcutWidgetView: View {
    var entry: DualShortcutEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("[[+]]")
                .font(.title3)
                .fontWeight(.heavy)
                .accessibilityHidden(true) // Decorative element
                .padding(.bottom, 4)

            Text("Capture Note, Todo, Voice or Scan")
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            HStack(spacing: 40) {
                ShortcutIconButton(shortcut: .note)
                ShortcutIconButton(shortcut: .todo)
                ShortcutIconButton(shortcut: .voice)
                ShortcutIconButton(shortcut: .scan)
            }
        }
        .padding(4)
        .containerBackground(Color.clear, for: .widget)
    }
}

// Each combined-widget icon owns its deep link and accessibility description.
private struct ShortcutIconButton: View {
    let shortcut: CaptureShortcut

    var body: some View {
        Link(destination: shortcut.deepLinkURL) {
            Image(systemName: shortcut.systemImageName)
                .imageScale(.large)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Capture \(shortcut.displayTitle)")
        .accessibilityHint("Opens \(shortcut.displayTitle) capture mode")
    }
}

// MARK: - Widget Definitions

// The four individual definitions share layouts but register distinct gallery entries.
struct CaptureNoteWidget: Widget {
    let kind: String = "CaptureNoteWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NoteShortcutProvider()) { entry in
            if #available(iOS 16.0, *) {
                AdaptiveShortcutWidgetView(entry: entry)
            } else {
                CaptureShortcutWidgetView(entry: entry)
            }
        }
        .configurationDisplayName("Capture Note")
        .description("Opens directly into Note capture")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct CaptureTodoWidget: Widget {
    let kind: String = "CaptureTodoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodoShortcutProvider()) { entry in
            if #available(iOS 16.0, *) {
                AdaptiveShortcutWidgetView(entry: entry)
            } else {
                CaptureShortcutWidgetView(entry: entry)
            }
        }
        .configurationDisplayName("Capture Todo")
        .description("Opens directly into Todo capture")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct CaptureVoiceWidget: Widget {
    let kind: String = "CaptureVoiceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VoiceShortcutProvider()) { entry in
            if #available(iOS 16.0, *) {
                AdaptiveShortcutWidgetView(entry: entry)
            } else {
                CaptureShortcutWidgetView(entry: entry)
            }
        }
        .configurationDisplayName("Capture Voice")
        .description("Opens directly into Voice capture")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct CaptureScanWidget: Widget {
    let kind: String = "CaptureScanWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScanShortcutProvider()) { entry in
            if #available(iOS 16.0, *) {
                AdaptiveShortcutWidgetView(entry: entry)
            } else {
                CaptureShortcutWidgetView(entry: entry)
            }
        }
        .configurationDisplayName("Scan Document")
        .description("Opens directly into Scan mode")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

// The combined definition is medium-only because it needs four independent tap targets.
struct CaptureEverythingWidget: Widget {
    let kind: String = "CaptureEverythingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DualShortcutProvider()) { entry in
            DualShortcutWidgetView(entry: entry)
        }
        .configurationDisplayName("Capture Everything")
        .description("Quick access to all capture methods")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Widget Bundle

// WidgetKit discovers this entry point and adds every returned definition to the gallery.
@main
struct CapturrWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CaptureNoteWidget()
        CaptureTodoWidget()
        CaptureVoiceWidget()
        CaptureScanWidget()
        CaptureEverythingWidget()
    }
}

// MARK: - Previews

// MARK: - Home Screen Widgets

#Preview("Note Widget", as: .systemSmall) {
    CaptureNoteWidget()
} timeline: {
    CaptureShortcutEntry(date: .now, shortcut: .note)
}

#Preview("Voice Widget", as: .systemSmall) {
    CaptureVoiceWidget()
} timeline: {
    CaptureShortcutEntry(date: .now, shortcut: .voice)
}

#Preview("Capture Everything Widget", as: .systemMedium) {
    CaptureEverythingWidget()
} timeline: {
    DualShortcutEntry(date: .now)
}

// MARK: - Lock Screen Widgets

#Preview("Note Lock Screen", as: .accessoryCircular) {
    CaptureNoteWidget()
} timeline: {
    CaptureShortcutEntry(date: .now, shortcut: .note)
}

#Preview("Todo Lock Screen", as: .accessoryCircular) {
    CaptureTodoWidget()
} timeline: {
    CaptureShortcutEntry(date: .now, shortcut: .todo)
}

#Preview("Voice Lock Screen", as: .accessoryCircular) {
    CaptureVoiceWidget()
} timeline: {
    CaptureShortcutEntry(date: .now, shortcut: .voice)
}

#Preview("Scan Lock Screen", as: .accessoryCircular) {
    CaptureScanWidget()
} timeline: {
    CaptureShortcutEntry(date: .now, shortcut: .scan)
}
