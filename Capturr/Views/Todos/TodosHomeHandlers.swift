/// These view modifiers keep `TodosHome` reactions separate from its visual
/// layout. `TodosHome` applies the public modifier, which feeds SwiftData and
/// profile changes into `TodosViewModel` and manages keyboard focus for the
/// inline new-TODO editor. Private modifiers keep the data and focus sequences
/// small and readable.

import SwiftUI
import SwiftData

// MARK: - Combined Handler

struct TodosHomeHandlers: ViewModifier {
    let profileViewModel: ProfileViewModel
    let modelContext: ModelContext
    let allTodos: [TodoItem]
    let outboxItems: [OutboxItem]
    let outboxStatusSignature: [String]
    let hasCustomSections: Bool
    @ObservedObject var viewModel: TodosViewModel
    @Binding var isNewTodoFocused: Bool

    func body(content: Content) -> some View {
        content
            .modifier(
                TodosHomeDataHandlers(
                profileViewModel: profileViewModel,
                modelContext: modelContext,
                allTodos: allTodos,
                outboxItems: outboxItems,
                outboxStatusSignature: outboxStatusSignature,
                hasCustomSections: hasCustomSections,
                viewModel: viewModel
            )
            )
            .modifier(
                TodosHomeFocusHandlers(
                    viewModel: viewModel,
                    isNewTodoFocused: $isNewTodoFocused
                )
            )
    }
}

// MARK: - Data and Profile Changes

private struct TodosHomeDataHandlers: ViewModifier {
    let profileViewModel: ProfileViewModel
    let modelContext: ModelContext
    let allTodos: [TodoItem]
    let outboxItems: [OutboxItem]
    let outboxStatusSignature: [String]
    let hasCustomSections: Bool
    @ObservedObject var viewModel: TodosViewModel

    func body(content: Content) -> some View {
        content
            .task {
                // Seed the view model from the screen's live queries. TodosHome
                // owns section refreshes; this task starts only the flat query.
                viewModel.configure(profileViewModel: profileViewModel, modelContext: modelContext)
                viewModel.updateTodos(allTodos)
                viewModel.updateOutbox(outboxItems)

                if viewModel.isConfigured && !hasCustomSections {
                    await viewModel.refreshTodos()
                }
            }
            .onChange(of: allTodos) { _, updatedTodos in
                viewModel.updateTodos(updatedTodos)
                // A Roam merge changes the SwiftData query. Sectioned mode must
                // regroup that updated cache using its current filters.
                if !viewModel.configuredSections.isEmpty {
                    viewModel.buildSectionResultsFromCache(allTodos: updatedTodos, sections: viewModel.configuredSections)
                }
            }
            .onChange(of: outboxStatusSignature) { _, _ in
                // Identity/status changes update pending rows and let the view
                // model detect when a queued TODO has finished syncing.
                viewModel.updateOutbox(outboxItems)
            }
            // Profile-wide filters rebuild local state immediately and trigger
            // a flat-list Roam refresh using the new values.
            .onChange(of: profileViewModel.todosTagFilter) {
                viewModel.handleFilterChange()
            }
            .onChange(of: profileViewModel.todosExcludeTagFilter) {
                viewModel.handleFilterChange()
            }
            .onChange(of: profileViewModel.todosTimePeriod) {
                viewModel.handleFilterChange()
            }
            .onChange(of: profileViewModel.todosBadgeEnabled) { _, _ in
                viewModel.handleProfileChange()
            }
            .onChange(of: profileViewModel.todosShowCompleted) { _, _ in
                viewModel.handleProfileChange()
            }
            .onChange(of: profileViewModel.todosEnabled) { _, _ in
                viewModel.handleProfileChange()
            }
            .onChange(of: profileViewModel.graphName) { _, _ in
                viewModel.handleProfileChange()
            }
    }
}

// MARK: - Inline Editor Focus

private struct TodosHomeFocusHandlers: ViewModifier {
    @ObservedObject var viewModel: TodosViewModel
    @Binding var isNewTodoFocused: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: viewModel.isAddingTodo) { _, isAddingTodo in
                if isAddingTodo {
                    // The text field is inserted only after this state changes.
                    // Wait one run-loop turn before asking SwiftUI to focus it.
                    DispatchQueue.main.async {
                        isNewTodoFocused = true
                    }
                } else {
                    isNewTodoFocused = false
                }
            }
            .onChange(of: isNewTodoFocused) { _, isFocused in
                // Leaving an untouched editor cancels it; non-empty draft text
                // remains available if focus moves elsewhere.
                if !isFocused, viewModel.isAddingTodo {
                    let trimmedTodoText = viewModel.newTodoText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedTodoText.isEmpty {
                        viewModel.cancelNewTodo()
                    }
                }
            }
    }
}
