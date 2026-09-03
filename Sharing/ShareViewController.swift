/// This view controller is the iOS entry point for Capturr's share extension.
/// `Sharing/Info.plist` registers it for shared text and URLs, so the system creates it
/// when Capturr is chosen from a share sheet. It extracts the attachment, embeds `ShareView`,
/// and saves the chosen capture to the app-group store for `SyncWorker` to send later.

import UIKit
import SwiftUI
import UniformTypeIdentifiers
import Combine
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.capturr.app", category: "ShareExtension")

@MainActor
final class ShareModel: ObservableObject {
    @Published var text: String = ""
    @Published var isURLShare: Bool = false

    // URL metadata stays alongside the editable text so the controller can create
    // either a normal note or a Roam Reader outbox item from the same editor.
    var rawURL: String?
    var pageTitle: String?
}

@objc(ShareViewController)
class ShareViewController: UIViewController {
    // MARK: - UI and State

    private var hostingController: UIHostingController<AnyView>?

    // UIKit may report appearance more than once, but an extension invocation should
    // extract one attachment and persist at most one outbox item.
    private var didExtract = false
    private let model = ShareModel()
    private let modelContainer: ModelContainer = SharedModelContainer()
    private var didSave = false

    // The controller snapshots profile choices before constructing the SwiftUI view.
    private var roamReaderEnabled = false
    private var multiGraphEnabled = false
    private var primaryGraphName: String?
    private var additionalGraphs: [ShareAdditionalGraph] = []

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didExtract else { return }
        didExtract = true

        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem else {
            close()
            return
        }

        // Safari often supplies a title separately from the URL attachment.
        let pageTitle: String? = extensionItem.attributedContentText?.string.trimmingCharacters(in: .whitespacesAndNewlines)
        model.pageTitle = pageTitle

        // Prefer a URL over accompanying plain text so the Reader path keeps its metadata.
        let urlTypes = ["public.url", "public.file-url"]
        if let attachments = extensionItem.attachments {
            for provider in attachments {
                for urlType in urlTypes {
                    if provider.hasItemConformingToTypeIdentifier(urlType) {
                        loadURL(from: provider, pageTitle: pageTitle)
                        return
                    }
                }
            }
        }

        // If no attachment exposes a URL, use the first plain-text representation.
        guard let itemProvider = extensionItem.attachments?.first else {
            close()
            return
        }

        let plainId = UTType.plainText.identifier
        if itemProvider.hasItemConformingToTypeIdentifier(plainId) {
            loadPlainText(from: itemProvider)
            return
        }

