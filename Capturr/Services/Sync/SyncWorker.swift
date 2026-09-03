/// This worker sends ready outbox items to the correct Roam API and destination.
/// `SyncManager`, background refresh, and audio or Watch recovery paths create it
/// after captures become sendable. It drains one item at a time, resolves credentials
/// and profile rules, enriches Reader links, retries failures, and persists each result.

import Foundation
import SwiftData
import Network
import OSLog
import UIKit

final class SyncWorker {
    enum SyncPassResult: Equatable {
        case noWork
        case success
        case offline
        case sendFailure
        case persistenceFailure
    }

    // MARK: - State
    private let modelContext: ModelContext
    private static var inFlight: Set<UUID> = []
    private static var isTicking: Bool = false

    // MARK: - Logging / Networking
    private let logger = Logger(category: "SyncWorker")
    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "SyncWorker.Network")

    // MARK: - Loop
    private var retryLoop: Task<Void, Never>?
    private let tickIntervalSeconds: UInt64 = 10
    private let maxDrainItems = 100
    private let maxConcurrentSends: Int = 1
    private var monitorStarted = false
    private let minRetryGapSeconds: TimeInterval = 5 // Short-gap retry for .inProgress
    private let offlineRetryDelaySeconds: TimeInterval = 60

    // MARK: - Date Formatting (cached)
    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "HH:mm"
        return df
    }()

    // MARK: - Roam Reader
    private let linkMetadataService = LinkMetadataService()
    private let maxEnrichmentAttempts = 3

    // MARK: - Init / Deinit
    init(modelContext: ModelContext, monitorsForegroundConnectivity: Bool = false) {
        self.modelContext = modelContext
        if monitorsForegroundConnectivity {
            start()
        }
    }

    deinit {
        logger.info("SyncWorker deinit — stopping monitors")
        retryLoop?.cancel()
        pathMonitor.cancel()
    }

    // MARK: - Startup
    private func start() {
        if !monitorStarted {
            pathMonitor.pathUpdateHandler = { [weak self] path in
                guard let self else { return }
                if path.status == .satisfied {
                    self.logger.info("NWPathMonitor: online — kicking queue")
                    self.kick()
                } else {
                    self.logger.info("NWPathMonitor: offline")
                }
            }
            pathMonitor.start(queue: pathQueue)
            monitorStarted = true
        }
        startRetryLoop()
    }

    private func startRetryLoop() {
        retryLoop?.cancel()
        let interval = tickIntervalSeconds
        logger.info("Retry loop started (every \(interval)s)")
        // Use weak self throughout — a strong binding via guard let self
        // would be retained across Task.sleep, blocking deinit and leaking
        // workers created in transient contexts (e.g. drainCaptureOutbox).
        retryLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.drainPendingItems()
                try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
            }
        }
    }

    private func kick() {
        Task { [weak self] in
            await self?.drainPendingItems()
        }
    }

    // Processes due items sequentially for queue-level triggers. Offline,
    // persistence failure, cancellation, and the safety limit end the pass.
    func drainPendingItems() async {
        for _ in 0..<maxDrainItems {
            if Task.isCancelled { return }
            switch await syncNextPendingItem() {
            case .success, .sendFailure:
                continue
            case .noWork, .offline, .persistenceFailure:
                return
            }
        }
        logger.warning("Stopped outbox drain at the safety limit")
    }

    // Resolves credentials for an OutboxItem based on its targetGraphId.
    // Returns (graphName, apiToken) or nil if credentials not found (graph deleted).
    private func credentialsForItem(_ item: OutboxItem, profile: UserProfile) async -> (graphName: String, apiToken: String)? {
        if let targetId = item.targetGraphId {
            // Additional graph - lookup from profile and Keychain
            guard let graph = profile.additionalGraphs.first(where: { $0.id == targetId }),
                  let token = await CredentialsManager.shared.appendToken(forGraphId: targetId),
                  !token.isEmpty else {
                return nil  // Graph deleted or token missing
            }
            return (graph.name, token)
        }

        // Primary graph
        guard let graphName = profile.graphName, !graphName.isEmpty,
              let token = await CredentialsManager.shared.primaryAppendToken, !token.isEmpty else {
            return nil
        }
        return (graphName, token)
    }

    // Determines the Roam page to send this capture to.
    // Resolution order: item.overridePage (shortcut) → profile.useDailyNotes → profile.customLocation → daily note fallback.
    private func resolveLocation(for item: OutboxItem, from profile: UserProfile) -> RoamLocation {
        // Shortcut-level override takes priority (set by CaptureIntent when user specifies a page)
        if let overridePage = item.overridePage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !overridePage.isEmpty {
            return .page(overridePage)
        }
        if profile.useDailyNotes { return .dailyNote(item.createdAt) }
        if let page = profile.customLocation?.trimmingCharacters(in: .whitespacesAndNewlines),
           !page.isEmpty {
            return .page(page)
        }
        return .dailyNote(item.createdAt)
    }

    // Adds a timestamp (HH:mm) and/or appends tags to the raw capture content.
    // Checks item-level overrides first (set by CaptureIntent), falls back to profile defaults.
    // Example: "Buy milk" → "Buy milk 14:30 #errands"
    private func decoratedContent(for item: OutboxItem, using profile: UserProfile) -> String {
        decorateString(item.content, item: item, profile: profile)
    }

    // Appends timestamp and/or tags to an arbitrary string using the item/profile settings.
    // Used for both flat content and decorating the first block of nested captures.
    private func decorateString(_ base: String, item: OutboxItem, profile: UserProfile) -> String {
        var result = base

        // item.overrideTimestamp is set by CaptureIntent; nil for in-app captures → uses profile default
        let shouldTimestamp = item.overrideTimestamp ?? profile.addTimestamp
        if shouldTimestamp {
            let ts = item.createdAt
            let timestamp = formattedTimestamp(
                Self.timeFormatter.string(from: ts),
                options: profile.timestampFormatting
            )
            switch profile.timestampPosition {
            case .append:
                result += " \(timestamp)"
            case .prepend:
                result = "\(timestamp) \(result)"
            }
        }

        // item.overrideTags is set by CaptureIntent; nil for in-app captures → uses profile default
        let tagSource = item.overrideTags ?? profile.defaultTag
        if let tagRaw = tagSource?.trimmingCharacters(in: .whitespacesAndNewlines),
           !tagRaw.isEmpty {
            result += " \(tagRaw)"
        }

        return result
    }

    private func formattedTimestamp(
        _ timestamp: String,
        options: TimestampFormatOptions
    ) -> String {
        var result = timestamp

        if options.contains(.highlight) {
            result = "^^\(result)^^"
        }
        if options.contains(.italic) {
            result = "__\(result)__"
        }
        if options.contains(.bold) {
            result = "**\(result)**"
        }

        return result
    }

    private func backoffDelay(for attempt: Int, statusCode: Int?) -> TimeInterval {
        // Hard failures: short-circuit; actual stop handled separately
        if let code = statusCode, code == 401 || code == 403 { return 60 } // auth errors: 60s between the limited retries before hardError
        // Exponential backoff capped at ~64s with jitter
        let capped = min(attempt, 6)
        let base = pow(2.0, Double(capped)) // 2,4,8,16,32,64
        let jitter = Double.random(in: 0...1)
        return (base + jitter)
    }

    private func requestResult(
        _ operation: () async throws -> Void
    ) async -> Result<Void, Error> {
        do {
            try await operation()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func isKnownOfflineError(_ error: Error) -> Bool {
        if let metadataError = error as? LinkMetadataError,
           case .fetchFailed(let underlyingError) = metadataError {
            return isKnownOfflineError(underlyingError)
        }
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            return true
        default:
            return false
        }
    }

    func persistSendResult(
        _ sendResult: Result<Void, Error>,
        for item: OutboxItem,
        now: Date = Date(),
        retryDelay: ((_ attemptCount: Int, _ statusCode: Int?) -> TimeInterval)? = nil
    ) -> SyncPassResult {
        let previousStatus = item.status
        let previousSentAt = item.sentAt
        let previousLastError = item.lastError
        let previousAttemptCount = item.attemptCount
        let previousNextAttemptAt = item.nextAttemptAt
        let previousHardError = item.hardError
        let syncPassResult: SyncPassResult
        switch sendResult {
        case .success:
            item.attemptCount += 1
            item.status = SyncStatus.success.rawValue
            item.sentAt = now
            item.lastError = "OK"
            item.nextAttemptAt = nil
            item.hardError = false
            syncPassResult = .success
        case .failure(let error):
            item.status = SyncStatus.pending.rawValue
            if isKnownOfflineError(error) {
                item.nextAttemptAt = now.addingTimeInterval(offlineRetryDelaySeconds)
                syncPassResult = .offline
            } else {
                item.attemptCount += 1
                item.lastError = error.localizedDescription
                let statusCode = statusCode(for: error)
                if let code = statusCode, code == 401 || code == 403 {
                    // Preserve the existing shared-counter policy for auth responses.
                    if item.attemptCount < 3 {
                        item.hardError = false
                        let delay = retryDelay?(item.attemptCount, statusCode)
                            ?? backoffDelay(for: item.attemptCount, statusCode: statusCode)
                        item.nextAttemptAt = now.addingTimeInterval(delay)
                    } else {
                        // The third counted attempt becomes hard until credentials change.
                        item.hardError = true
                        item.nextAttemptAt = nil
                    }
                } else {
                    let delay = retryDelay?(item.attemptCount, statusCode)
                        ?? backoffDelay(for: item.attemptCount, statusCode: statusCode)
                    item.nextAttemptAt = now.addingTimeInterval(delay)
                }
                syncPassResult = .sendFailure
            }
        }

        do {
            try modelContext.save()
            return syncPassResult
        } catch {
            // Keep the in-memory object aligned with its last durable state so
            // this process can retry it after a failed result save.
            item.status = previousStatus
            item.sentAt = previousSentAt
            item.lastError = previousLastError
            item.attemptCount = previousAttemptCount
            item.nextAttemptAt = previousNextAttemptAt
            item.hardError = previousHardError
            logger.error("Failed to persist result for item \(item.id): \(error.localizedDescription)")
            return .persistenceFailure
        }
    }

    private func statusCode(for error: Error) -> Int? {
        if let apiError = error as? RoamAPIError {
            return apiError.statusCode
        }
        if let backendError = error as? RoamBackendAPIError {
            switch backendError {
            case .unauthorized: return 401
            case .badRequest: return 400
            case .rateLimitExceeded: return 429
            case .serverError, .serviceUnavailable: return 500
            default: return nil
            }
        }
        return nil
    }

    // Wraps scan-captured blocks in a "Document scanned" parent block with page count and timestamp.
    private static func scanParentBlock(wrapping blocks: [RoamBlock], capturedAt: Date) -> RoamBlock {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "HH:mm:ss"
        let timeString = fmt.string(from: capturedAt)
        let pageCount = blocks.filter { $0.string.hasPrefix("Page ") }.count
        let actualPageCount = max(pageCount, 1)
        let pageText = actualPageCount == 1 ? "1 page" : "\(actualPageCount) pages"
        let parentString = "Document (\(pageText)) scanned by [[CAPTURR]] at \(timeString)"
        return RoamBlock(string: parentString, children: blocks)
    }

    // MARK: - Queue processing
    // Processes at most one due item so lifecycle-aware callers can inspect its result.
    @MainActor
    @discardableResult
    func syncNextPendingItem() async -> SyncPassResult {
        if Self.isTicking {
            logger.debug("syncNextPendingItem: coalesce (already running)")
            return .noWork
        }
        Self.isTicking = true
        defer { Self.isTicking = false }

        // Get profile - we need it for settings
        let descriptor = FetchDescriptor<UserProfile>()
        let profile: UserProfile
        do {
            guard let fetchedProfile = try modelContext.fetch(descriptor).first else {
                logger.debug("syncNextPendingItem: skip (no profile)")
                return .noWork
            }
            profile = fetchedProfile
        } catch {
            logger.error("syncNextPendingItem: profile fetch failed: \(error.localizedDescription)")
            return .persistenceFailure
        }
        do {
            try ProfileManager(modelContext: modelContext)
                .migrateLegacyTimestampPreferences(in: profile)
        } catch {
            logger.error(
                "Failed to migrate legacy timestamp preferences: \(error.localizedDescription)"
            )
            return .persistenceFailure
        }

        // Check which APIs are configured (uses nonisolated Keychain checks)
        let hasGraphName = !(profile.graphName ?? "").isEmpty
        let hasAppendAPI = hasGraphName && CredentialsManager.shared.hasPrimaryAppendToken
        let hasBackendAPI = hasGraphName && CredentialsManager.shared.hasPrimaryBackendToken

        if !hasAppendAPI && !hasBackendAPI {
            logger.debug("syncNextPendingItem: skip (no APIs configured)")
            return .noWork
        }

        // Fetch all and filter in-memory — avoids predicate crashes on stale device schemas
        let pending = SyncStatus.pending.rawValue
        let inProgress = SyncStatus.inProgress.rawValue
        let itemsDescriptor = FetchDescriptor<OutboxItem>()

        let items: [OutboxItem]
        do {
            items = try modelContext.fetch(itemsDescriptor)
        } catch {
            logger.error("syncNextPendingItem: fetch failed: \(error.localizedDescription)")
            return .persistenceFailure
        }
        logger.debug("syncNextPendingItem: fetched=\(items.count)")

        let now = Date()

        let filtered = items.filter { item in
            // Never pick up items that are currently being sent
            if Self.inFlight.contains(item.id) { return false }

            // Skip hard errors until credentials/settings change
            if item.hardError ?? false { return false }

            // Items still in (or failed out of) the transcription stage have no
            // sendable content yet — TranscriptionWorker owns them until done
            if let ts = item.transcriptionState, ts != TranscriptionState.done.rawValue { return false }

            // Skip items that don't have the required API configured
            let isTodoStateChange = (item.type == .todo && item.action != nil)
            if isTodoStateChange && !hasBackendAPI { return false }

            // For regular captures: check if target graph has credentials
            // Primary graph uses hasAppendAPI, additional graphs need token lookup
            if !isTodoStateChange {
                if let targetId = item.targetGraphId {
                    // Additional graph - check if token exists
                    if !CredentialsManager.shared.hasAppendToken(forGraphId: targetId) { return false }
                } else {
                    // Primary graph
                    if !hasAppendAPI { return false }
                }
            }

            // Pending items: send if due (or no schedule)
            if item.status == pending {
                if let next = item.nextAttemptAt { return next <= now }
                return true
            }

            // In-progress items: retry after a small gap since last attempt
            if item.status == inProgress {
                let last = item.lastAttemptAt ?? .distantPast
                return last <= now.addingTimeInterval(-minRetryGapSeconds)
            }

            return false
        }

        logger.debug("syncNextPendingItem: candidates=\(filtered.count)")

        // Process items based on their type
        var syncPassResult: SyncPassResult = .noWork
        for item in filtered.prefix(maxConcurrentSends) {
            // Safety valve: clear stale in-flight marker before retry
            Self.inFlight.remove(item.id)

            let isTodoStateChange = (item.type == .todo && item.action != nil)
            let isRoamReader = item.isRoamReader ?? false
            logger.info("Starting sync attempt for item \(item.id, privacy: .public)")

            if isTodoStateChange {
                // TODO state changes use Backend API directly (always primary graph)
                syncPassResult = await syncTodoStateChange(item, profile: profile)
            } else if isRoamReader {
                // Roam Reader items need enrichment and send to Reading List: Inbox
                syncPassResult = await syncRoamReaderItem(item, profile: profile)
            } else {
                // Regular captures use Append API - resolve credentials based on targetGraphId
                if let creds = await credentialsForItem(item, profile: profile) {
                    let api = RoamAPI(graphName: creds.graphName, apiToken: creds.apiToken)
                    let location = resolveLocation(for: item, from: profile)
                    syncPassResult = await sync(item, using: api, profile: profile, location: location)
                } else {
                    // Graph credentials not found (graph deleted or token missing)
                    // Mark as failed, not pending (don't retry forever)
                    syncPassResult = markItemAsGraphNotConfigured(item)
                }
            }
            logger.info("Finished sync attempt for item \(item.id, privacy: .public)")
        }
        return syncPassResult
    }

    // Mark an item as failed because its target graph is no longer configured.
    private func markItemAsGraphNotConfigured(_ item: OutboxItem) -> SyncPassResult {
        item.status = SyncStatus.failed.rawValue
        item.lastError = "Graph no longer configured"
        item.nextAttemptAt = nil
        item.hardError = true  // Prevent retries
        do {
            try modelContext.save()
            logger.warning("Item \(item.id) marked as failed: target graph not configured")
            return .success
        } catch {
            logger.error("Failed to persist graph error for item \(item.id): \(error.localizedDescription)")
            return .persistenceFailure
        }
    }

    @MainActor
    private func sync(_ item: OutboxItem, using api: RoamAPI, profile: UserProfile, location: RoamLocation) async -> SyncPassResult {
        // Defensive: never send an item whose content is still a transcription placeholder.
        if let ts = item.transcriptionState, ts != TranscriptionState.done.rawValue { return .noWork }
        // Prevent double-send and mark in-progress
        if Self.inFlight.contains(item.id) { return .noWork }
        Self.inFlight.insert(item.id)

        // Hold an assertion across the SQLite saves below as well as the API call.
        // Without this, a background→suspended transition mid-save can have iOS
        // SIGKILL the process with RUNNINGBOARD 0xdead10cc (SQLite lock held during
        // suspension).
        let backgroundTask = BGTaskBox()
        backgroundTask.id = UIApplication.shared.beginBackgroundTask {
            backgroundTask.end()
        }
        defer {
            Self.inFlight.remove(item.id)
            backgroundTask.end()
        }

        item.status = SyncStatus.inProgress.rawValue
        item.lastAttemptAt = Date()
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to persist in-progress state for item \(item.id): \(error.localizedDescription)")
            return .persistenceFailure
        }

        // item.overrideNestUnder is set by CaptureIntent; nil for in-app captures → uses profile default
        let nestSource = item.overrideNestUnder ?? profile.customBlock
        let rawNest = nestSource?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nestUnderArg: String? = {
            guard let trimmedNestTarget = rawNest, !trimmedNestTarget.isEmpty else { return nil }
            return trimmedNestTarget
        }()

        let prepared = decoratedContent(for: item, using: profile)

        let sendResult: Result<Void, Error>
        switch item.type {
        case .todo:
            sendResult = await requestResult {
                try await api.sendTodoBlock(prepared, location, nestUnder: nestUnderArg)
            }
        case .note:
            if let data = item.content.data(using: .utf8) {
                // Try NestedCapture first (Write nested blocks)
                if let capture = try? JSONDecoder().decode(NestedCapture.self, from: data),
                   capture.source == "write" {
                    // Decorate first root block with timestamp/tags
                    var blocks = capture.blocks
                    if !blocks.isEmpty {
                        blocks[0].string = decorateString(blocks[0].string, item: item, profile: profile)
                    }
                    sendResult = await requestResult {
                        try await api.sendBlocks(blocks, location, nestUnder: nestUnderArg)
                    }
                }
                // Fall back to [RoamBlock] (Scan captures) — wrap in "Document scanned" parent
                else if let blocks = try? JSONDecoder().decode([RoamBlock].self, from: data) {
                    let parentBlock = Self.scanParentBlock(wrapping: blocks, capturedAt: item.createdAt)
                    sendResult = await requestResult {
                        try await api.sendBlocks([parentBlock], location, nestUnder: nestUnderArg)
                    }
                }
                // Flat text
                else {
                    sendResult = await requestResult {
                        try await api.sendNoteBlock(prepared, location, nestUnder: nestUnderArg)
                    }
                }
            } else {
                sendResult = await requestResult {
                    try await api.sendNoteBlock(prepared, location, nestUnder: nestUnderArg)
                }
            }
        }
        return persistSendResult(sendResult, for: item)
    }

    // MARK: - Roam Reader Sync

    @MainActor
    private func syncRoamReaderItem(_ item: OutboxItem, profile: UserProfile) async -> SyncPassResult {
        // Prevent double-send
        if Self.inFlight.contains(item.id) { return .noWork }
        Self.inFlight.insert(item.id)
        defer { Self.inFlight.remove(item.id) }

        // Hold an assertion across the saves and enrichment fetch. sendRoamReaderBlock
        // owns its own assertion for the API call itself.
        let backgroundTask = BGTaskBox()
        backgroundTask.id = UIApplication.shared.beginBackgroundTask {
            backgroundTask.end()
        }
        defer { backgroundTask.end() }

        item.status = SyncStatus.inProgress.rawValue
        item.lastAttemptAt = Date()
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to persist Reader in-progress state for item \(item.id): \(error.localizedDescription)")
            return .persistenceFailure
        }

        // Resolve credentials for target graph
        guard let creds = await credentialsForItem(item, profile: profile) else {
            return markItemAsGraphNotConfigured(item)
        }

        // Check if we need to enrich (only if not already enriched)
        if item.enrichedTitle == nil, let urlString = item.rawURL, let url = URL(string: urlString) {
            let currentAttempts = item.enrichmentAttempts ?? 0

            if currentAttempts < maxEnrichmentAttempts {
                do {
                    let metadata = try await linkMetadataService.fetchMetadata(for: url)

                    // Persist enrichment results
                    item.enrichedTitle = metadata.title
                    item.enrichedDescription = metadata.description
                    item.enrichedImageURL = metadata.imageURL
                    do {
                        try modelContext.save()
                    } catch {
                        logger.error("Failed to persist Reader metadata for item \(item.id): \(error.localizedDescription)")
                        return .persistenceFailure
                    }

                    logger.info("Roam Reader: enriched item \(item.id)")
                } catch {
                    if isKnownOfflineError(error) {
                        item.status = SyncStatus.pending.rawValue
                        item.nextAttemptAt = Date().addingTimeInterval(offlineRetryDelaySeconds)
                        do {
                            try modelContext.save()
                            return .offline
                        } catch {
                            logger.error("Failed to persist Reader offline retry for item \(item.id): \(error.localizedDescription)")
                            return .persistenceFailure
                        }
                    }
                    // Enrichment failed - increment attempts and maybe retry later
                    item.enrichmentAttempts = currentAttempts + 1
                    logger.warning("Roam Reader: enrichment failed for item \(item.id), attempt \(currentAttempts + 1)")

                    if (item.enrichmentAttempts ?? 0) < maxEnrichmentAttempts {
                        // Schedule retry with backoff
                        item.status = SyncStatus.pending.rawValue
                        let delay = backoffDelay(for: item.enrichmentAttempts ?? 1, statusCode: nil)
                        item.nextAttemptAt = Date().addingTimeInterval(delay)
                        do {
                            try modelContext.save()
                            return .sendFailure
                        } catch {
                            logger.error("Failed to persist Reader retry for item \(item.id): \(error.localizedDescription)")
                            return .persistenceFailure
                        }
                    }
                    // If max attempts reached, continue with fallback data
                    logger.info("Roam Reader: max enrichment attempts reached, using fallback data")
                    do {
                        try modelContext.save()
                    } catch {
                        logger.error("Failed to persist Reader enrichment attempts for item \(item.id): \(error.localizedDescription)")
                        return .persistenceFailure
                    }
                }
            }
        }

        backgroundTask.end()

        // Build and send the Roam Reader block
        return await sendRoamReaderBlock(item, using: creds)
    }

    // Builds and sends the Roam Reader block structure to the Reading List: Inbox page.
    @MainActor
    private func sendRoamReaderBlock(_ item: OutboxItem, using creds: (graphName: String, apiToken: String)) async -> SyncPassResult {
        let api = RoamAPI(graphName: creds.graphName, apiToken: creds.apiToken)

        // Resolve title with fallback chain
        let title = resolveRoamReaderTitle(for: item)

        // Build the nested block structure
        // Parent: Article: {title}
        // Children: Full Title, Category, Description, Document Tags, Date Captured, URL
        var childBlocks: [RoamBlock] = []

        childBlocks.append(RoamBlock(string: "Full Title:: \(title)"))
        childBlocks.append(RoamBlock(string: "Category:: #articles"))

        if let desc = item.enrichedDescription, !desc.isEmpty {
            childBlocks.append(RoamBlock(string: "Description:: \(desc)"))
        } else {
            childBlocks.append(RoamBlock(string: "Description::"))
        }

        childBlocks.append(RoamBlock(string: "Document Tags::"))

        let dateLink = RoamAPI.roamDateLink(from: item.createdAt)
        childBlocks.append(RoamBlock(string: "Date Captured:: \(dateLink)"))

        if let url = item.rawURL {
            childBlocks.append(RoamBlock(string: "URL:: \(url)"))
        }

        if let imageURL = item.enrichedImageURL, !imageURL.isEmpty {
            childBlocks.append(RoamBlock(string: "![](\(imageURL))"))
        }

        let parentBlock = RoamBlock(string: "Article: \(title)", children: childBlocks)

        // Hold the assertion across the save below and the API call.
        let backgroundTask = BGTaskBox()
        backgroundTask.id = UIApplication.shared.beginBackgroundTask {
            backgroundTask.end()
        }
        defer { backgroundTask.end() }

        let sendResult = await requestResult {
            try await api.sendToPage([parentBlock], pageName: "Reading List: Inbox")
        }
        return persistSendResult(sendResult, for: item)
    }

    // Resolves the title for a Roam Reader item using fallback chain:
    // 1. enrichedTitle (from LPMetadataProvider)
    // 2. content (Safari page title stored at share time)
    // 3. URL domain (extracted from rawURL)
    // 4. "Untitled"
    private func resolveRoamReaderTitle(for item: OutboxItem) -> String {
        // 1. Check enriched title
        if let title = item.enrichedTitle, !title.isEmpty {
            return title
        }

        // 2. Check content (Safari page title)
        let content = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !content.isEmpty {
            return content
        }

        // 3. Try to extract domain from URL
        if let urlString = item.rawURL, let url = URL(string: urlString), let host = url.host {
            return host
        }

        // 4. Fallback
        return "Untitled"
    }

    // MARK: - TODO State Change
    @MainActor
    private func syncTodoStateChange(_ item: OutboxItem, profile: UserProfile) async -> SyncPassResult {
        // Prevent double-send and mark in-progress
        if Self.inFlight.contains(item.id) { return .noWork }
        Self.inFlight.insert(item.id)
        defer { Self.inFlight.remove(item.id) }

        // Hold an assertion across the saves and the backend API call.
        let backgroundTask = BGTaskBox()
        backgroundTask.id = UIApplication.shared.beginBackgroundTask {
            backgroundTask.end()
        }
        defer { backgroundTask.end() }

        item.status = SyncStatus.inProgress.rawValue
        item.lastAttemptAt = Date()
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to persist TODO in-progress state for item \(item.id): \(error.localizedDescription)")
            return .persistenceFailure
        }

        // Call the actual send method
        let sendResult = await requestResult {
            try await sendTodoStateChange(for: item, profile: profile)
        }
        return persistSendResult(sendResult, for: item)
    }

    private func sendTodoStateChange(for item: OutboxItem, profile: UserProfile) async throws {
        guard let blockUid = item.roamBlockUid,
              let graphName = profile.graphName else {
            throw RoamAPIError(message: "Missing required TODO state change parameters", statusCode: nil)
        }

        // Get backend token from Keychain
        guard let apiToken = await CredentialsManager.shared.primaryBackendToken else {
            throw RoamAPIError(message: "Backend API token not configured", statusCode: nil)
        }

        // Determine direction of state change
        let markingAsDone = (item.action == "mark-done")

        // Use the original block string from OutboxItem.content
        // and replace the TODO/DONE marker
        let newString: String
        if markingAsDone {
            newString = item.content.replacingOccurrences(of: "{{[[TODO]]}}", with: "{{[[DONE]]}}")
        } else {
            newString = item.content.replacingOccurrences(of: "{{[[DONE]]}}", with: "{{[[TODO]]}}")
        }

        logger.info("Sending TODO state change: blockUid=\(blockUid), markingAsDone=\(markingAsDone)")

        // Use RoamBackendAPI to update the block
        let backendAPI = RoamBackendAPI(apiToken: apiToken)

        try await backendAPI.updateBlock(graphName: graphName, blockUid: blockUid, newString: newString)
    }
}

// Reference-typed holder for a UIBackgroundTaskIdentifier. Lets the expiration
// closure and the surrounding @MainActor async function share the identifier
// without tripping Swift's "mutated after capture by sendable closure" check —
// the closure captures the box, not the var. Access is main-actor-serialized
// in practice since both the handler and the call sites run on the main queue.
private final class BGTaskBox: @unchecked Sendable {
    var id: UIBackgroundTaskIdentifier = .invalid

    @MainActor
    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
