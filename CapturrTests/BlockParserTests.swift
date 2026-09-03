/// This test suite checks how the block editor's indented lines become a Roam block tree.
/// Swift Testing runs each `@Test`, which sends representative `BlockLine` arrays through
/// `BlockParser.buildTree`. The cases protect the nested capture structure that
/// `CaptureWrite` saves to the outbox.

import Testing
@testable import Capturr

struct BlockParserTests {
    @Test
    func emptyAndWhitespaceOnlyLinesProduceNoBlocks() {
        let lines = [
            BlockLine(),
            BlockLine(text: "   "),
            BlockLine(text: "\t"),
        ]

        #expect(BlockParser.buildTree(from: lines).isEmpty)
    }

    @Test
    func trimsContentAndPreservesSiblingOrder() {
        let lines = [
            BlockLine(text: "  First  "),
            BlockLine(text: "Second"),
            BlockLine(text: "   "),
            BlockLine(text: "Third"),
        ]

        #expect(
            BlockParser.buildTree(from: lines) == [
                RoamBlock(string: "First"),
                RoamBlock(string: "Second"),
                RoamBlock(string: "Third"),
            ]
        )
    }

    @Test
    func buildsNestedTreeAcrossIndentAndDedent() {
        let lines = [
            BlockLine(text: "Parent"),
            BlockLine(text: "Child one", indentLevel: 1),
            BlockLine(text: "Grandchild", indentLevel: 2),
            BlockLine(text: "Child two", indentLevel: 1),
            BlockLine(text: "Sibling"),
        ]

        #expect(
            BlockParser.buildTree(from: lines) == [
                RoamBlock(
                    string: "Parent",
                    children: [
                        RoamBlock(
                            string: "Child one",
                            children: [RoamBlock(string: "Grandchild")]
                        ),
                        RoamBlock(string: "Child two"),
                    ]
                ),
                RoamBlock(string: "Sibling"),
            ]
        )
    }

    @Test
    func acceptsSkippedIndentLevels() {
        let lines = [
            BlockLine(text: "Parent"),
            BlockLine(text: "Deep child", indentLevel: 3),
            BlockLine(text: "Sibling"),
        ]

        #expect(
            BlockParser.buildTree(from: lines) == [
                RoamBlock(
                    string: "Parent",
                    children: [RoamBlock(string: "Deep child")]
                ),
                RoamBlock(string: "Sibling"),
            ]
        )
    }
}
