/// This view draws a TODO that has been fetched from Roam and lets the user
/// mark it done or not done. `TodosHome` uses it in both the flat and sectioned
/// lists, and a tap updates the local `TodoItem` before queuing the Roam change.

import SwiftUI
import SwiftData

struct TodoRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var todo: TodoItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: {
                toggleCompletion()
            }) {
                Image(systemName: todo.isCompleted ? "checkmark.circle" : "circle")
                    .font(.title2)
                    .foregroundColor(todo.isCompleted ? .green : .gray)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(todo.text)
                    .strikethrough(todo.isCompleted)
                    .foregroundColor(todo.isCompleted ? .secondary : .primary)

                if let page = todo.parentPageTitle {
                    Text(page)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Completion Changes

    func toggleCompletion() {
        let wasCompleted = todo.isCompleted

        // Update the on-screen TODO first so the tap feels immediate.
        todo.isCompleted.toggle()
        todo.updatedAt = Date()

        do {
            try modelContext.save()

            queueTodoStateChange(markingAsDone: !wasCompleted)
        } catch {
            // If the local save fails, put the visible completion state back.
            todo.isCompleted = wasCompleted
        }
    }

    func queueTodoStateChange(markingAsDone: Bool) {
        // Store an instruction for SyncWorker. The original Roam text keeps
        // the TODO or DONE marker that the worker needs to replace.
        let outboxItem = OutboxItem(
            content: todo.originalString,
            type: .todo
        )
        outboxItem.roamBlockUid = todo.roamBlockUid
        outboxItem.action = markingAsDone ? "mark-done" : "mark-todo"

        modelContext.insert(outboxItem)

        do {
            try modelContext.save()
            BackgroundSyncScheduler.scheduleAfterEnqueue(itemIDs: [outboxItem.id])
        } catch {
            modelContext.delete(outboxItem)
            // The local toggle remains; this queueing failure is not shown in the UI.
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: TodoItem.self, configurations: config)

    let sampleTodo = TodoItem(
        roamBlockUid: "sample-uid",
        text: "Complete project documentation lots of additional text here haha",
        originalString: "{{[[TODO]]}} Complete project documentation lots of lines and text here haha",
        isCompleted: false
    )
    sampleTodo.parentPageTitle = "Projects"

    container.mainContext.insert(sampleTodo)

    return TodoRow(todo: sampleTodo)
        .modelContainer(container)
}
