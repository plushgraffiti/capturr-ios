/// This view builds the TODOs tab that `ContentView` places in the main app.
/// It watches SwiftData for fetched TODOs, queued TODO captures, and custom
/// sections, then chooses the appropriate flat, sectioned, loading, or empty
/// screen. `TodosViewModel` prepares the data, while `TodosHomeHandlers`
/// connects changes in the screen and database back to that view model.

import SwiftUI
import SwiftData

struct TodosHome: View {
    // MARK: - State and Data

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var profileViewModel: ProfileViewModel

    // These live queries are the screen's three sources of truth: TODOs already
    // fetched from Roam, new TODOs waiting in the outbox, and section settings.
    @Query(sort: \TodoItem.updatedAt, order: .reverse) var allTodos: [TodoItem]
    @Query(sort: \OutboxItem.createdAt, order: .reverse) var outboxItems: [OutboxItem]
    @Query(sort: \TodoSection.order) var customSections: [TodoSection]

    @StateObject private var viewModel = TodosViewModel()
    @FocusState private var isNewTodoFocused: Bool

    @State private var isShowingSectionManager = false
    @State private var isShowingAddSectionSheet = false

    // Nil means the inline new-TODO editor belongs to the flat list; otherwise
    // the ID keeps the editor attached to the section where it was opened.
    @State private var sectionIDForNewTodo: UUID?

    var hasCustomSections: Bool {
        !customSections.isEmpty
    }

    // SwiftUI restarts the section task when a section's query settings change.
    // Names, ordering, and collapsed state do not change what Roam must fetch.
    private var sectionQueryFingerprint: String {
        customSections.map { section in
            "\(section.id)|\(section.isEnabled)|\(section.includeTagFilter ?? "")|\(section.excludeTagFilter ?? "")|\(section.timePeriodDays)"
        }.joined(separator: ",")
    }

    // MARK: - Screen Layout

    var body: some View {
        NavigationStack {
            content
        }
    }

    private var content: some View {
        // Configuration, layout mode, loading state, and available data decide
        // which single screen the user sees.
        Group {
            if viewModel.isConfigured {
                if hasCustomSections {
                    sectionedListView
                } else if viewModel.filteredTodos.isEmpty && viewModel.pendingOutboxItems.isEmpty && !viewModel.isAddingTodo {
                    if viewModel.isFetching {
                        ProgressView("Fetching TODOs...")
                            .padding()
                    } else if let error = viewModel.lastError {
                        TodoEmptyState(reason: .error(error))
                    } else {
                        TodoEmptyState(reason: .noResults)
                    }
                } else {
                    flatListView
                }
            } else {
                if viewModel.isAddingTodo {
                    flatListView
                } else {
                    TodoEmptyState(reason: .notConfigured)
                }
            }
        }
        .navigationTitle("TODOs")
        .refreshable {
            if hasCustomSections {
                await viewModel.refreshAllSections(sections: customSections)
            } else {
                await viewModel.refreshTodos()
            }
        }
        .toolbar {
            toolbarContent
        }
        // Keep lifecycle, SwiftData-change, profile-change, and keyboard-focus
        // reactions out of the already-branching view layout above.
        .modifier(
            TodosHomeHandlers(
                profileViewModel: profileViewModel,
                modelContext: modelContext,
                allTodos: allTodos,
                outboxItems: outboxItems,
                outboxStatusSignature: outboxStatusSignature,
                hasCustomSections: hasCustomSections,
                viewModel: viewModel,
                isNewTodoFocused: newTodoFocusBinding
            )
        )
        .navigationDestination(isPresented: $isShowingSectionManager) {
            ManageSectionsView()
        }
        .sheet(isPresented: $isShowingAddSectionSheet) {
            NavigationStack {
                EditSectionView(section: nil, isCreatingSection: true, onFirstSectionCreated: {
                    materializeDefaultSection()
                })
            }
        }
        // Show cached section results immediately, then replace or merge them
        // with the latest Roam query results.
        .task(id: sectionQueryFingerprint) {
            viewModel.configuredSections = customSections
            if hasCustomSections {
                viewModel.buildSectionResultsFromCache(allTodos: allTodos, sections: customSections)
                await viewModel.refreshAllSections(sections: customSections)
            }
        }
        .onChange(of: customSections.map(\.id)) { _, _ in
            viewModel.configuredSections = customSections
        }
    }

    // MARK: - Sectioned List

