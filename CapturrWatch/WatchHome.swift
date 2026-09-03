/// This view is the Watch app's single recording screen.
/// `CapturrWatchApp` presents it, and it owns a `WatchRecorder` plus the shared
/// `WatchCaptureStore`. It shows the record control, elapsed time or final status,
/// and how many durable recordings are still waiting for the paired iPhone.

import SwiftUI

struct WatchHome: View {
    @StateObject private var recorder = WatchRecorder()
    @StateObject private var captureStore = WatchCaptureStore.shared

    var body: some View {
        VStack(spacing: 10) {
            Button(action: recorder.toggle) {
                ZStack {
                    Circle()
                        .fill(recorder.isRecording ? Color.red : Color.blue)
                        .frame(width: 76, height: 76)
                    Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                        .foregroundStyle(.white)
                        .font(.system(size: 30, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Start recording")

            if recorder.isRecording {
                Text(timeString(recorder.elapsed))
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(.red)
            } else if let status = recorder.statusText {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Tap to capture")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if captureStore.pendingCount > 0 && !recorder.isRecording {
                Label("\(captureStore.pendingCount) waiting for iPhone", systemImage: "iphone.badge.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
    }

    private func timeString(_ elapsedTime: TimeInterval) -> String {
        let totalSeconds = Int(elapsedTime)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

#Preview {
    WatchHome()
}
