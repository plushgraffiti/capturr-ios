/// This widget is Capturr's complication for launching voice capture from a Watch face.
/// WidgetKit discovers the `@main` `CapturrComplication` through the Watch widget extension
/// and asks its static provider for the display entry. The view adapts the Capturr mark to
/// each supported accessory family, and a tap opens the containing Watch app's `WatchHome`.

import SwiftUI
import WidgetKit

// WidgetKit requires a dated entry even though this complication has no changing data.
private struct CapturrComplicationEntry: TimelineEntry {
    let date: Date
}

private struct CapturrComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> CapturrComplicationEntry {
        CapturrComplicationEntry(date: .now)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (CapturrComplicationEntry) -> Void
    ) {
        completion(CapturrComplicationEntry(date: .now))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<CapturrComplicationEntry>) -> Void
    ) {
        let entry = CapturrComplicationEntry(date: .now)
        // The mark is static, so the provider never requests a scheduled refresh.
        completion(Timeline(entries: [entry], policy: .never))
    }
}

// Reuses the same compact brand mark in families that do not have room for a label.
private struct CapturrMark: View {
    var body: some View {
        Text("[[+]]")
            .font(.system(.caption2, design: .monospaced, weight: .heavy))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .widgetAccentable()
            .accessibilityLabel("CAPTURR")
    }
}

// WidgetKit supplies the active family, which determines whether the mark can include text.
private struct CapturrComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("CAPTURR", systemImage: "plus.square.on.square")
        case .accessoryRectangular:
            HStack(spacing: 5) {
                CapturrMark()
                Text("CAPTURR")
                    .font(.headline)
                    .minimumScaleFactor(0.7)
            }
            .widgetAccentable()
        case .accessoryCircular, .accessoryCorner:
            CapturrMark()
        default:
            CapturrMark()
        }
    }
}

@main
struct CapturrComplication: Widget {
    private let kind = "CapturrComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CapturrComplicationProvider()) { _ in
            CapturrComplicationView()
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("CAPTURR")
        .description("Open CAPTURR for a quick voice capture.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular,
        ])
        .contentMarginsDisabled()
    }
}