    private var sectionedListView: some View {
        List {
            ForEach(customSections) { section in
                Section {
                    if !section.isCollapsed {
                        let todos = filteredTodosForSection(section)
                        ForEach(todos) { sectionTodo in
                            TodoRow(todo: sectionTodo.todo)
                                .listRowSeparator(.hidden)
                        }

                        // A new TODO remains an OutboxItem until Roam accepts it
                        // and the next refresh turns it into a cached TodoItem.
                        ForEach(pendingOutboxForSection(section)) { item in
                            TodoPendingRow(item: item)
                                .listRowSeparator(.hidden)
                        }

                        // Only the section that opened the editor replaces its
                        // add button with the shared inline text field.
                        if viewModel.isAddingTodo && sectionIDForNewTodo == section.id {
                            newTodoRow
                                .listRowSeparator(.hidden)
                        } else {
                            addTodoButton(for: section)
                                .listRowSeparator(.hidden)
                        }
                    }

                } header: {
                    SectionHeaderView(
                        section: section,
                        isFirstSection: section.id == customSections.first?.id,
                        onToggleCollapse: {
                            section.isCollapsed.toggle()
                            try? modelContext.save()
                        }
                    )
                }
            }
        }
        .listStyle(.plain)
        .listRowSpacing(-10)
        .listSectionSpacing(0)
        .listSectionSeparator(.hidden)
    }

    // Section queries cache both open and completed TODOs. Apply the user's
    // display preference without fetching the section again.
    private func filteredTodosForSection(_ section: TodoSection) -> [SectionTodo] {
        guard let todos = viewModel.sectionResults[section.id] else { return [] }
        if profileViewModel.todosShowCompleted { return todos }
        return todos.filter { !$0.todo.isCompleted }
    }

    // Place a queued TODO in every section whose include tags it contains. A
    // tagless section acts as "Others" and receives items matching no other one.
    private func pendingOutboxForSection(_ section: TodoSection) -> [OutboxItem] {
        let rawIncludeTagFilter = section.includeTagFilter?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let includeTags = TodoSyncManager.parseTagsFromInput(rawIncludeTagFilter)
        return viewModel.pendingOutboxItems.filter { item in
            if includeTags.isEmpty {
                // Keep tagged items out of "Others" when another section claims them.
                let otherSectionIncludeTags = customSections
                    .filter { $0.id != section.id }
                    .compactMap { $0.includeTagFilter?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .flatMap { TodoSyncManager.parseTagsFromInput($0) }
                return !otherSectionIncludeTags.contains { item.content.contains($0) }
            }
            return includeTags.contains { item.content.contains($0) }
        }
    }

    // MARK: - Flat List

    private var flatListView: some View {
        List {
            ForEach(viewModel.filteredTodos) { todo in
                TodoRow(todo: todo)
                    .listRowSeparator(.hidden)
            }

            // Pending rows bridge the time between saving locally and seeing
            // the newly synced TODO in a later Roam refresh.
            ForEach(viewModel.pendingOutboxItems) { item in
                TodoPendingRow(item: item)
                    .listRowSeparator(.hidden)
            }

            if viewModel.isAddingTodo && sectionIDForNewTodo == nil {
                newTodoRow
                    .listRowSeparator(.hidden)
            } else if !viewModel.isFetching {
                flatAddTodoButton
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .listRowSpacing(-10)
    }

    // MARK: - Toolbar

    private var toolbarContent: some ToolbarContent {
        Group {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if hasCustomSections {
                        Button {
                            isShowingSectionManager = true
                        } label: {
                            Label("Manage Sections", systemImage: "list.bullet.below.rectangle")
                        }
                    } else {
                        Button {
                            isShowingAddSectionSheet = true
                        } label: {
                            Label("Add Section", systemImage: "list.bullet.below.rectangle")
                        }
                    }

                    Divider()

                    Button {
                        profileViewModel.todosShowCompleted.toggle()
                        viewModel.handleProfileChange()
                        try? profileViewModel.saveChanges(context: modelContext)
                    } label: {
                        if profileViewModel.todosShowCompleted {
                            Label("Hide Completed", systemImage: "eye.slash")
                        } else {
                            Label("Show Completed", systemImage: "eye")
                        }
                    }

                    if !hasCustomSections {
                        NavigationLink {
                            SettingTodosQuery(viewModel: profileViewModel)
                        } label: {
                            Label("Edit TODO Filters", systemImage: "slider.horizontal.3")
                        }
                    }
                } label: {
                    Label("Menu", systemImage: "ellipsis")
                }
            }

            if viewModel.isAddingTodo {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: viewModel.submitNewTodo) {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .accessibilityLabel("Add TODO")
                }
            }
        }
    }