        close()
    }

    // MARK: - Helpers

    // Formats URL editor text using the shared profile's link preference.
    private func formatURLText(urlString: String, pageTitle: String?) -> String {
        let cleanedTitle = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines)

        // The extension reads the same app-group profile that the main app edits.
        let modelContext = ModelContext(self.modelContainer)
        let profile: UserProfile? = try? modelContext.fetch(FetchDescriptor<UserProfile>()).first

        if let profile, profile.shareFormatLinks {
            // A missing title falls back to showing the URL inside the Roam-style link.
            let visible = (cleanedTitle?.isEmpty == false) ? cleanedTitle! : urlString
            return clamp("[\(visible)](\(urlString))")
        }

        if let title = cleanedTitle, !title.isEmpty, title != urlString {
            return clamp(title + " - " + urlString)
        } else {
            return clamp(urlString)
        }
    }

    // Limits unusually large provider payloads before they reach the editor or SwiftData.
    private func clamp(_ s: String, limit: Int = 50_000) -> String {
        if s.count <= limit { return s }
        let endIndex = s.index(s.startIndex, offsetBy: limit)
        return String(s[..<endIndex])
    }

    // Loads plain text into the editor, or closes when the provider cannot produce usable text.
    private func loadPlainText(from provider: NSItemProvider) {
        let plainId = UTType.plainText.identifier
        provider.loadItem(forTypeIdentifier: plainId, options: nil) { [weak self] (provided, error) in
            DispatchQueue.main.async {
                guard let self else { return }
                if error != nil { self.close(); return }
                if let s = provided as? String {
                    self.model.text = self.clamp(s)
                    self.model.isURLShare = false
                } else if let d = provided as? Data, let s = String(data: d, encoding: .utf8) {
                    self.model.text = self.clamp(s)
                    self.model.isURLShare = false
                } else {
                    self.close()
                }
            }
        }
    }

    // Normalizes the provider's possible URL representations before populating the editor.
    private func loadURL(from provider: NSItemProvider, pageTitle: String?) {
        let urlId = "public.url"
        provider.loadItem(forTypeIdentifier: urlId, options: nil) { [weak self] (urlItem, error) in
            DispatchQueue.main.async {
                guard let self else { return }
                if error != nil { self.close(); return }

                var urlString: String?
                if let url = urlItem as? URL {
                    urlString = url.absoluteString
                } else if let nsurl = urlItem as? NSURL {
                    urlString = (nsurl as URL).absoluteString
                } else if let s = urlItem as? String, URL(string: s) != nil {
                    urlString = s
                } else if let d = urlItem as? Data, let s = String(data: d, encoding: .utf8), URL(string: s) != nil {
                    urlString = s
                }

                guard let urlString else {
                    self.close()
                    return
                }

                self.model.text = self.formatURLText(urlString: urlString, pageTitle: pageTitle)
                self.model.isURLShare = true
                self.model.rawURL = urlString
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        loadProfileSettings()

        let graphConfig = ShareGraphConfig(
            primaryGraphName: primaryGraphName,
            multiGraphEnabled: multiGraphEnabled,
            additionalGraphs: additionalGraphs
        )

        let root = ShareView(
            model: model,
            graphConfig: graphConfig,
            roamReaderEnabled: roamReaderEnabled,
            onPost: { [weak self] params in
                self?.handlePost(params: params, isRoamReader: false)
            },
            onPostRoamReader: { [weak self] params in
                self?.handlePost(params: params, isRoamReader: true)
            }
        )
        let rootView = AnyView(root.modelContainer(modelContainer))

        let hostingController = UIHostingController(rootView: rootView)
        self.hostingController = hostingController
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)

        NotificationCenter.default.addObserver(forName: NSNotification.Name("Close"), object: nil, queue: .main) { [weak self] _ in
            self?.close()
        }
    }

    // Copies the shared profile values needed by this short-lived extension session.
    private func loadProfileSettings() {
        let modelContext = ModelContext(self.modelContainer)
        guard let profile = try? modelContext.fetch(FetchDescriptor<UserProfile>()).first else {
            return
        }

        roamReaderEnabled = profile.roamReaderEnabled
        multiGraphEnabled = profile.multiGraphEnabled ?? false
        primaryGraphName = profile.graphName

        additionalGraphs = profile.additionalGraphs.map { graph in
            ShareAdditionalGraph(id: graph.id, name: graph.name)
        }
    }

    // Converts either send action into one durable outbox item, then dismisses the extension.
    private func handlePost(params: ShareSendParams, isRoamReader: Bool) {
        guard !didSave else { return }
        didSave = true

        Task { @MainActor in
            let modelContext = ModelContext(self.modelContainer)
            let text = self.model.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // A whitespace-only edit has nothing meaningful to persist.
            if text.isEmpty { self.close(); return }

            let item: OutboxItem
            if isRoamReader {
                // Reader sync enriches rawURL later; the page title remains its offline fallback.
                item = OutboxItem(content: self.model.pageTitle ?? "", type: .note)
                item.isRoamReader = true
                item.rawURL = self.model.rawURL
            } else {
                item = OutboxItem(content: text, type: .note)
            }

            item.targetGraphId = params.graphId
            item.targetGraphName = params.graphName

            modelContext.insert(item)
            do {
                try modelContext.save()
                BackgroundSyncScheduler.scheduleAfterEnqueue(itemIDs: [item.id])
                self.close()
            } catch {
                modelContext.delete(item)
                self.didSave = false
                logger.error("Failed to save shared capture: \(error.localizedDescription)")
            }
        }
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
