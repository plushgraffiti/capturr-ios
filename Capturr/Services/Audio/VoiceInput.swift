/// This input helper records one live voice capture and returns its transcription.
/// `CaptureVoice` creates it when recording starts. It configures the audio session and
/// microphone stream, then hands that stream to `VoiceSpeechService` for speech analysis.
/// It also owns cleanup so stopping or failing a recording releases the microphone safely.

import Foundation
@preconcurrency import AVFoundation
import Speech
import UIKit

@MainActor
final class VoiceInput {


    private var service: VoiceSpeechService?
    private let localeTag: String
    private let statusHandler: ((String) -> Void)?

    // Mic pipeline
    private var engine: AVAudioEngine?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var inputStream: AsyncStream<AnalyzerInput>?
    private var converter: AVAudioConverter?
    private var lastInstallError: VoiceCaptureError?

    init(localeTag: String, statusHandler: ((String) -> Void)? = nil) {
        self.localeTag = localeTag
        self.statusHandler = statusHandler
    }

    // MARK: - Lifecycle

    func begin() async throws {
        // Normalize to an installed, regioned variant if the incoming tag lacks one (generic, no hardcoded codes)
        var tag = localeTag
        if !tag.contains("-") {
            let keyboardTags = UITextInputMode.activeInputModes.compactMap { $0.primaryLanguage }
            if let fromKeyboard = keyboardTags.first(where: { $0.lowercased().hasPrefix(tag.lowercased()) }) {
                tag = fromKeyboard
            } else {
                let installed = await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) }
                if let fromInstalled = installed.first(where: { $0.lowercased().hasPrefix(tag.lowercased()) }) {
                    tag = fromInstalled
                }
            }
        }
        let locale = Locale(identifier: tag)

        // Ensure dictation model is installed if supported
        await ensureDictationModelInstalled(for: locale)

        // If dictation model installation failed with a specific, known error, surface that instead of a generic analyzer message.
        if let installErr = lastInstallError {
            throw installErr
        }

        // Try a small set of dictation presets (Notes-like behavior varies by locale)
        let presets: [DictationTranscriber.Preset] = [.progressiveShortDictation, .shortDictation]
        var selectedTranscriber: DictationTranscriber?
        var requiredFormat: AVAudioFormat?

        for preset in presets {
            let transcriber = DictationTranscriber(locale: locale, preset: preset)

            if let compatibleFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) {
                selectedTranscriber = transcriber
                requiredFormat = compatibleFormat
                break
            }
        }

        guard let transcriber = selectedTranscriber, let requiredFormat = requiredFormat else {
            throw VoiceCaptureError.analyzerIncompatibleFormat
        }
        statusHandler?("Ready")
        // Inform UI that the pipeline is ready before capture begins
        let speechService = VoiceSpeechService()

        // Configure audio session
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true)

        // Set up engine + tap
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let hardwareFormat = input.outputFormat(forBus: 0)

        // Prepare a reusable converter so every buffer matches the analyzer's required format
        if hardwareFormat != requiredFormat {
            converter = AVAudioConverter(from: hardwareFormat, to: requiredFormat)
        } else {
            converter = nil
        }

        // Create stream/continuation pair
        let pair = AsyncStream<AnalyzerInput>.makeStream()
        self.inputStream = pair.stream
        self.inputContinuation = pair.continuation

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // Avoid yielding multiple overlapping buffers
            guard buffer.frameLength > 0 else { return }

            // Convert if needed
            var analysisBuffer: AVAudioPCMBuffer = buffer
            if hardwareFormat != requiredFormat, let converter = self.converter {
                if let converted = try? self.convert(buffer, with: converter, to: requiredFormat) {
                    analysisBuffer = converted
                }
            }

            // Ensure analyzer format compliance
            guard analysisBuffer.format.channelCount == 1 else { return }

            // Yield a copy to prevent concurrent buffer reuse issues
            if let cloned = analysisBuffer.copy() as? AVAudioPCMBuffer {
                self.inputContinuation?.yield(AnalyzerInput(buffer: cloned))
            } else {
                self.inputContinuation?.yield(AnalyzerInput(buffer: analysisBuffer))
            }
        }

        self.engine = engine
        try engine.start()

        // Hand stream to service
        if let stream = self.inputStream {
            try await speechService.start(transcriber: transcriber,
                                inputSequence: stream,
                                requiredFormat: requiredFormat)
        }
        self.service = speechService
    }

    func end() async throws -> String {
        // Stop feeding, close the stream, then finalize analysis
        inputContinuation?.finish()
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        guard let speechService = service else { throw VoiceCaptureError.notRecording }
        let text = try await speechService.stopAndGetTranscript()
        cleanup()
        return text
    }

    func cancel() {
        inputContinuation?.finish()
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        service?.cancel()
        cleanup()
    }

    private func convert(_ buffer: AVAudioPCMBuffer,
                         with converter: AVAudioConverter,
                         to: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let out = AVAudioPCMBuffer(pcmFormat: to, frameCapacity: buffer.frameCapacity) else {
            throw VoiceCaptureError.bufferAllocationFailed
        }
        var error: NSError?
        var consumed = false
        converter.convert(to: out, error: &error) { _, status in
            status.pointee = consumed ? .noDataNow : .haveData
            consumed = true
            return buffer
        }
        if let error { throw error }
        return out
    }

    private func convert(_ buffer: AVAudioPCMBuffer, from: AVAudioFormat, to: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let converter = AVAudioConverter(from: from, to: to) else {
            throw VoiceCaptureError.converterCreationFailed
        }
        guard let out = AVAudioPCMBuffer(pcmFormat: to, frameCapacity: buffer.frameCapacity) else {
            throw VoiceCaptureError.bufferAllocationFailed
        }
        var error: NSError?
        var consumed = false
        converter.convert(to: out, error: &error) { _, status in
            status.pointee = consumed ? .noDataNow : .haveData
            consumed = true
            return buffer
        }
        if let error { throw error }
        return out
    }


    // MARK: - Dictation (Assistant) asset install if available
    private func ensureDictationModelInstalled(for locale: Locale) async {
        let installed = await DictationTranscriber.installedLocales
        if installed.contains(where: { $0.identifier(.bcp47).lowercased() == locale.identifier(.bcp47).lowercased() }) {
            return
        }
        if let equivalent = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            let installedLowercased = installed.map { $0.identifier(.bcp47).lowercased() }
            let eqIDLowercased = equivalent.identifier(.bcp47).lowercased()
            if !installedLowercased.contains(eqIDLowercased) {
                do {
                    if let request = try await AssetInventory.assetInstallationRequest(supporting: [DictationTranscriber(locale: equivalent, preset: .shortDictation)]) {
                        let readable = Locale.current.localizedString(forIdentifier: equivalent.identifier(.bcp47)) ?? equivalent.identifier(.bcp47)
                        statusHandler?("Preparing \(readable)")
                        let progress = request.progress
                        statusHandler?("Downloading model (0%)")

                        var obs: NSKeyValueObservation?
                        obs = progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] prog, _ in
                            let pct = max(0, min(100, Int(prog.fractionCompleted * 100)))
                            Task { @MainActor in
                                self?.statusHandler?("Downloading model (\(pct)%)")
                            }
                        }
                        defer { obs?.invalidate() }

                        try await request.downloadAndInstall()
                        statusHandler?("Model installed")
                    } else {
                        lastInstallError = .dictationModelUnavailable
                    }
                } catch {
                    let ns = error as NSError
                    if ns.domain == "SFSpeechErrorDomain" && ns.code == 11 {
                        lastInstallError = .dictationModelCapacityExceeded
                    } else {
                        lastInstallError = .dictationModelUnavailable
                    }
                }
            }
        }
    }

    private func cleanup() {
        converter = nil
        service = nil
        engine = nil
        inputContinuation = nil
        inputStream = nil
        lastInstallError = nil
    }
    
}
