/// This service transcribes one saved audio file into text on the device.
/// `TranscriptionWorker` gives it imported or Watch-recorded files and receives progress
/// while Speech analyzes them. Unlike live voice capture, this path does not own a microphone.

import Foundation
import AVFoundation
import Speech
import OSLog

private let logger = Logger(category: "FileTranscription")

enum FileTranscriptionService {
    typealias ProgressHandler = @Sendable (Double) -> Void

    // Transcribes an audio file on-device. Returns "" for silence — callers
    // decide policy (CAPTURR marks the item failed and keeps the audio).
    static func transcribe(
        url: URL,
        localeTag: String,
        progress: @escaping ProgressHandler = { _ in }
    ) async throws -> String {
        try Task.checkCancellation()
        progress(0)

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            throw FileTranscriptionFailure(
                stage: "opening audio file",
                underlying: error as NSError
            )
        }
        let sampleRate = audioFile.processingFormat.sampleRate
        guard audioFile.length > 0, sampleRate > 0 else {
            throw FileTranscriptionFailure(
                stage: "opening audio file",
                underlying: NSError(
                    domain: "com.capturr.app.FileTranscription",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "The file contains no decodable audio frames"]
                )
            )
        }
        let duration = Double(audioFile.length) / sampleRate
        let locale = Locale(identifier: localeTag)
        let transcriber = DictationTranscriber(
            locale: locale,
            preset: preset(forDuration: duration)
        )

        // Same asset-install dance as VoiceInput.ensureDictationModelInstalled —
        // the dictation model may need a (network-dependent) download first.
        progress(0.02)
        let installed = await DictationTranscriber.installedLocales
        try Task.checkCancellation()
        if !installed.contains(where: { $0.identifier(.bcp47).lowercased() == locale.identifier(.bcp47).lowercased() }) {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                logger.info("Downloading dictation model for \(localeTag)")
                let observation = request.progress.observe(
                    \.fractionCompleted,
                    options: [.initial, .new]
                ) { modelProgress, _ in
                    progress(0.02 + (min(max(modelProgress.fractionCompleted, 0), 1) * 0.06))
                }
                defer { observation.invalidate() }
                try await request.downloadAndInstall()
            }
        }
        try Task.checkCancellation()
        progress(0.08)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        do {
            try await analyzer.prepareToAnalyze(
                in: audioFile.processingFormat,
                withProgressReadyHandler: { _ in
                    progress(0.09)
                }
            )
            try Task.checkCancellation()
            progress(0.10)
        } catch is CancellationError {
            await analyzer.cancelAndFinishNow()
            throw CancellationError()
        } catch {
            await analyzer.cancelAndFinishNow()
            throw FileTranscriptionFailure(
                stage: "preparing transcription model",
                underlying: error as NSError
            )
        }

        let resultTask = Task { () throws -> String in
            var finalized = AttributedString("")
            do {
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    if result.isFinal {
                        if !finalized.characters.isEmpty { finalized.append(AttributedString(" ")) }
                        finalized.append(result.text)
                        let finalizedSeconds = CMTimeGetSeconds(result.range.end)
                        if finalizedSeconds.isFinite, duration > 0 {
                            let fraction = min(max(finalizedSeconds / duration, 0), 1)
                            progress(0.10 + (fraction * 0.85))
                        }
                    }
                }
            } catch {
                logger.error("Results stream error: \(error.localizedDescription)")
                throw error
            }
            return String(finalized.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var stage = "opening audio file"
        let formatDescription = "file=\(audioFile.fileFormat), processing=\(audioFile.processingFormat), frames=\(audioFile.length)"
        do {
            try Task.checkCancellation()
            stage = "analyzing audio"
            if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
                try Task.checkCancellation()
                stage = "finalizing analysis"
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }

            try Task.checkCancellation()
            stage = "collecting transcription results"
            let transcript = try await resultTask.value
            try Task.checkCancellation()
            progress(0.95)
            return transcript
        } catch is CancellationError {
            resultTask.cancel()
            await analyzer.cancelAndFinishNow()
            _ = try? await resultTask.value
            throw CancellationError()
        } catch {
            // Do not leave the result consumer suspended if opening or analyzing
            // the file fails. Most importantly, propagate stream failures so a
            // partial transcript can never be accepted as complete.
            resultTask.cancel()
            await analyzer.cancelAndFinishNow()
            _ = try? await resultTask.value
            let nsError = error as NSError
            let fileSize = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? -1
            logger.error("File transcription failed during \(stage, privacy: .public); file=\(url.lastPathComponent, privacy: .public), bytes=\(fileSize), \(formatDescription, privacy: .public), error=\(nsError.domain, privacy: .public) \(nsError.code): \(nsError.localizedDescription, privacy: .public)")
            throw FileTranscriptionFailure(stage: stage, underlying: nsError)
        }
    }

    // Apple recommends the short preset through one minute and the long
    // preset above one minute for file-based dictation.
    static func preset(forDuration duration: TimeInterval) -> DictationTranscriber.Preset {
        duration <= 60 ? .shortDictation : .longDictation
    }
}

private struct FileTranscriptionFailure: LocalizedError {
    let stage: String
    let domain: String
    let code: Int
    let detail: String

    init(stage: String, underlying: NSError) {
        self.stage = stage
        domain = underlying.domain
        code = underlying.code
        detail = underlying.localizedDescription
    }

    var errorDescription: String? {
        "Audio \(stage) failed (\(domain) \(code)): \(detail)"
    }
}
