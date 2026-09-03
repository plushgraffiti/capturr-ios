/// This test suite checks TODO tag parsing, Roam queries, result parsing, and local cache updates.
/// Swift Testing runs each `@Test`; actor-isolated cases create `TodoSyncManager` with an
/// `InMemoryModelContainer`. The cases protect the same SwiftData reconciliation used by
/// `TodosViewModel` and the app's background refresh work.

import Foundation
import SwiftData
import Testing
@testable import Capturr

@MainActor
struct TodoSyncManagerTests {
    // MARK: - Tag Parsing

    @Test
    func parsesPageReferencesAndHashtags() {
        let tags = TodoSyncManager.parseTagsFromInput(
            "plain text [[project alpha]] #urgent [[Area 51]] #waiting"
        )

        #expect(tags == ["[[project alpha]]", "#urgent", "[[Area 51]]", "#waiting"])
    }

    @Test
    func ignoresIncompleteAndEmptyTags() {
        let tags = TodoSyncManager.parseTagsFromInput("[[unfinished # #valid")

        #expect(tags == ["#valid"])
    }

    // MARK: - Result Parsing

    @Test
    func parsesTodoAndDoneResultsAndSkipsMalformedRows() throws {
        let container = try InMemoryModelContainer.make()
        let manager = TodoSyncManager(modelContext: ModelContext(container))
        let timestampMilliseconds: Int64 = 1_700_000_000_000

        let todos = manager.parseTodoResults([
            ["todo-1", "{{[[TODO]]}} Buy milk", timestampMilliseconds, "Daily Notes"],
            ["done-1", "{{[[DONE]]}} Shipped", timestampMilliseconds + 1_000, "Projects"],
            ["missing-fields"],
            ["wrong-time", "{{[[TODO]]}} Invalid", "not-a-timestamp", "Page"],
        ])

        #expect(todos.count == 2)
        #expect(todos[0].roamBlockUid == "todo-1")
        #expect(todos[0].text == "Buy milk")
        #expect(!todos[0].isCompleted)
        #expect(todos[0].parentPageTitle == "Daily Notes")
        #expect(todos[0].updatedAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(todos[1].text == "Shipped")
        #expect(todos[1].isCompleted)
        #expect(todos[1].parentPageTitle == "Projects")
    }

    @Test
    func parsesResultsDecodedFromJSON() throws {
        let container = try InMemoryModelContainer.make()
        let manager = TodoSyncManager(modelContext: ModelContext(container))

        // The production path hands parseTodoResults values decoded by
        // JSONSerialization (NSNumber timestamps), not Swift-native Int64s —
        // exercise that bridging explicitly.
        let json = """
        [["todo-1", "{{[[TODO]]}} Buy milk", 1700000000000, "Daily Notes"]]
        """
        let results = try #require(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[Any]]
        )

        let todos = manager.parseTodoResults(results)

