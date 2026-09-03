/// This service converts one live audio stream into an on-device dictation result.
/// `VoiceInput` creates it with the profile's chosen language and supplies microphone samples.
/// Speech analysis may produce partial results internally, but callers receive one final string.
/// The service analyzes audio only; `VoiceInput` remains responsible for the microphone pipeline.

import AVFoundation
import Speech
import OSLog

private let logger = Logger(category: "Voice")

@available(iOS 26.0, *)
@MainActor
final class VoiceSpeechService {

    // MARK: ‑ State
    private var analyzer: SpeechAnalyzer?
    private var transcriber: DictationTranscriber?
    private var resultTask: Task<AttributedString, Never>?
    private var isRunning = false

    enum ServiceError: Error { case notRunning }

    // MARK: - API

    // Starts one dictation session using the caller's configured transcriber.
    // The stream's samples must match requiredFormat, which VoiceInput obtains
    // from Speech before it starts the microphone pipeline.
    func start(transcriber: DictationTranscriber,
               inputSequence: AsyncStream<AnalyzerInput>,
               requiredFormat: AVAudioFormat) async throws {
        guard !isRunning else { return }

        let analyzer = SpeechAnalyzer(modules: [transcriber])

        // Build final transcript by checking isFinal property on each result.
        // - Volatile (isFinal == false): interim updates as the recognizer refines (e.g., "five" → "55" → "559")
        // - Finalized (isFinal == true): completed segments, typically after a pause or end of utterance
        resultTask = Task { [transcriber] in
            var finalizedTranscript = AttributedString("")
            var volatileTranscript = AttributedString("")

            do {
                for try await r in transcriber.results {
                    if r.isFinal {
                        // Completed segment - append to finalized transcript
                        if !finalizedTranscript.characters.isEmpty {
                            finalizedTranscript.append(AttributedString(" "))
                        }
                        finalizedTranscript.append(r.text)
                        volatileTranscript = AttributedString("") // Clear volatile
                    } else {
                        // Interim update - just track it but don't commit yet
                        volatileTranscript = r.text
                    }
                }

                // If there's any remaining volatile text when the stream ends, include it
                if !volatileTranscript.characters.isEmpty {
                    if !finalizedTranscript.characters.isEmpty {
                        finalizedTranscript.append(AttributedString(" "))
                    }
                    finalizedTranscript.append(volatileTranscript)
                }
            } catch {
                // Swallow errors; stop/cancel will handle lifecycle.
            }
            return finalizedTranscript
        }

        // Prepare analyzer for the exact format we will feed, then start.
        do {
            try await analyzer.prepareToAnalyze(in: requiredFormat, withProgressReadyHandler: nil)
            try await analyzer.start(inputSequence: inputSequence)
        } catch {
            let ns = error as NSError
            if ns.domain == "SFSpeechErrorDomain" && ns.code == 11 {
                let err = VoiceCaptureError.dictationModelCapacityExceeded
                logger.error("Dictation model install failed: \(err.errorDescription ?? "capacity exceeded")")
                throw err
            } else {
                logger.error("Analyzer prepare/start failed — domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription) reason=\(String(describing: ns.userInfo[NSLocalizedFailureReasonErrorKey])) underlying=\(String(describing: ns.userInfo[NSUnderlyingErrorKey]))")
                throw error
            }
        }

        self.transcriber = transcriber
        self.analyzer = analyzer
        self.isRunning = true
    }

    // Finalize analysis and return the single transcript string.
    func stopAndGetTranscript() async throws -> String {
        guard isRunning, let analyzer, let resultTask else { throw ServiceError.notRunning }
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let attributed = await resultTask.value
        cleanup()
        return String(attributed.characters).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Cancel current session without returning text.
    func cancel() {
        Task { [analyzer] in
            await analyzer?.cancelAndFinishNow()
        }
        cleanup()
    }

    // MARK: ‑ Teardown
    private func cleanup() {
        resultTask?.cancel(); resultTask = nil
        analyzer = nil
        transcriber = nil
        isRunning = false
    }
}
