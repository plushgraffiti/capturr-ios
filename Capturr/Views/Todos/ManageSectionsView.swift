/// This view is the section-organizing screen opened from `TodosHome`. It
/// lists saved `TodoSection` filters, opens `EditSectionView` to add or edit
/// one, and saves a new order when the user drags the rows.

import SwiftUI
import SwiftData

struct ManageSectionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TodoSection.order) var sections: [TodoSection]

    var body: some View {
        List {
            ForEach(sections) { section in
                NavigationLink {
                    EditSectionView(section: section, isCreatingSection: false)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.name)
                            .font(.body.weight(.medium))

                        if section.timePeriodDays > 0 {
                            Text("\(section.timePeriodDays) days")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("All time")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .onMove(perform: moveSection)

            Section {
                NavigationLink {
                    EditSectionView(section: nil, isCreatingSection: true)
                } label: {
                    Label("Add Section", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Manage Sections")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
    }

    // Dragging changes the display order, so rewrite every section's stored
    // position to make the same order survive the next launch.
    private func moveSection(from sourceOffsets: IndexSet, to destinationOffset: Int) {
        var orderedSections = sections.sorted { $0.order < $1.order }
        orderedSections.move(fromOffsets: sourceOffsets, toOffset: destinationOffset)
        for (index, section) in orderedSections.enumerated() {
            section.order = index
        }
        try? modelContext.save()
    }
}
