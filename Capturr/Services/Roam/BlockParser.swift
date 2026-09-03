/// This parser turns the block editor's flat, indented lines into a nested Roam block tree.
/// `CaptureWrite` calls it before saving a structured capture to the outbox. Indentation
/// decides which lines become children, and blank lines are left out of the result.

import Foundation

enum BlockParser {

    // Builds a RoamBlock tree from the block editor's structured lines.
    // Blank lines (after trimming whitespace) are skipped so they never become empty blocks.
    static func buildTree(from lines: [BlockLine]) -> [RoamBlock] {
        let entries = lines
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { (level: $0.indentLevel, text: $0.text.trimmingCharacters(in: .whitespaces)) }
        guard !entries.isEmpty else { return [] }
        return buildTree(from: entries)
    }

    // Builds the tree in a single bottom-to-top pass using a stack.
    //
    // Indentation becomes nesting: each line takes the more-indented lines below it as its
    // children. Going bottom-up means those children are already built when the parent claims them.
    private static func buildTree(from entries: [(level: Int, text: String)]) -> [RoamBlock] {
        var stack: [(level: Int, block: RoamBlock)] = []

        for entry in entries.reversed() {
            var block = RoamBlock(string: entry.text)

            // Deeper-indented blocks on the stack become this entry's children.
            var children: [RoamBlock] = []
            while let top = stack.last, top.level > entry.level {
                children.append(stack.removeLast().block)
            }
            block.children = children

            stack.append((level: entry.level, block: block))
        }

        return stack.reversed().map(\.block)
    }
}
