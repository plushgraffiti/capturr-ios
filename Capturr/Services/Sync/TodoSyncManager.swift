/// This manager pulls filtered TODO blocks from Roam into the local SwiftData store.
/// `TodosViewModel` asks it to refresh using the person's graph and filter settings.
/// It builds the Backend API query, turns rows into `TodoItem` models, and reconciles
/// the local list; edits going back to Roam are queued separately for `SyncWorker`.

import Foundation
import SwiftData
import OSLog

private let logger = Logger(category: "TodoSyncManager")

@MainActor
class TodoSyncManager: ObservableObject {
    @Published var isFetching: Bool = false
    @Published var lastError: String?
    @Published var lastFetchDate: Date?

    var modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // Pulls one filtered snapshot from Roam and merges it into SwiftData.
    // A caller doing several section fetches can defer orphan cleanup until the
    // combined valid-UID set is known.
    func fetchTodos(graphName: String, tagFilter: String?, excludeFilter: String?, timePeriodDays: Int, apiToken: String, skipCleanup: Bool = false) async throws {
        guard !isFetching else {
            logger.warning("Fetch already in progress, skipping")
            return
        }

        isFetching = true
        lastError = nil
        defer { isFetching = false }

        logger.info("Fetching TODOs from graph: \(graphName)")

        // Build query from user's filter settings
        let query = buildQuery(tagFilter: tagFilter, excludeFilter: excludeFilter, timePeriodDays: timePeriodDays)

        let api = RoamBackendAPI(apiToken: apiToken)

        do {
            // Execute generated query
            let results = try await api.executeQuery(graphName: graphName, query: query)

            // Parse results into TodoItem models
            let fetchedTodos = parseTodoResults(results)

            logger.info("Parsed \(fetchedTodos.count) TODOs from query results")

            // Merge into local database, then clean up orphans
            try mergeLocalTodos(fetchedTodos)
            if !skipCleanup {
                let validUids = Set(fetchedTodos.map(\.roamBlockUid))
                try cleanupOrphanedTodos(validUids: validUids)
            }

            lastFetchDate = Date()
            logger.info("Successfully fetched and updated TODOs")

        } catch let error as RoamBackendAPIError {
            logger.error("Backend API error: \(error.localizedDescription)")
            lastError = error.localizedDescription
            throw error
        } catch {
            logger.error("Unexpected error: \(error.localizedDescription)")
            lastError = error.localizedDescription
            throw error
        }
    }

    // Parse query results into TodoItem objects
    // Expected result format: [[block-uid, block-string, edit-time, page-title], ...]
    func parseTodoResults(_ results: [[Any]]) -> [TodoItem] {
        var todos: [TodoItem] = []

        for result in results {
            // Expect 4 elements: uid, string, edit-time, and page-title
            guard result.count >= 4,
                  let uid = result[0] as? String,
                  let string = result[1] as? String,
                  let editTimeMs = result[2] as? Int64,
                  let pageTitle = result[3] as? String else {
                logger.warning("Skipping result with invalid format: \(result)")
                continue
            }

            // Convert edit time from milliseconds to Date
            let editTime = Date(timeIntervalSince1970: TimeInterval(editTimeMs) / 1000.0)

            // Determine if TODO or DONE based on string content
            let isCompleted = string.contains("{{[[DONE]]}}")

            // Clean up string (remove TODO/DONE markers for display)
            let cleanText = string
                .replacingOccurrences(of: "{{[[TODO]]}}", with: "")
                .replacingOccurrences(of: "{{[[DONE]]}}", with: "")
                .trimmingCharacters(in: .whitespaces)

            // Create TodoItem with both cleaned text and original string
            let todo = TodoItem(
                roamBlockUid: uid,
                text: cleanText,
                originalString: string,
                isCompleted: isCompleted
            )
            // Set updatedAt to Roam's edit time for proper sorting
            todo.updatedAt = editTime
            // Set parent page title
            todo.parentPageTitle = pageTitle

            todos.append(todo)
        }

        return todos
    }

    // Merge fetched TODOs into local SwiftData (upsert only, no deletes)
    func mergeLocalTodos(_ fetchedTodos: [TodoItem]) throws {
        let existing = try modelContext.fetch(FetchDescriptor<TodoItem>())
        var existingMap: [String: TodoItem] = [:]
        for todo in existing { existingMap[todo.roamBlockUid] = todo }

        for fetched in fetchedTodos {
            if let existing = existingMap[fetched.roamBlockUid] {
                if existing.originalString != fetched.originalString {
                    existing.text = fetched.text
                    existing.originalString = fetched.originalString
                    existing.isCompleted = fetched.isCompleted
                }
                if existing.parentPageTitle != fetched.parentPageTitle {
                    existing.parentPageTitle = fetched.parentPageTitle
                }
                if existing.updatedAt != fetched.updatedAt {
                    existing.updatedAt = fetched.updatedAt
                }
            } else {
                modelContext.insert(fetched)
            }
        }
        try modelContext.save()
    }