    // MARK: - Add TODO Components

    // Opening a section editor remembers that section and its include tags so
    // the submitted TODO will match the section's next query.
    private func addTodoButton(for section: TodoSection) -> some View {
        Button {
            sectionIDForNewTodo = section.id
            viewModel.beginNewTodo(sectionId: section.id, sectionTags: section.includeTagFilter)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "circle.dashed")
                    .foregroundStyle(.secondary)
                    .font(.title2)
                Text("New TODO...")
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .disabled(viewModel.isAddingTodo)
    }

    // The flat-list editor has no section destination, so the view model falls
    // back to the profile-wide TODO tags when it submits.
    private var flatAddTodoButton: some View {
        Button {
            sectionIDForNewTodo = nil
            viewModel.beginNewTodo()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "circle.dashed")
                    .foregroundStyle(.secondary)
                    .font(.title2)
                Text("")
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .disabled(viewModel.isAddingTodo)
    }

    // Both layouts reuse this editor; the surrounding list decides where it is shown.
    private var newTodoRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .font(.title2)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                TextField("New item", text: $viewModel.newTodoText, axis: .vertical)
                    .focused($isNewTodoFocused)
                    .lineLimit(1...8)
                    .onChange(of: viewModel.newTodoText) { oldValue, newValue in
                        guard newValue.contains("\n") else { return }
                        if newValue == oldValue + "\n" {
                            // A single Return submits instead of adding a line.
                            viewModel.newTodoText = oldValue
                            viewModel.submitNewTodo()
                        } else {
                            // Pasted line breaks are removed without submitting.
                            viewModel.newTodoText = newValue.replacingOccurrences(of: "\n", with: " ")
                        }
                    }
                Text("...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Default Section Materialization

    // When sections are enabled for the first time, preserve the old flat-list
    // filters inside an "Others" section instead of silently discarding them.
    private func materializeDefaultSection() {
        let graphName = profileViewModel.graphName ?? ""

        // The sheet callback can run more than once, so creation is idempotent.
        let descriptor = FetchDescriptor<TodoSection>(
            predicate: #Predicate { $0.isDefault == true && $0.graphName == graphName }
        )
        let existing = try? modelContext.fetch(descriptor)
        guard existing?.isEmpty ?? true else { return }

        let defaultSection = TodoSection(
            graphName: graphName,
            name: "Others",
            order: 0,
            isDefault: true,
            includeTagFilter: profileViewModel.todosTagFilter,
            excludeTagFilter: profileViewModel.todosExcludeTagFilter,
            timePeriodDays: profileViewModel.todosTimePeriod
        )
        modelContext.insert(defaultSection)
        try? modelContext.save()
    }

    // MARK: - Helpers

    // TodosHomeHandlers expects a normal Binding, while this screen owns the
    // value through FocusState so SwiftUI can control keyboard focus.
    private var newTodoFocusBinding: Binding<Bool> {
        Binding(
            get: { isNewTodoFocused },
            set: { isNewTodoFocused = $0 }
        )
    }

    // OutboxItem is a SwiftData model rather than an Equatable value. Reduce the
    // fields the handler watches to the identity and status changes it needs.
    private var outboxStatusSignature: [String] {
        outboxItems.map { "\($0.id.uuidString):\($0.status)" }
    }
}

// MARK: - Previews

#Preview("Flat List") {
    TodosViewModel.isPreviewMode = true
    let mockViewModel = ProfileViewModel()
    mockViewModel.todosEnabled = true
    mockViewModel.todosTagFilter = "[[priority]]"
    mockViewModel.todosTimePeriod = 30
    mockViewModel.graphName = "preview-graph"
    mockViewModel.todosShowCompleted = true

    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: TodoItem.self, OutboxItem.self, TodoSection.self,
        configurations: config
    )

    let todo1 = TodoItem(
        roamBlockUid: "abc123",
        text: "Review quarterly goals",
        originalString: "{{[[TODO]]}} Review quarterly goals",
        isCompleted: false
    )
    todo1.parentPageTitle = "January 3rd, 2026"

    let todo2 = TodoItem(
        roamBlockUid: "def456",
        text: "Update project documentation",
        originalString: "{{[[TODO]]}} Update project documentation",
        isCompleted: false
    )
    todo2.parentPageTitle = "Work Projects"

    let todo3 = TodoItem(
        roamBlockUid: "ghi789",
        text: "Call dentist for appointment",
        originalString: "{{[[DONE]]}} Call dentist for appointment",
        isCompleted: true
    )
    todo3.parentPageTitle = "Personal"

    container.mainContext.insert(todo1)
    container.mainContext.insert(todo2)
    container.mainContext.insert(todo3)

    let pendingOutbox = OutboxItem(content: "Review contract terms [[priority]]", type: .todo)
    pendingOutbox.status = SyncStatus.pending.rawValue
    container.mainContext.insert(pendingOutbox)

    return TodosHome()
        .environmentObject(mockViewModel)
        .modelContainer(container)
}

