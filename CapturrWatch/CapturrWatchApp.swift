/// This Watch app is the wrist entry point for one-tap voice capture.
/// WatchKit creates `CapturrWatchApp`, whose window presents `WatchHome`, and forwards
/// lifecycle events to `WatchAppDelegate`. The delegate activates the durable transfer
/// store and retries stranded recordings; the paired iPhone owns transcription and sync.

import SwiftUI
import WatchKit

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        WatchCaptureStore.shared.activate()
    }

    func applicationDidBecomeActive() {
        WatchCaptureStore.shared.requeueStale()
    }
}

@main
struct CapturrWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup { WatchHome() }
    }
}
