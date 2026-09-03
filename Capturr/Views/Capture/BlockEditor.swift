/// This view provides the Roam-style outline editor used by `CaptureWrite`.
/// Each `BlockLine` stores one editable block and its indentation, while a UIKit
/// text-view bridge handles focus, wrapping, and Return-key behavior that SwiftUI's
/// text field cannot provide. The visible bullets are not part of the saved text.

import SwiftUI
import UIKit

// MARK: - Model

// One editable line in the outline, including its nesting and measured UI height.
struct BlockLine: Identifiable {
    let id: UUID
    var text: String
    var indentLevel: Int
    var height: CGFloat

    init(text: String = "", indentLevel: Int = 0) {
        self.id = UUID()
        self.text = text
        self.indentLevel = indentLevel
        self.height = 28
    }
}

// MARK: - Active text field holder

// Gives CaptureWrite's formatting toolbar access to the currently focused text view.
class ActiveTextFieldHolder: ObservableObject {
    weak var activeField: UITextView?

    // Wrap a selection, or insert an empty delimiter pair with the cursor between it.
    func insertOrWrap(open: String, close: String) {
        guard let textView = activeField, let range = textView.selectedTextRange else { return }
        let selected = textView.text(in: range) ?? ""
        if selected.isEmpty {
            textView.replace(range, withText: open + close)
            if let pos = textView.position(from: range.start, offset: open.count) {
                textView.selectedTextRange = textView.textRange(from: pos, to: pos)
            }
        } else {
            textView.replace(range, withText: open + selected + close)
        }
        textView.delegate?.textViewDidChange?(textView)
    }

    func insertAtCursor(_ text: String) {
        guard let textView = activeField, let range = textView.selectedTextRange else { return }
        textView.replace(range, withText: text)
        textView.delegate?.textViewDidChange?(textView)
    }

    // Add block syntax once at the beginning rather than at the current cursor position.
    func prependToLine(_ prefix: String) {
        guard let textView = activeField, let text = textView.text else { return }
        if text.hasPrefix(prefix) { return }
        guard let start = textView.position(from: textView.beginningOfDocument, offset: 0),
              let startRange = textView.textRange(from: start, to: start) else { return }
        textView.replace(startRange, withText: prefix)
        textView.delegate?.textViewDidChange?(textView)
    }
}

// MARK: - UIKit TextField wrapper

// Bridge UIKit's multiline sizing, selection, and Return interception into SwiftUI.
private struct BlockTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var dynamicHeight: CGFloat
    var isFocused: Bool
    var holder: ActiveTextFieldHolder
    var onReturn: () -> Void
    var onFocus: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = .preferredFont(forTextStyle: .body)
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.backgroundColor = .clear
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text { textView.text = text }
        context.coordinator.parent = self
        if isFocused && !textView.isFirstResponder {
            DispatchQueue.main.async { textView.becomeFirstResponder() }
        }
        BlockTextField.recalcHeight(textView, result: $dynamicHeight)
    }

    static func recalcHeight(_ textView: UITextView, result: Binding<CGFloat>) {
        let size = textView.sizeThatFits(CGSize(width: textView.frame.width, height: .greatestFiniteMagnitude))
        let newHeight = max(size.height, 28)
        if abs(result.wrappedValue - newHeight) > 0.5 {
            DispatchQueue.main.async { result.wrappedValue = newHeight }
        }
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: BlockTextField
        init(_ parent: BlockTextField) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            BlockTextField.recalcHeight(textView, result: parent.$dynamicHeight)
        }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                parent.onReturn()
                return false
            }
            return true
        }
        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.holder.activeField = textView
            parent.onFocus()
        }
    }
}

// MARK: - Block Editor

struct BlockEditor: View {
    @Binding var blocks: [BlockLine]
    @Binding var focusedId: UUID?
    var textFieldHolder: ActiveTextFieldHolder

    private let bulletSize: CGFloat = 7.2
    private let bulletSpacing: CGFloat = 10

    // Align each child bullet with the start of its parent's text.
    private var indentWidth: CGFloat { bulletSize + bulletSpacing }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach($blocks) { $block in
                        HStack(alignment: .top, spacing: bulletSpacing) {
                            Circle()
                                .fill(Color.secondary.opacity(0.5))
                                .frame(width: bulletSize, height: bulletSize)
                                .padding(.top, 7)

                            BlockTextField(
                                text: $block.text,
                                dynamicHeight: $block.height,
                                isFocused: focusedId == block.id,
                                holder: textFieldHolder,
                                onReturn: { insertBlock(after: block.id, proxy: proxy) },
                                onFocus: { focusedId = block.id }
                            )
                            .frame(maxWidth: .infinity, minHeight: block.height)
                        }
                        .padding(.leading, CGFloat(block.indentLevel) * indentWidth)
                        .contentShape(Rectangle())
                        .onTapGesture { focusedId = block.id }
                        .id(block.id)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { focusedId = blocks.first?.id }
        }
    }

    // MARK: - Block Operations

    private func insertBlock(after id: UUID, proxy: ScrollViewProxy) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        let newBlock = BlockLine(indentLevel: blocks[index].indentLevel)
        blocks.insert(newBlock, at: index + 1)
        focusedId = newBlock.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(newBlock.id, anchor: .bottom)
            }
        }
    }

}
