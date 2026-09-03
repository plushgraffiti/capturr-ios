/// This view captures a Roam note as an editable outline of nested blocks.
/// `CaptureHome` opens it for the note route. `BlockEditor` manages the outline,
/// the toolbar edits the focused block, and sending stores either plain text or
/// encoded nested blocks in the SwiftData outbox for the chosen graph.

import SwiftUI
import SwiftData

struct CaptureWrite: View {
    @Environment(\.modelContext) private var modelContext: ModelContext
    @EnvironmentObject private var profileViewModel: ProfileViewModel

    @State private var blocks: [BlockLine] = [BlockLine()]
    @State private var focusedId: UUID?
    @State private var hasBegunEditing = false
    @StateObject private var textFieldHolder = ActiveTextFieldHolder()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            BlockEditor(blocks: $blocks, focusedId: $focusedId, textFieldHolder: textFieldHolder)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            GraphAwareSendButton(
                onSend: { graphId, graphName in
                    submit(graphId: graphId, graphName: graphName)
                },
                isDisabled: !hasContent
            )
            .padding()

            if hasBegunEditing {
                keyboardToolbar
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("New Note")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: focusedId) { _, newValue in
            if newValue != nil {
                hasBegunEditing = true
            }
        }
    }

    // MARK: - Keyboard Toolbar

    private var keyboardToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                toolbarButton(icon: "increase.indent") { indentFocused() }
                toolbarButton(icon: "decrease.indent") { outdentFocused() }
                toolbarDivider
                toolbarButton(title: "[[") { textFieldHolder.insertOrWrap(open: "[[", close: "]]") }
                toolbarButton(title: "#") { textFieldHolder.insertAtCursor("#") }
                toolbarDivider
                toolbarButton(icon: "text.quote") { textFieldHolder.prependToLine("> ") }
                toolbarButton(icon: "info.bubble") { textFieldHolder.prependToLine("[[>]] [[!NOTE]] ") }
                toolbarButton(icon: "highlighter") { textFieldHolder.insertOrWrap(open: "^^", close: "^^") }
                
                toolbarDivider
                toolbarButton(icon: "photo") { textFieldHolder.insertOrWrap(open: "![", close: "]()") }
                toolbarButton(icon: "link") { textFieldHolder.insertOrWrap(open: "[", close: "]()") }
            }
            .padding(.horizontal, 4)
        }
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 0)
        .padding(.bottom, 8)
    }

    // MARK: - Toolbar Actions

    private func indentFocused() {
        guard let id = focusedId,
              let index = blocks.firstIndex(where: { $0.id == id }),
              index > 0 else { return }
        let maxLevel = blocks[index - 1].indentLevel + 1
        if blocks[index].indentLevel < maxLevel {
            blocks[index].indentLevel += 1
        }
    }

    private func outdentFocused() {
        guard let id = focusedId,
              let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        if blocks[index].indentLevel > 0 {
            blocks[index].indentLevel -= 1
        }
    }

    // MARK: - Toolbar Helpers

    private func toolbarButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toolbarButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var toolbarDivider: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 4)
    }

    // MARK: - Content & Submission

    // Empty outline rows should not enable the send control.
    private var hasContent: Bool {
        blocks.contains { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func submit(graphId: String?, graphName: String) {
        let roamBlocks = BlockParser.buildTree(from: blocks)
        guard !roamBlocks.isEmpty else { return }

        let content: String
        // Preserve hierarchy as JSON; a single flat block can remain ordinary text.
        if roamBlocks.count > 1 || !roamBlocks[0].children.isEmpty {
            let capture = NestedCapture(blocks: roamBlocks, source: "write")
            if let data = try? JSONEncoder().encode(capture),
               let json = String(data: data, encoding: .utf8) {
                content = json
            } else {
                content = roamBlocks[0].string
            }
        } else {
            content = roamBlocks[0].string
        }

        let item = OutboxItem(content: content, type: .note)
        item.targetGraphId = graphId
        item.targetGraphName = graphName

        modelContext.insert(item)
        do {
            try profileViewModel.saveChanges(context: modelContext)
            BackgroundSyncScheduler.scheduleAfterEnqueue(itemIDs: [item.id])
            dismiss()
        } catch {
            modelContext.delete(item)
        }
    }
}

#Preview {
    CaptureWrite()
        .environmentObject(ProfileViewModel())
}
