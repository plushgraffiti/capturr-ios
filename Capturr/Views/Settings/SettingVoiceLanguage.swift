/// This view chooses the language used for on-device voice transcription.
/// `SettingsHome` presents it from Capture Preferences. It matches the user's
/// installed keyboards with locales supported by `DictationTranscriber`, then
/// saves the chosen canonical language tag for voice and imported-audio captures.

import SwiftUI
import UIKit
import SwiftData
import Speech

struct SettingVoiceLanguage: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ProfileViewModel

    // MARK: - Model

    struct KeyboardLanguage: Identifiable, Hashable {
        enum Status: Int { case installed = 0, downloadable = 1, unavailable = 2 }
        let id: String                 // original keyboard tag (e.g. "yue-Hant-HK")
        let dictationTag: String?      // canonical dictation tag (e.g. "zh-hk") if supported
        let displayName: String        // user-facing name
        let status: Status             // installed / downloadable / unavailable
    }

    @State private var keyboardLanguages: [KeyboardLanguage] = []
    @State private var selectedDictationTag: String = ""          // canonical dictation tag we store

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                
                VStack(spacing: 16) {
                    
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 80, height: 80)
                        Image(systemName: "globe")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.white)
                    }
                    .padding(.top)

                    Text("Dictation Language")
                        .font(.title2)
                        .bold()
                        .multilineTextAlignment(.center)

                    Text("Choose your primary language for on‑device dictation. If a model isn’t installed yet, we'll download it the first time you record.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(sortedKeyboardLanguages) { item in
                            Button {
                                guard item.status != .unavailable, let canonical = item.dictationTag else { return }
                                selectedDictationTag = canonical
                                viewModel.voiceLanguage = canonical
                                try? viewModel.saveChanges(context: context)
                            } label: {
                                HStack(spacing: 10) {
                                    Text(item.displayName)
                                        .foregroundStyle(item.status == .unavailable ? .secondary : .primary)
                                        .lineLimit(2)

                                    

                                    switch item.status {
                                    case .installed:
                                        LanguageStatusBadge(text: "Installed", tint: .blue)
                                    case .downloadable:
                                        LanguageStatusBadge(text: "Download", tint: .gray)
                                    case .unavailable:
                                        LanguageStatusBadge(text: "Unavailable", tint: .gray.opacity(0.6))
                                    }

                                    Spacer()
                                    
                                    if let canonical = item.dictationTag, canonical == selectedDictationTag, item.status != .unavailable {
                                        Image(systemName: "checkmark")
                                            .imageScale(.medium)
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .disabled(item.status == .unavailable)

                            Divider()
                        }
                    }
                    .task { await loadLanguagesAndSeed() }
                    .padding()
                }
                .padding()
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("For privacy, we only support on-device transcription. For more information, see the official Apple list of supported languages for on-device dictation. **[Learn more](https://www.apple.com/ios/feature-availability/#dictation-on-device)**")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal)

                Spacer()
            }
            .padding()
        }
        .background(Color(.secondarySystemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    try? viewModel.saveChanges(context: context)
                    dismiss()
                }
            }
        }
    }

    // MARK: - Helpers

    private var sortedKeyboardLanguages: [KeyboardLanguage] {
        keyboardLanguages.sorted { lhs, rhs in
            if lhs.status != rhs.status { return lhs.status.rawValue < rhs.status.rawValue }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func displayName(for tag: String) -> String {
        // Match Apple's Dictation wording where a raw locale name would be unclear.
        let key = tag.lowercased()
        let overrides: [String: String] = [
            "zh-cn": "Mandarin (China Mainland)",
            "zh-tw": "Mandarin (Taiwan)",
            "zh-hk": "Cantonese (Hong Kong)",
            "yue-cn": "Cantonese Simplified (China Mainland)"
        ]
        if let custom = overrides[key] { return custom }
        return Locale.current.localizedString(forIdentifier: tag) ?? tag
    }

    private func canonicalTag(_ locale: Locale) -> String {
        locale.identifier(.bcp47).lowercased()
    }

    private func loadLanguagesAndSeed() async {
        // Start with installed keyboards so the list reflects languages the user actually uses.
        let keyboardTags: [String] = UITextInputMode.activeInputModes
            .compactMap { $0.primaryLanguage }
            .filter { $0.lowercased() != "emoji" }

        // Some input modes report the same language tag; keep only the first occurrence.
        var seen = Set<String>()
        let uniqueKeyboardTags = keyboardTags.filter { tag in
            let low = tag.lowercased()
            if seen.contains(low) { return false }
            seen.insert(low)
            return true
        }

        // Canonical tags let differently formatted keyboard and dictation identifiers compare safely.
        let installedSet = Set(await DictationTranscriber.installedLocales.map { canonicalTag($0) })

        // A keyboard can exist even when Apple's public on-device dictation API has no match.
        var loadedLanguages: [KeyboardLanguage] = []
        loadedLanguages.reserveCapacity(uniqueKeyboardTags.count)

        for keyboardTag in uniqueKeyboardTags {
            let keyboardLocale = Locale(identifier: keyboardTag)
            let resolved = await DictationTranscriber.supportedLocale(equivalentTo: keyboardLocale)
            if let dictationLocale = resolved {
                let dictationTag = canonicalTag(dictationLocale)
                let status: KeyboardLanguage.Status = installedSet.contains(dictationTag) ? .installed : .downloadable
                let name = displayName(for: dictationTag)
                loadedLanguages.append(.init(id: keyboardTag, dictationTag: dictationTag, displayName: name, status: status))
            } else {
                let name = Locale.current.localizedString(forIdentifier: keyboardTag) ?? keyboardTag
                loadedLanguages.append(.init(id: keyboardTag, dictationTag: nil, displayName: name, status: .unavailable))
            }
        }

        // Preserve the saved choice when possible; otherwise choose the best usable fallback.
        let savedDictationTag = viewModel.voiceLanguage.lowercased()
        let matchingLanguage = loadedLanguages.first { $0.dictationTag == savedDictationTag && $0.status != .unavailable }
        if let match = matchingLanguage, let canonical = match.dictationTag {
            selectedDictationTag = canonical
        } else if let firstInstalled = loadedLanguages.first(where: { $0.status == .installed })?.dictationTag {
            selectedDictationTag = firstInstalled
            viewModel.voiceLanguage = firstInstalled
            try? viewModel.saveChanges(context: context)
        } else if let firstDownloadable = loadedLanguages.first(where: { $0.status == .downloadable })?.dictationTag {
            selectedDictationTag = firstDownloadable
            viewModel.voiceLanguage = firstDownloadable
            try? viewModel.saveChanges(context: context)
        }

        // Publish once after the async lookups to avoid showing a partially built list.
        keyboardLanguages = loadedLanguages
    }
}



#Preview {
    NavigationStack {
        SettingVoiceLanguage(viewModel: ProfileViewModel())
    }
}
