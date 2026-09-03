/// This view captures one or more Roam TODOs in a single entry session.
/// `CaptureHome` opens it for the TODO route. It keeps an empty row ready as the
/// user types, then creates one SwiftData outbox item per non-empty TODO and uses
/// `GraphAwareSendButton` to record the chosen destination graph.

import SwiftUI
import SwiftData

struct CaptureTodo: View {
    @Environment(\.modelContext) private var modelContext: ModelContext
    @EnvironmentObject private var profileViewModel: ProfileViewModel

    @State private var todos: [String] = [""]
    @FocusState private var focusedIndex: Int?
    @Environment(\.dismiss) private var dismiss

    private var hasNonEmptyTodos: Bool {
        todos.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        VStack {
            List {
                ForEach(todos.indices, id: \.self) { index in
                    HStack(alignment: .top) {
                        Image(systemName: "circle")
                            .foregroundStyle(.secondary)
                        TextField("New To-Do", text: $todos[index], axis: .vertical)
                            .focused($focusedIndex, equals: index)
                            .lineLimit(1...8)
                            .onChange(of: todos[index]) { oldValue, newValue in
                                guard newValue.contains("\n") else {
                                    // Keep one blank row ready without saving it as a TODO.
                                    if index == todos.count - 1 && !newValue.isEmpty {
                                        todos.append("")
                                    }
                                    return
                                }
                                if newValue == oldValue + "\n" {
                                    // Return commits this row and moves focus to the next one.
                                    todos[index] = oldValue
                                    if index < todos.count - 1 {
                                        focusedIndex = index + 1
                                    } else {
                                        todos.append("")
                                        focusedIndex = todos.count - 1
                                    }
                                } else {
                                    // A pasted newline stays within this TODO rather than creating hidden rows.
                                    todos[index] = newValue.replacingOccurrences(of: "\n", with: "")
                                }
                            }
                    }
                }
            }
            .listStyle(.plain)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    focusedIndex = 0
                }
            }

            GraphAwareSendButton(
                onSend: { graphId, graphName in
                    submit(graphId: graphId, graphName: graphName)
                },
                isDisabled: !hasNonEmptyTodos
            )
            .padding()
        }
        .navigationTitle("New To-Dos")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit(graphId: String?, graphName: String) {
        let nonEmptyTodos = todos
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !nonEmptyTodos.isEmpty else { return }

        var items: [OutboxItem] = []
        for todo in nonEmptyTodos {
            let item = OutboxItem(content: todo, type: .todo)
            item.targetGraphId = graphId
            item.targetGraphName = graphName
            modelContext.insert(item)
            items.append(item)
        }
        do {
            try profileViewModel.saveChanges(context: modelContext)
            BackgroundSyncScheduler.scheduleAfterEnqueue(itemIDs: items.map(\.id))
            dismiss()
        } catch {
            items.forEach(modelContext.delete)
        }
    }

}

#Preview {
    NavigationStack {
        CaptureTodo()
            .environmentObject(ProfileViewModel())
    }
}