        #expect(todos.count == 1)
        #expect(todos.first?.roamBlockUid == "todo-1")
        #expect(todos.first?.text == "Buy milk")
        #expect(todos.first?.updatedAt == Date(timeIntervalSince1970: 1_700_000_000))
    }

    // MARK: - Query Building

    @Test
    func queryContainsRequestedIncludeAndExcludeFilters() throws {
        let container = try InMemoryModelContainer.make()
        let manager = TodoSyncManager(modelContext: ModelContext(container))

        let query = manager.buildQuery(
            tagFilter: "[[project alpha]] #urgent",
            excludeFilter: "#waiting [[someday]]",
            timePeriodDays: 0
        )

        #expect(query.contains("{{[[TODO]]}}"))
        #expect(query.contains("{{[[DONE]]}}"))
        #expect(query.contains("(clojure.string/includes? ?block-str \"[[project alpha]]\")"))
        #expect(query.contains("(clojure.string/includes? ?block-str \"#urgent\")"))
        #expect(query.contains("(not [(clojure.string/includes? ?block-str \"#waiting\")])"))
        #expect(query.contains("(not [(clojure.string/includes? ?block-str \"[[someday]]\")])"))
        #expect(!query.contains("[(> ?edit-time"))
    }

    @Test
    func queryIncludesEditTimeCutoffForBoundedTimePeriod() throws {
        let container = try InMemoryModelContainer.make()
        let manager = TodoSyncManager(modelContext: ModelContext(container))

        let query = manager.buildQuery(
            tagFilter: nil,
            excludeFilter: nil,
            timePeriodDays: 30
        )

        // The cutoff is computed from the current date, so assert the clause's
        // shape rather than an exact value: a millisecond timestamp after
        // 2020-01-01 (1577836800000).
        let match = try #require(
            query.firstMatch(of: #/\[\(> \?edit-time (\d+)\)\]/#)
        )
        let cutoffMilliseconds = try #require(Int64(match.1))
        #expect(cutoffMilliseconds > 1_577_836_800_000)
    }

    // MARK: - Cache Reconciliation

    @Test
    func mergeInsertsAndUpdatesWithoutDuplicating() throws {
        let container = try InMemoryModelContainer.make()
        let context = ModelContext(container)
        let manager = TodoSyncManager(modelContext: context)
        let existing = TodoItem(
            roamBlockUid: "same-uid",
            text: "Old",
            originalString: "{{[[TODO]]}} Old"
        )
        context.insert(existing)
        try context.save()
        let originalID = existing.id

        let updated = TodoItem(
            roamBlockUid: "same-uid",
            text: "New",
            originalString: "{{[[DONE]]}} New",
            isCompleted: true
        )
        updated.parentPageTitle = "Updated page"
        updated.updatedAt = Date(timeIntervalSince1970: 2_000)

        let inserted = TodoItem(
            roamBlockUid: "new-uid",
            text: "New item",
            originalString: "{{[[TODO]]}} New item"
        )

        try manager.mergeLocalTodos([updated, inserted])

        let storedTodos = try context.fetch(FetchDescriptor<TodoItem>())
        #expect(storedTodos.count == 2)

        let storedUpdated = try #require(
            storedTodos.first { $0.roamBlockUid == "same-uid" }
        )
        #expect(storedUpdated.id == originalID)
        #expect(storedUpdated.text == "New")
        #expect(storedUpdated.isCompleted)
        #expect(storedUpdated.parentPageTitle == "Updated page")
        #expect(storedUpdated.updatedAt == Date(timeIntervalSince1970: 2_000))
        #expect(storedTodos.contains { $0.roamBlockUid == "new-uid" })
    }

    @Test
    func mergeUpdatesPageAndDateIndependentlyWhenOriginalStringUnchanged() throws {
        let container = try InMemoryModelContainer.make()
        let context = ModelContext(container)
        let manager = TodoSyncManager(modelContext: context)
        let existing = TodoItem(
            roamBlockUid: "same-uid",
            text: "Old",
            originalString: "{{[[TODO]]}} Old"
        )
        existing.parentPageTitle = "Original page"
        existing.updatedAt = Date(timeIntervalSince1970: 1_000)
        context.insert(existing)
        try context.save()

        // Same originalString, so text/isCompleted are left alone — but the
        // block may have moved pages or been re-edited, and merge should pick
        // those up independently.
        let fetched = TodoItem(
            roamBlockUid: "same-uid",
            text: "Old",
            originalString: "{{[[TODO]]}} Old"
        )
        fetched.parentPageTitle = "Moved page"
        fetched.updatedAt = Date(timeIntervalSince1970: 2_000)

        try manager.mergeLocalTodos([fetched])

        let storedTodos = try context.fetch(FetchDescriptor<TodoItem>())
        #expect(storedTodos.count == 1)
        let merged = try #require(storedTodos.first)
        #expect(merged.text == "Old")
        #expect(!merged.isCompleted)
        #expect(merged.parentPageTitle == "Moved page")
        #expect(merged.updatedAt == Date(timeIntervalSince1970: 2_000))
    }

    @Test
    func cleanupRemovesOnlyOrphanedTodos() throws {
        let container = try InMemoryModelContainer.make()
        let context = ModelContext(container)
        let manager = TodoSyncManager(modelContext: context)

        context.insert(
            TodoItem(
                roamBlockUid: "keep",
                text: "Keep",
                originalString: "{{[[TODO]]}} Keep"
            )
        )
        context.insert(
            TodoItem(
                roamBlockUid: "remove",
                text: "Remove",
                originalString: "{{[[TODO]]}} Remove"
            )
        )
        try context.save()

        try manager.cleanupOrphanedTodos(validUids: ["keep"])

        let storedTodos = try context.fetch(FetchDescriptor<TodoItem>())
        #expect(storedTodos.map(\.roamBlockUid) == ["keep"])
    }
}
