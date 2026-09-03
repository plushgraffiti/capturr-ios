/// This recorder captures one AAC voice note for the Watch app's durable outbox.
/// `WatchHome` owns it and toggles recording, while the Watch audio background mode keeps
/// it running with the wrist down. User stops, interruptions, and the five-minute cap share
/// one path that waits for file finalization before handing audio to `WatchCaptureStore`.

import Foundation
import AVFoundation
import OSLog

private let logger = Logger(subsystem: "com.capturr.app", category: "WatchRecorder")

final class WatchRecorder: NSObject, ObservableObject {
    // MARK: - State

    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0
    @Published var statusText: String?

    // The soft cap bounds file size, transfer time, and battery use.
    private let maxDuration: TimeInterval = 5 * 60

    private struct PendingSave {
        let id: UUID
        let url: URL
        let duration: TimeInterval
        let reason: String
    }

    private var recorder: AVAudioRecorder?
    private var ticker: Timer?
    private var currentId: UUID?
    private var pendingSave: PendingSave?

    // MARK: - Setup and Controls

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification, object: nil)
    }

    @objc private func handleInterruption(_ note: Notification) {
        let interruptionTypeRawValue = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 0
        guard AVAudioSession.InterruptionType(rawValue: interruptionTypeRawValue) == .began else { return }
        DispatchQueue.main.async {
            if self.isRecording { self.stop(reason: "Saved — recording was interrupted") }
        }
    }

    func toggle() {
        if isRecording {
            stop(reason: "Saved ✓")
        } else {
            start()
        }
    }

    // MARK: - Recording

    private func start() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                guard granted else {
                    self.statusText = "Microphone access needed — enable in Settings"
                    return
                }
                self.beginRecording()
            }
        }
    }

    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            statusText = "Couldn't start recording"
            logger.error("Audio session error: \(error.localizedDescription)")
            return
        }

        let id = UUID()
        let url = WatchCaptureStore.recordingsDir.appendingPathComponent("\(id.uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]

        do {
            let audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder.delegate = self
            guard audioRecorder.record() else {
                statusText = "Couldn't start recording"
                return
            }
            recorder = audioRecorder
            currentId = id
            isRecording = true
            elapsed = 0
            statusText = nil

            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self, let audioRecorder = self.recorder else { return }
                self.elapsed = audioRecorder.currentTime
                if audioRecorder.currentTime >= self.maxDuration {
                    self.stop(reason: "Saved — 5 minute limit reached")
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
            logger.info("Recording started: \(id)")
        } catch {
            statusText = "Couldn't start recording"
            logger.error("Recorder init error: \(error.localizedDescription)")
        }
    }

    private func stop(reason: String) {
        guard let audioRecorder = recorder, let id = currentId else { return }
        ticker?.invalidate(); ticker = nil
        // The file is only guaranteed finalized (header written) when
        // audioRecorderDidFinishRecording fires — queuing the transfer before
        // that can ship a truncated .m4a. Park the save; the delegate completes it.
        pendingSave = PendingSave(id: id, url: audioRecorder.url, duration: audioRecorder.currentTime, reason: reason)
        audioRecorder.stop()
        recorder = nil
        currentId = nil
        isRecording = false
        statusText = "Saving…"
    }
}

extension WatchRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully didFinishSuccessfully: Bool) {
        DispatchQueue.main.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            guard let save = self.pendingSave else { return }
            self.pendingSave = nil

            guard save.duration > 0.2 else {
                // Accidental tap — nothing worth keeping
                try? FileManager.default.removeItem(at: save.url)
                self.statusText = nil
                return
            }

            if !didFinishSuccessfully {
                // Send anyway — the phone marks unreadable files failed, which
                // beats silently discarding whatever was captured
                logger.error("Recorder reported unsuccessful finish for \(save.id)")
            }
            WatchCaptureStore.shared.add(id: save.id, fileURL: save.url, duration: save.duration)
            self.statusText = save.reason
            logger.info("Recording finished: \(save.id) (\(Int(save.duration))s)")
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        logger.error("Encode error: \(error?.localizedDescription ?? "unknown")")
        DispatchQueue.main.async {
            if self.isRecording { self.stop(reason: "Saved — recording error") }
        }
    }
}
