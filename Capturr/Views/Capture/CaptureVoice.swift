/// This view records speech or imports audio for private on-device transcription.
/// `CaptureHome` opens it for the voice route. Short recordings become outbox items
/// immediately, while imported files enter the background transcription pipeline;
/// both retain the selected graph destination from the shared profile.

import SwiftUI
import SwiftData
import Speech
import UniformTypeIdentifiers

struct CaptureVoice: View {
    // Optional hook for callers that also need the completed one-shot transcript.
    var onTranscript: (String) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var profileViewModel: ProfileViewModel

    @State private var voiceInput: VoiceInput?
    @State private var isRecording = false
    @State private var statusMessage: String = "Tap the icon above to start recording"
    @State private var installedDictationTags: Set<String> = [] // lowercased BCP‑47 of DictationTranscriber.installedLocales
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var supportedDictationTags: Set<String> = [] // lowercased BCP‑47 of DictationTranscriber.supportedLocales

    @State private var selectedGraphId: String? = nil  // nil = primary graph
    @State private var selectedGraphName: String = ""

    // Imported files use the same background transcription pipeline as watch captures.
    @State private var showImporter = false
    @State private var isPreparingImport = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 16) {
                
                Button(action: toggle) {
                    ZStack {
                        Circle()
                            .fill(isRecording ? Color.red : Color.blue)
                            .frame(width: 88, height: 88)
                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .foregroundStyle(.white)
                            .font(.system(size: 32, weight: .semibold))
                            .offset(y: 1)
                    }
                    .padding(.top)
                }
                .disabled(!isSelectedLanguageSupported || isDownloading || isPreparingImport)
                .opacity(isSelectedLanguageSupported && !isDownloading && !isPreparingImport ? 1 : 0.4)
                .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
                
                Text("Voice Capture")
                    .font(.title2)
                    .bold()
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .init(horizontal: .center, vertical: .top))

                if isMultiGraphEnabled {
                    graphSelectorView
                        .padding(.top, 8)
                }

                if isDownloading {
                    ProgressView(value: downloadProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .padding(.horizontal)
                }

                if isPreparingImport {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Preparing audio…")
                    }
                    .font(.subheadline)
                    .padding(.horizontal)
                }
                
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

            }
            .padding()
            .padding(.bottom)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
            VStack(alignment: .leading) {
                Text("**Transcription language:** \(displayName(for: profileViewModel.voiceLanguage)). This language is used for voice capture and imported audio. Manage Dictation Languages in Settings > General > Keyboard.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal)

                Text("**Audio file import:** Files up to 60 minutes are supported. Large files may take several minutes to process. Transcription happens privately on this iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal)
                    .padding(.top, 4)
                
                if isSelectedLanguageSupported && !isSelectedLanguageInstalled {
                    Text("First use will download the dictation model for this language.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .padding()
                } else if !isSelectedLanguageSupported {
                    Text("This language isn't available to third‑party apps for on‑device dictation on iOS.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .padding()
                }
            }
            Spacer()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showImporter = true
                } label: {
                    Image(systemName: "waveform.badge.plus")
                }
                .disabled(
                    isRecording ||
                    isDownloading ||
                    isPreparingImport ||
                    !isSelectedLanguageSupported
                )
                .accessibilityLabel("Import audio file")
            }
        }
        .task {
            // Cache both sets because availability controls recording, import, and download messaging.
            let installed = await DictationTranscriber.installedLocales.map { $0.identifier(.bcp47).lowercased() }
            let supported = await DictationTranscriber.supportedLocales.map { $0.identifier(.bcp47).lowercased() }
            installedDictationTags = Set(installed)
            supportedDictationTags = Set(supported)
        }
        .onDisappear {
            if isRecording {
                voiceInput?.cancel()
                isRecording = false
            }
            voiceInput = nil
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { result in
            handleImportResult(result)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Audio File Import

    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain,
               nsError.code == CocoaError.userCancelled.rawValue {
                return
            }
            statusMessage = AudioImportError.fileProvider.localizedDescription
        case .success(let url):
            let graphId = effectiveGraphId
            let graphName = effectiveGraphName
            isPreparingImport = true
            statusMessage = ""
            Task {
                defer { isPreparingImport = false }
                do {
                    try await AudioImportCoordinator.importAudio(
                        from: url,
                        targetGraphId: graphId,
                        targetGraphName: graphName,
                        modelContext: modelContext
                    )
                    profileViewModel.lastUsedGraphId = graphId
                    do {
                        try profileViewModel.saveChanges(context: modelContext)
                    } catch {
                        // The OutboxItem is already durable. A preference-save
                        // failure must not misrepresent the import itself.
                    }
                    statusMessage = "Saved. Now transcribing on this iPhone."
                } catch {
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: Actions

    private func toggle() {
        if isDownloading || isPreparingImport {
            return
        }
        if isRecording {
            Task {
                var insertedItem: OutboxItem?
                do {
                    let text = try await voiceInput?.end() ?? ""
                    isRecording = false
                    voiceInput = nil
                    if text.isEmpty {
                        statusMessage = "No voice/input detected"
                    } else {
                        let trimmedTranscript = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let item = OutboxItem(content: trimmedTranscript, type: .note)

                        item.targetGraphId = effectiveGraphId
                        item.targetGraphName = effectiveGraphName

                        profileViewModel.lastUsedGraphId = effectiveGraphId

                        modelContext.insert(item)
                        insertedItem = item
                        try profileViewModel.saveChanges(context: modelContext)
                        BackgroundSyncScheduler.scheduleAfterEnqueue(itemIDs: [item.id])

                        onTranscript(trimmedTranscript)

                        statusMessage = "Saved"
                    }
                } catch {
                    if let insertedItem { modelContext.delete(insertedItem) }
                    isRecording = false
                    voiceInput = nil
                    statusMessage = error.localizedDescription
                }
            }
        } else {
            Task {
                do {
                    voiceInput = VoiceInput(localeTag: profileViewModel.voiceLanguage) { status in
                        self.statusMessage = status
                        let normalizedStatus = status.lowercased()
                        if normalizedStatus.contains("downloading") {
                            isDownloading = true
                            if let progressFraction = parseProgress(from: status) {
                                downloadProgress = progressFraction
                            } else {
                                downloadProgress = 0
                            }
                        } else if normalizedStatus.contains("installed") || normalizedStatus.contains("ready") {
                            isDownloading = false
                            downloadProgress = 1.0
                        }
                    }
                    try await voiceInput?.begin()
                    isRecording = true
                    statusMessage = "Recording voice, tap again to finish"
                } catch {
                    voiceInput = nil
                    isRecording = false
                    statusMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func parseProgress(from status: String) -> Double? {
        // VoiceInput reports model-download progress as human-readable status text.
        let pattern = #"(\d+)%?"#
        if let range = status.range(of: pattern, options: .regularExpression) {
            let substring = status[range]
            if let value = Double(substring.trimmingCharacters(in: CharacterSet(charactersIn: "%"))) {
                return value / 100.0
            }
        }
        return nil
    }

    // MARK: Helpers

    private var isSelectedLanguageInstalled: Bool {
        installedDictationTags.contains(profileViewModel.voiceLanguage.lowercased())
    }
    
    private var isSelectedLanguageSupported: Bool {
        supportedDictationTags.contains(profileViewModel.voiceLanguage.lowercased())
    }

    private func displayName(for tag: String) -> String {
        if tag.caseInsensitiveCompare("en-US") == .orderedSame {
            return "English (US)"
        }
        return Locale.current.localizedString(forIdentifier: tag) ?? tag
    }

    // MARK: - Multi-Graph Support

    private var isMultiGraphEnabled: Bool {
        profileViewModel.multiGraphEnabled && !profileViewModel.additionalGraphs.isEmpty
    }

    private var effectiveGraphId: String? {
        if isMultiGraphEnabled {
            return selectedGraphId
        }
        return nil
    }

    private var effectiveGraphName: String {
        if isMultiGraphEnabled && !selectedGraphName.isEmpty {
            return selectedGraphName
        }
        return profileViewModel.graphName ?? "Primary Graph"
    }

    @ViewBuilder
    private var graphSelectorView: some View {
        let effectiveLastUsedGraphId = profileViewModel.effectiveLastUsedGraphId()

        Menu {
            let primaryName = profileViewModel.graphName ?? "Primary Graph"
            Button {
                selectedGraphId = nil
                selectedGraphName = primaryName
            } label: {
                HStack {
                    Text("\(primaryName)")
                    if selectedGraphId == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            ForEach(profileViewModel.additionalGraphs.sorted { $0.name.lowercased() < $1.name.lowercased() }) { graph in
                Button {
                    selectedGraphId = graph.id
                    selectedGraphName = graph.name
                } label: {
                    HStack {
                        Text(graph.name)
                        if selectedGraphId == graph.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text(effectiveGraphName)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .disabled(isPreparingImport)
        .onAppear {
            // Seed the menu from the quick-capture preference when it first appears.
            if profileViewModel.multiGraphDefaultToLast, let lastUsedGraphId = effectiveLastUsedGraphId {
                selectedGraphId = lastUsedGraphId
                selectedGraphName = profileViewModel.graphDisplayName(for: lastUsedGraphId)
            } else {
                selectedGraphId = nil
                selectedGraphName = profileViewModel.graphName ?? "Primary Graph"
            }
        }
    }
}

#Preview {
    NavigationStack {
        CaptureVoice()
            .environmentObject(ProfileViewModel())
    }
}
