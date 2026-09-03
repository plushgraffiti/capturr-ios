/// This model stores one named TODO section and the filters that decide what it contains.
/// `EditSectionView` creates and updates these SwiftData records, `ManageSectionsView`
/// reorders them, and `TodosViewModel` uses each enabled section for both Roam queries and
/// offline filtering. `TodosHome` also creates a protected default section for old filters.

import Foundation
import SwiftData

@Model
final class TodoSection {
    var id: UUID
    var graphName: String
    var name: String

    // The order and collapsed state keep the TODO screen arranged the same way across launches.
    var order: Int
    var isCollapsed: Bool
    var isEnabled: Bool
    var isDefault: Bool           // The preserved fallback section cannot be deleted.

    // Each enabled section uses these rules for its Roam query and its cached offline results.
    var includeTagFilter: String?
    var excludeTagFilter: String?
    var timePeriodDays: Int       // Zero means all time.

    var createdAt: Date
    var updatedAt: Date

    init(
        graphName: String,
        name: String,
        order: Int,
        isDefault: Bool = false,
        includeTagFilter: String? = nil,
        excludeTagFilter: String? = nil,
        timePeriodDays: Int = 30
    ) {
        self.id = UUID()
        self.graphName = graphName
        self.name = name
        self.order = order
        self.isDefault = isDefault
        self.includeTagFilter = includeTagFilter
        self.excludeTagFilter = excludeTagFilter
        self.timePeriodDays = timePeriodDays
        self.isCollapsed = false
        self.isEnabled = true
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