#Preview("Sectioned") {
    TodosViewModel.isPreviewMode = true
    let mockViewModel = ProfileViewModel()
    mockViewModel.todosEnabled = true
    mockViewModel.graphName = "preview-graph"
    mockViewModel.todosShowCompleted = true

    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: TodoItem.self, OutboxItem.self, TodoSection.self,
        configurations: config
    )
    let sampleDataContext = container.mainContext

    // Work section
    let workSection = TodoSection(
        graphName: "preview-graph",
        name: "Work",
        order: 0,
        includeTagFilter: "[[work]]",
        timePeriodDays: 30
    )
    sampleDataContext.insert(workSection)

    // Personal section
    let personalSection = TodoSection(
        graphName: "preview-graph",
        name: "Personal",
        order: 1,
        includeTagFilter: "[[personal]]",
        timePeriodDays: 60
    )
    sampleDataContext.insert(personalSection)

    // Others (default) section
    let othersSection = TodoSection(
        graphName: "preview-graph",
        name: "Others",
        order: 2,
        isDefault: true,
        timePeriodDays: 0
    )
    sampleDataContext.insert(othersSection)

    // Work TODOs
    let w1 = TodoItem(
        roamBlockUid: "w1",
        text: "Prepare Q1 presentation slides",
        originalString: "{{[[TODO]]}} Prepare Q1 presentation slides [[work]]",
        isCompleted: false
    )
    w1.parentPageTitle = "February 28th, 2026"
    sampleDataContext.insert(w1)

    let w2 = TodoItem(
        roamBlockUid: "w2",
        text: "Review pull request #142",
        originalString: "{{[[TODO]]}} Review pull request #142 [[work]]",
        isCompleted: false
    )
    w2.parentPageTitle = "February 27th, 2026"
    sampleDataContext.insert(w2)

    let w3 = TodoItem(
        roamBlockUid: "w3",
        text: "Send weekly status update",
        originalString: "{{[[DONE]]}} Send weekly status update [[work]]",
        isCompleted: true
    )
    w3.parentPageTitle = "February 26th, 2026"
    sampleDataContext.insert(w3)

    // Personal TODOs
    let p1 = TodoItem(
        roamBlockUid: "p1",
        text: "Call dentist for appointment",
        originalString: "{{[[TODO]]}} Call dentist for appointment [[personal]]",
        isCompleted: false
    )
    p1.parentPageTitle = "February 28th, 2026"
    sampleDataContext.insert(p1)

    let p2 = TodoItem(
        roamBlockUid: "p2",
        text: "Buy groceries for weekend",
        originalString: "{{[[DONE]]}} Buy groceries for weekend [[personal]]",
        isCompleted: true
    )
    p2.parentPageTitle = "February 27th, 2026"
    sampleDataContext.insert(p2)

    // Others TODOs (no specific tags)
    let o1 = TodoItem(
        roamBlockUid: "o1",
        text: "Read chapter 5 of Thinking in Systems",
        originalString: "{{[[TODO]]}} Read chapter 5 of Thinking in Systems",
        isCompleted: false
    )
    o1.parentPageTitle = "February 25th, 2026"
    sampleDataContext.insert(o1)

    // Pending outbox item in Work section
    let pendingOutbox = OutboxItem(content: "Draft team meeting agenda [[work]]", type: .todo)
    pendingOutbox.status = SyncStatus.pending.rawValue
    sampleDataContext.insert(pendingOutbox)

    try? sampleDataContext.save()

    return TodosHome()
        .environmentObject(mockViewModel)
        .modelContainer(container)
}
