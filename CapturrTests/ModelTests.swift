/// This test suite checks important defaults and conversions on the app's stored models.
/// Swift Testing runs each `@Test`, covering outbox state, profile settings, graph data,
/// and basic SwiftData persistence. Persistence checks use `InMemoryModelContainer`
/// so they never touch the app's on-disk store.

import Foundation
import SwiftData
import Testing
@testable import Capturr

@MainActor
struct ModelTests {
    @Test
    func outboxItemStartsPendingWithExpectedDefaults() {
        let item = OutboxItem(content: "Capture me", type: .todo)

        #expect(item.content == "Capture me")
        #expect(item.type == .todo)
        #expect(item.status == SyncStatus.pending.rawValue)
        #expect(item.sentAt == nil)
        #expect(item.lastError == nil)
        #expect(item.attemptCount == 0)
        #expect(item.targetGraphId == nil)
        #expect(item.transcriptionState == nil)
    }

    @Test
    func profileTimestampSettingsHaveStableDefaultsAndRoundTrip() {
        let profile = UserProfile()

        #expect(profile.timestampPosition == .append)
        #expect(profile.timestampFormatting.isEmpty)

        profile.timestampPosition = .prepend
        profile.timestampFormatting = [.bold, .highlight]

        #expect(profile.timestampPosition == .prepend)
        #expect(profile.timestampFormatting.contains(.bold))
        #expect(profile.timestampFormatting.contains(.highlight))
        #expect(!profile.timestampFormatting.contains(.italic))
    }

    @Test
    func additionalGraphsRoundTripAndCorruptDataDegradesToEmpty() {
        let profile = UserProfile()
        let graphs = [
            AdditionalGraph(id: "work-id", name: "Work"),
            AdditionalGraph(id: "personal-id", name: "Personal"),
        ]

        profile.additionalGraphs = graphs
        #expect(profile.additionalGraphs == graphs)

        profile.additionalGraphsData = Data("not-json".utf8)
        #expect(profile.additionalGraphs.isEmpty)
    }

    @Test
    func modelsPersistInAnIsolatedInMemoryStore() throws {
        let container = try InMemoryModelContainer.make()
        let context = ModelContext(container)
        let item = OutboxItem(content: "Offline capture")
        let profile = UserProfile(id: "test-profile")

        context.insert(item)
        context.insert(profile)
        try context.save()

        let outboxItems = try context.fetch(FetchDescriptor<OutboxItem>())
        let profiles = try context.fetch(FetchDescriptor<UserProfile>())

        #expect(outboxItems.map(\.content) == ["Offline capture"])
        #expect(profiles.map(\.id) == ["test-profile"])
    }
}
