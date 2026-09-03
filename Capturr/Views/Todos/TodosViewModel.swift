/// This view model is the behind-the-scenes organizer for the TODOs screen
/// owned by `TodosHome`. `TodosHomeHandlers` feeds it saved TODOs, queued
/// changes, and profile settings. It turns those inputs into flat or sectioned
/// lists, asks `TodoSyncManager` to refresh them from Roam, queues new TODOs,
/// and keeps the app icon badge in sync.

import Foundation
import SwiftData
import UserNotifications

// The same Roam TODO can match more than one section. Combining the section and
// block identities gives SwiftUI a distinct row identity in each section.
struct SectionTodo: Identifiable {
    let id: String
    let todo: TodoItem
}

@MainActor
final class TodosViewModel: ObservableObject {
    // MARK: - State

    // TodosHome reads these values to choose its current screen state and binds
    // the new-TODO fields directly to its inline editor.
    @Published var isAddingTodo = false
    @Published var newTodoText = ""
    @Published var lastError: String?
    @Published var filteredTodos: [TodoItem] = []
    @Published var pendingOutboxItems: [OutboxItem] = []
    @Published var isConfigured = false
    @Published var isFetching = false
    @Published var sectionResults: [UUID: [SectionTodo]] = [:]

    private let syncManager: TodoSyncManager
    private var profileViewModel: ProfileViewModel?
    private var modelContext: ModelContext?

    // TodosHome's SwiftData queries feed these source snapshots into the view
    // model. Derived published lists are rebuilt whenever a snapshot changes.
    private var allTodos: [TodoItem] = []
    private var outboxItems: [OutboxItem] = []
    private var relevantOutboxItems: [OutboxItem] = []

    // Remembering prior outbox states lets the view model notice the exact
    // transition from queued to synced and pull the new Roam TODO into cache.
    private var outboxStatusSnapshot: [UUID: Int] = [:]
    private var refreshRetryTask: Task<Void, Never>?

    // TodosHome supplies its current sections so post-sync retries can repeat
    // either the sectioned refresh or the single flat-list refresh.
    var configuredSections: [TodoSection] = []

    // MARK: - Setup and Inputs

    init() {
        // A StateObject is created before TodosHome can provide its environment
        // ModelContext. Start with the shared store, then replace this context
        // in configure() as soon as the screen appears.
        let container = SharedModelContainer()
        let context = ModelContext(container)
        self.syncManager = TodoSyncManager(modelContext: context)
    }

    func configure(profileViewModel: ProfileViewModel, modelContext: ModelContext) {
        self.profileViewModel = profileViewModel
        self.modelContext = modelContext
        syncManager.modelContext = modelContext

        updateConfiguration()
        rebuildFilteredTodos()
        rebuildPendingOutbox()
        updateBadges()
    }

    func updateTodos(_ todos: [TodoItem]) {
        allTodos = todos
        rebuildFilteredTodos()
        updateBadges()
    }

    func updateOutbox(_ items: [OutboxItem]) {
        outboxItems = items
        rebuildPendingOutbox()
        handleOutboxStatusChange()
    }

    func handleProfileChange() {
        updateConfiguration()
        rebuildFilteredTodos()
        rebuildPendingOutbox()
        updateBadges()
    }

    func handleFilterChange() {
        handleProfileChange()
        Task {
            await refreshTodos()
        }
    }

    // MARK: - Roam Refresh

