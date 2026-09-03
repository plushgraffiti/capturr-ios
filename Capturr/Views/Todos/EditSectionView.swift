/// This view provides the form for creating or editing a TODO section.
/// `TodosHome` opens it for the first section, while `ManageSectionsView` opens
/// it for later additions and edits; the form saves `TodoSection` in SwiftData.

import SwiftUI
import SwiftData

struct EditSectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var profileViewModel: ProfileViewModel

    // MARK: - State

    let section: TodoSection?
    let isCreatingSection: Bool
    var onFirstSectionCreated: (() -> Void)? = nil

    @State private var sectionName: String = ""
    @State private var includeTagFilter: String = ""
    @State private var excludeTagFilter: String = ""
    @State private var timePeriodDays: Int = 30
    @State private var isShowingDeleteConfirmation = false

    var isDefaultSection: Bool {
        section?.isDefault ?? false
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    headerView
                    nameField
                    includeTagsField
                    excludeTagsField
                    timePeriodField
                }
                .padding()
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if !isCreatingSection && !isDefaultSection {
                    deleteSectionCard
                }

                Spacer()
            }
            .padding()
        }
        .background(Color(.secondarySystemBackground))
        .navigationTitle(isCreatingSection ? "New Section" : "Edit Section")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveSection()
                }
                .disabled(sectionName.isEmpty)
            }
            // The first-section form is presented as a sheet, so it needs an
            // explicit way to close without saving.
            if onFirstSectionCreated != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear { loadSectionData() }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 80, height: 80)
                Image(systemName: "list.bullet.below.rectangle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 45, height: 50)
                    .foregroundColor(.white)
            }
            .padding(.top)

            Text(isCreatingSection ? "New Section" : "Edit Section")
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)

            Text("Configure filters to control which TODOs appear in this section")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    // MARK: - Fields

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Section Name")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("e.g. Work, Personal", text: $sectionName)
                .font(.body)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal)
        .padding(.top, 15)
    }

    private var includeTagsField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Include Tags")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("Example: #urgent", text: $includeTagFilter)
                .font(.body)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal)
        .padding(.bottom, 5)
    }

    private var excludeTagsField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exclude Tags")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("Example: [[someday]]", text: $excludeTagFilter)
                .font(.body)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal)
        .padding(.bottom, 5)
    }

    private var timePeriodField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time Period")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("Time Period", selection: $timePeriodDays) {
                Text("30 days").tag(30)
                Text("60 days").tag(60)
                Text("90 days").tag(90)
                Text("All time").tag(0)
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal)
        .padding(.bottom)
    }

    // MARK: - Delete

    private var deleteSectionCard: some View {
        Button(role: .destructive) {
            isShowingDeleteConfirmation = true
        } label: {
            HStack {
                Text("Delete Section")
            }
        }
        .alert("Delete Section", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                performDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this section? This cannot be undone.")
        }
    }

    // MARK: - Actions

    private func loadSectionData() {
        // Copy the model into temporary form fields so Cancel can discard edits.
        guard let section = section else { return }
        sectionName = section.name
        includeTagFilter = section.includeTagFilter ?? ""
        excludeTagFilter = section.excludeTagFilter ?? ""
        timePeriodDays = section.timePeriodDays
    }

    private func saveSection() {
        if let section = section {
            // Editing changes the existing SwiftData model in place.
            section.name = sectionName
            section.includeTagFilter = includeTagFilter.isEmpty ? nil : includeTagFilter
            section.excludeTagFilter = excludeTagFilter.isEmpty ? nil : excludeTagFilter
            section.timePeriodDays = timePeriodDays
            section.updatedAt = Date()
        } else {
            // On the first custom section, TodosHome preserves the old
            // flat-list filters as a default catch-all section.
            onFirstSectionCreated?()

            let graphName = profileViewModel.graphName ?? ""
            // New sections are placed after the current highest order value.
            let newSection = TodoSection(
                graphName: graphName,
                name: sectionName,
                order: getNextOrder(),
                includeTagFilter: includeTagFilter.isEmpty ? nil : includeTagFilter,
                excludeTagFilter: excludeTagFilter.isEmpty ? nil : excludeTagFilter,
                timePeriodDays: timePeriodDays
            )
            modelContext.insert(newSection)
        }

        try? modelContext.save()
        dismiss()
    }

    private func performDelete() {
        // Default sections are protected because they catch unmatched TODOs.
        guard let section = section, !section.isDefault else { return }

        modelContext.delete(section)
        try? modelContext.save()
        dismiss()
    }

    private func getNextOrder() -> Int {
        // Fetch the last position so a newly created section can follow it.
        let descriptor = FetchDescriptor<TodoSection>(
            sortBy: [SortDescriptor(\.order, order: .reverse)]
        )
        let sections = try? modelContext.fetch(descriptor)
        return (sections?.first?.order ?? -1) + 1
    }

}

// MARK: - Previews

#Preview("New Section") {
    NavigationStack {
        EditSectionView(section: nil, isCreatingSection: true)
    }
    .modelContainer(for: TodoSection.self, inMemory: true)
    .environmentObject(ProfileViewModel())
}
#Preview("Edit Section") {
    NavigationStack {
        EditSectionView(
            section: TodoSection(
                graphName: "my-graph",
                name: "Work",
                order: 0,
                includeTagFilter: "[[work]]",
                timePeriodDays: 30
            ),
            isCreatingSection: false
        )
    }
    .modelContainer(for: TodoSection.self, inMemory: true)
    .environmentObject(ProfileViewModel())
}