    // Remove TODOs from SwiftData that aren't in the valid set
    func cleanupOrphanedTodos(validUids: Set<String>) throws {
        let all = try modelContext.fetch(FetchDescriptor<TodoItem>())
        for todo in all where !validUids.contains(todo.roamBlockUid) {
            modelContext.delete(todo)
        }
        try modelContext.save()
    }

    // Clear all local TODOs (useful for logout or disabling feature)
    func clearAllTodos() throws {
        let fetchDescriptor = FetchDescriptor<TodoItem>()
        let allTodos = try modelContext.fetch(fetchDescriptor)

        for todo in allTodos {
            modelContext.delete(todo)
        }

        try modelContext.save()
        logger.info("Cleared all local TODOs")
    }

    // MARK: - Query Builder

    // Builds the Datalog query from optional include tags, exclude tags, and age.
    // A zero-day period deliberately leaves out the edit-time cutoff.
    func buildQuery(tagFilter: String?, excludeFilter: String?, timePeriodDays: Int) -> String {
        var whereClauses: [String] = [
            "[?b :block/uid ?block-uid]",
            "[?b :block/string ?block-str]",
            "[?b :edit/time ?edit-time]",
            "[?b :block/page ?p]",
            "[?p :node/title ?page-title]",
            "(or-join [?b ?block-str]",
            "  (and",
            "    [?todo-page :node/title \"TODO\"]",
            "    [?b :block/refs ?todo-page]",
            "    [(clojure.string/includes? ?block-str \"{{[[TODO]]}}\")])",
            "  (and",
            "    [?done-page :node/title \"DONE\"]",
            "    [?b :block/refs ?done-page]",
            "    [(clojure.string/includes? ?block-str \"{{[[DONE]]}}\")]))"
        ]

        // Add time filter if not "all time"
        if timePeriodDays > 0 {
            let cutoffTimestamp = calculateCutoffTimestamp(daysAgo: timePeriodDays)
            whereClauses.append("[(> ?edit-time \(cutoffTimestamp))]")
        }

        // Add INCLUDE tag filters (OR logic - any tag matches)
        if let tags = tagFilter, !tags.isEmpty {
            let individualTags = Self.parseTagsFromInput(tags)
            if !individualTags.isEmpty {
                // Build OR clause for include tags
                whereClauses.append("(or")
                for tag in individualTags {
                    let escapedTag = tag.replacingOccurrences(of: "\"", with: "\\\"")
                    whereClauses.append("  [(clojure.string/includes? ?block-str \"\(escapedTag)\")]")
                }
                whereClauses.append(")")
            }
        }

        // Add EXCLUDE tag filters (NOT + OR logic - none of these tags can match)
        if let excludeTags = excludeFilter, !excludeTags.isEmpty {
            let individualExcludeTags = Self.parseTagsFromInput(excludeTags)
            for tag in individualExcludeTags {
                let escapedTag = tag.replacingOccurrences(of: "\"", with: "\\\"")
                whereClauses.append("(not [(clojure.string/includes? ?block-str \"\(escapedTag)\")])")
            }
        }

        let whereClause = whereClauses.joined(separator: "\n ")

        return """
        [:find ?block-uid ?block-str ?edit-time ?page-title
         :where
         \(whereClause)]
        """
    }

    // Splits the settings field without breaking spaces inside [[page refs]].
    // Hashtags stop at whitespace, and every returned tag keeps the spelling
    // needed for the generated Datalog rule.
    static func parseTagsFromInput(_ input: String) -> [String] {
        var tags: [String] = []
        var i = input.startIndex

        while i < input.endIndex {
            // Skip whitespace
            if input[i].isWhitespace {
                i = input.index(after: i)
                continue
            }

            // Match [[...]] page refs (may contain spaces)
            if input[i...].hasPrefix("[[") {
                if let closeRange = input.range(of: "]]", range: i..<input.endIndex) {
                    let end = closeRange.upperBound
                    tags.append(String(input[i..<end]))
                    i = end
                    continue
                }
            }

            // Match #hashtags (no spaces allowed)
            if input[i] == "#" {
                let start = i
                i = input.index(after: i)
                while i < input.endIndex && !input[i].isWhitespace {
                    i = input.index(after: i)
                }
                let tag = String(input[start..<i])
                if tag.count > 1 { tags.append(tag) }
                continue
            }

            // Skip any other non-whitespace characters
            i = input.index(after: i)
        }

        return tags
    }

    // Roam stores edit times as Unix milliseconds, so the day-based setting is
    // converted at the start of the cutoff day. Returning zero safely disables
    // the filter if Calendar cannot produce that date.
    private func calculateCutoffTimestamp(daysAgo: Int) -> Int64 {
        let now = Date()
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -daysAgo, to: now) else {
            return 0
        }
        // Roam uses milliseconds since epoch
        return Int64(cutoffDate.timeIntervalSince1970 * 1000)
    }
}