    // The Backend API token stays in Keychain rather than published view state,
    // so each refresh asks CredentialsManager for the current value.
    func refreshTodos(skipCleanup: Bool = false) async {
        guard isConfigured,
              let profileViewModel,
              let graphName = profileViewModel.graphName else {
            return
        }

        guard let apiToken = await CredentialsManager.shared.primaryBackendToken else {
            return
        }

        isFetching = true
        lastError = nil
        defer { isFetching = false }

        do {
            try await syncManager.fetchTodos(
                graphName: graphName,
                tagFilter: profileViewModel.todosTagFilter,
                excludeFilter: profileViewModel.todosExcludeTagFilter,
                timePeriodDays: profileViewModel.todosTimePeriod,
                apiToken: apiToken,
                skipCleanup: skipCleanup
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    // Each enabled section has its own Roam query. Merge every response into
    // the shared SwiftData cache, then rebuild all section lists from that cache.
    func refreshAllSections(sections: [TodoSection], skipCleanup: Bool = false) async {
        guard isConfigured,
              let profileViewModel,
              let graphName = profileViewModel.graphName else { return }

        guard let apiToken = await CredentialsManager.shared.primaryBackendToken else { return }

        isFetching = true
        defer { isFetching = false }

        let enabledSections = sections.filter(\.isEnabled)
        guard !enabledSections.isEmpty else { return }

        // Cleanup needs the union from every section because one TODO can match
        // several section queries but should exist only once in SwiftData.
        var allFetchedUids = Set<String>()

        for section in enabledSections {
            let query = syncManager.buildQuery(
                tagFilter: section.includeTagFilter,
                excludeFilter: section.excludeTagFilter,
                timePeriodDays: section.timePeriodDays
            )

            do {
                let api = RoamBackendAPI(apiToken: apiToken)
                let results = try await api.executeQuery(graphName: graphName, query: query)

                try Task.checkCancellation()

                let fetchedTodos = syncManager.parseTodoResults(results)
                try syncManager.mergeLocalTodos(fetchedTodos)
                allFetchedUids.formUnion(fetchedTodos.map(\.roamBlockUid))
            } catch is CancellationError {
                return
            } catch {
                lastError = error.localizedDescription
            }
        }

        // FIXME: Skip cleanup if any section query fails; a partial UID set can delete valid cached TODOs.
        // https://github.com/plushgraffiti/capturr-ios/issues/30
        if !skipCleanup {
            try? syncManager.cleanupOrphanedTodos(validUids: allFetchedUids)
        }

        // Rebuild from whatever is now in the durable cache so the screen does
        // not depend on holding the network responses in memory.
        let allTodos = (try? syncManager.modelContext.fetch(FetchDescriptor<TodoItem>())) ?? []
        buildSectionResultsFromCache(allTodos: allTodos, sections: sections)
    }

    // MARK: - Section Results

    // Reapply each section's include, exclude, and age rules locally. This is
    // what makes the sectioned screen usable from the SwiftData cache offline.
    @discardableResult
    func buildSectionResultsFromCache(allTodos: [TodoItem], sections: [TodoSection]) -> [UUID: [SectionTodo]] {
        var sectionTodosBySectionID: [UUID: [SectionTodo]] = [:]

        for section in sections where section.isEnabled {
            let includeTags = section.includeTagFilter
                .flatMap { TodoSyncManager.parseTagsFromInput($0) } ?? []
            let excludeTags = section.excludeTagFilter
                .flatMap { TodoSyncManager.parseTagsFromInput($0) } ?? []

            var matchingTodos = allTodos.filter { todo in
                let includeMatch = includeTags.isEmpty ||
                    includeTags.contains { todo.originalString.contains($0) }
                let excludeMatch = excludeTags.isEmpty ||
                    !excludeTags.contains { todo.originalString.contains($0) }
                let timeMatch: Bool
                if section.timePeriodDays > 0 {
                    let cutoff = Calendar.current.date(
                        byAdding: .day, value: -section.timePeriodDays, to: Date()
                    ) ?? .distantPast
                    timeMatch = todo.updatedAt >= cutoff
                } else {
                    timeMatch = true
                }
                return includeMatch && excludeMatch && timeMatch
            }

            matchingTodos.sort { $0.updatedAt > $1.updatedAt }

            sectionTodosBySectionID[section.id] = matchingTodos.map {
                SectionTodo(id: "\(section.id)_\($0.roamBlockUid)", todo: $0)
            }
        }

        sectionResults = sectionTodosBySectionID
        updateBadgesFromSections()
        return sectionTodosBySectionID
    }

    // MARK: - New TODO Creation

    // Remember where the inline editor was opened so submitNewTodo() can append
    // the section's tags. Nil means the editor belongs to the flat list.
    private var newTodoSectionTags: String?
    private var newTodoSectionId: UUID?

    // Open a blank inline editor and remember its optional destination section.
    func beginNewTodo(sectionId: UUID? = nil, sectionTags: String? = nil) {
        guard !isAddingTodo else { return }
        newTodoText = ""
        newTodoSectionId = sectionId
        newTodoSectionTags = sectionTags
        isAddingTodo = true
    }

    func cancelNewTodo() {
        newTodoText = ""
        newTodoSectionId = nil
        newTodoSectionTags = nil
        isAddingTodo = false
    }

    func submitNewTodo() {
        let trimmed = newTodoText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelNewTodo()
            return
        }

        guard let modelContext else { return }

        // A section-created TODO receives that section's include tags. A flat
        // TODO uses the profile-wide filter so it appears in the current list.
        let includeTags: String?
        if newTodoSectionId != nil {
            includeTags = newTodoSectionTags?.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            includeTags = profileViewModel?.todosTagFilter?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let content: String
        if let includeTags, !includeTags.isEmpty {
            content = "\(trimmed) \(includeTags)"
        } else {
            content = trimmed
        }

        let item = OutboxItem(content: content, type: .todo)
        modelContext.insert(item)
        do {
            try modelContext.save()
            BackgroundSyncScheduler.scheduleAfterEnqueue(itemIDs: [item.id])
            cancelNewTodo()
        } catch {
            modelContext.delete(item)
            lastError = "Failed to save TODO."
        }
    }

    // MARK: - Configuration and Filtering

    // Xcode previews have no configured Keychain token but still need to render
    // the configured TODO screen using their in-memory sample data.
    static var isPreviewMode = false

    private func updateConfiguration() {
        guard profileViewModel != nil else {
            isConfigured = false
            return
        }
        isConfigured = Self.isPreviewMode || CredentialsManager.shared.hasPrimaryBackendToken
    }

    private func rebuildFilteredTodos() {
        guard let profileViewModel else {
            filteredTodos = []
            return
        }

        let todos = profileViewModel.todosShowCompleted
            ? allTodos
            : allTodos.filter { !$0.isCompleted }

        filteredTodos = todos.sorted {
            if $0.isCompleted == $1.isCompleted {
                return $0.updatedAt > $1.updatedAt
            }
            // Keep incomplete work above completed work regardless of date.
            return !$0.isCompleted
        }
    }

    private func rebuildPendingOutbox() {
        guard let profileViewModel else {
            relevantOutboxItems = []
            pendingOutboxItems = []
            return
        }

        if !configuredSections.isEmpty {
            // TodosHome assigns section membership for pending rows, so retain
            // every newly created TODO here when the sectioned layout is active.
            relevantOutboxItems = outboxItems.filter { item in
                item.type == .todo && item.action == nil
            }
        } else {
            // In the flat layout, mirror the profile's include filter so queued
            // TODOs appear beside the fetched TODOs they will eventually join.
            let includeTagsRaw = profileViewModel.todosTagFilter?.trimmingCharacters(in: .whitespacesAndNewlines)
            relevantOutboxItems = outboxItems.filter { item in
                guard item.type == .todo, item.action == nil else { return false }
                if let includeTagsRaw, !includeTagsRaw.isEmpty {
                    let parsed = TodoSyncManager.parseTagsFromInput(includeTagsRaw)
                    return parsed.isEmpty || parsed.contains { item.content.contains($0) }
                }
                return true
            }
        }

        pendingOutboxItems = relevantOutboxItems.filter {
            SyncStatus(rawValue: $0.status) != .success
        }
    }

    // MARK: - Badge Updates

    private func updateBadges() {
        guard let profileViewModel else { return }

        // A TODO can appear in several sections, so sectioned mode needs the
        // UID-deduplicating counter rather than a simple list count.
        if !configuredSections.isEmpty {
            updateBadgesFromSections()
            return
        }

        let incompleteCount: Int
        if profileViewModel.todosShowCompleted {
            incompleteCount = filteredTodos.filter { !$0.isCompleted }.count
        } else {
            incompleteCount = filteredTodos.count
        }
        let count = min(incompleteCount, 99)

        profileViewModel.todosBadgeCount = count

        guard profileViewModel.todosBadgeEnabled && profileViewModel.todosEnabled else {
            Task {
                try? await UNUserNotificationCenter.current().setBadgeCount(0)
            }
            return
        }

        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(count)
        }
    }

    // Count each incomplete Roam block once even when several section filters
    // place that same TODO on screen.
    private func updateBadgesFromSections() {
        guard let profileViewModel else { return }

        var countedTodoUIDs = Set<String>()
        var incompleteCount = 0

        for (_, todos) in sectionResults {
            for sectionTodo in todos where !sectionTodo.todo.isCompleted {
                if countedTodoUIDs.insert(sectionTodo.todo.roamBlockUid).inserted {
                    incompleteCount += 1
                }
            }
        }

        let count = min(incompleteCount, 99)
        profileViewModel.todosBadgeCount = count

        guard profileViewModel.todosBadgeEnabled && profileViewModel.todosEnabled else {
            Task {
                try? await UNUserNotificationCenter.current().setBadgeCount(0)
            }
            return
        }

        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(count)
        }
    }

    // MARK: - Post-Sync Refresh

    private func handleOutboxStatusChange() {
        // Compare snapshots instead of reacting to every SwiftData update. Only
        // a newly successful send needs a follow-up pull from Roam.
        let newSnapshot = Dictionary(uniqueKeysWithValues: relevantOutboxItems.map { ($0.id, $0.status) })
        let oldSnapshot = outboxStatusSnapshot
        outboxStatusSnapshot = newSnapshot

        guard isConfigured else { return }

        let successValue = SyncStatus.success.rawValue
        let shouldRefresh = newSnapshot.contains { id, newStatus in
            if let oldStatus = oldSnapshot[id] {
                return oldStatus != successValue && newStatus == successValue
            }
            return false
        }

        if shouldRefresh {
            scheduleRefreshRetries()
        }
    }

    private func scheduleRefreshRetries() {
        // Roam's query API may not expose a just-sent TODO immediately. Retry a
        // few times; early pulls merge only so stale query results cannot delete
        // cached TODOs, while the final pull performs normal authoritative cleanup.
        refreshRetryTask?.cancel()
        let sections = configuredSections
        refreshRetryTask = Task {
            if !sections.isEmpty {
                await refreshAllSections(sections: sections, skipCleanup: true)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await refreshAllSections(sections: sections, skipCleanup: true)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await refreshAllSections(sections: sections)
            } else {
                await refreshTodos(skipCleanup: true)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await refreshTodos(skipCleanup: true)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await refreshTodos()
            }
        }
    }
}
