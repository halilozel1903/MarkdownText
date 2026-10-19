import Testing
@testable import MarkdownText

@Suite("Lists and tables")
struct ListAndTableTests {
    private func blocks(_ markdown: String) -> [MarkdownBlock] {
        MarkdownDocument(parsing: markdown).blocks
    }

    private func item(_ text: String, checked: Bool? = nil) -> MarkdownListItem {
        MarkdownListItem(isChecked: checked, blocks: [.paragraph([.text(text)])])
    }

    @Test func tightBulletList() {
        #expect(blocks("- one\n- two\n- three") == [
            .list(MarkdownList(isOrdered: false, items: [item("one"), item("two"), item("three")])),
        ])
    }

    @Test func looseList() {
        #expect(blocks("* one\n\n* two") == [
            .list(MarkdownList(isOrdered: false, isTight: false, items: [item("one"), item("two")])),
        ])
    }

    @Test func orderedListKeepsItsStart() {
        #expect(blocks("3. three\n4. four") == [
            .list(MarkdownList(isOrdered: true, start: 3, items: [item("three"), item("four")])),
        ])
    }

    @Test func changingTheMarkerStartsANewList() {
        #expect(blocks("- a\n+ b") == [
            .list(MarkdownList(isOrdered: false, items: [item("a")])),
            .list(MarkdownList(isOrdered: false, items: [item("b")])),
        ])
    }

    @Test func nestedList() {
        let markdown = """
        1. First
           - nested
           - items
        2. Second
        """
        #expect(blocks(markdown) == [
            .list(MarkdownList(isOrdered: true, items: [
                MarkdownListItem(blocks: [
                    .paragraph([.text("First")]),
                    .list(MarkdownList(isOrdered: false, items: [item("nested"), item("items")])),
                ]),
                item("Second"),
            ])),
        ])
    }

    @Test func listItemWithCodeBlock() {
        let markdown = """
        - Install:

          ```sh
          swift build
          ```
        """
        #expect(blocks(markdown) == [
            .list(MarkdownList(isOrdered: false, isTight: false, items: [
                MarkdownListItem(blocks: [
                    .paragraph([.text("Install:")]),
                    .codeBlock(language: "sh", code: "swift build"),
                ]),
            ])),
        ])
    }

    @Test func taskList() {
        #expect(blocks("- [x] Parse\n- [ ] Render\n- [] Not a task") == [
            .list(MarkdownList(isOrdered: false, items: [
                item("Parse", checked: true),
                item("Render", checked: false),
                item("[] Not a task"),
            ])),
        ])
    }

    @Test func listInterruptsParagraphOnlyFromOne() {
        #expect(blocks("Steps:\n1. first") == [
            .paragraph([.text("Steps:")]),
            .list(MarkdownList(isOrdered: true, items: [item("first")])),
        ])
        #expect(blocks("The year\n2026. was good") == [
            .paragraph([.text("The year"), .softBreak, .text("2026. was good")]),
        ])
    }

    @Test func listEndsAtUnindentedParagraphAfterBlankLine() {
        #expect(blocks("- item\n\nparagraph") == [
            .list(MarkdownList(isOrdered: false, items: [item("item")])),
            .paragraph([.text("paragraph")]),
        ])
    }

    @Test func tableWithAlignments() {
        let markdown = """
        | Name | Platform | Size |
        | :--- | :------: | ---: |
        | `MarkdownText` | iOS | 12 KB |
        | Demo | macOS |
        """
        let expected = MarkdownTable(
            alignments: [.leading, .center, .trailing],
            header: [[.text("Name")], [.text("Platform")], [.text("Size")]],
            rows: [
                [[.code("MarkdownText")], [.text("iOS")], [.text("12 KB")]],
                [[.text("Demo")], [.text("macOS")], []],
            ]
        )
        #expect(blocks(markdown) == [.table(expected)])
    }

    @Test func tableWithoutOuterPipesAndEscapedPipe() {
        let markdown = "a | b\n--- | ---\nx \\| y | z"
        let expected = MarkdownTable(
            alignments: [.none, .none],
            header: [[.text("a")], [.text("b")]],
            rows: [[[.text("x | y")], [.text("z")]]]
        )
        #expect(blocks(markdown) == [.table(expected)])
    }

    @Test func tableEndsAtBlankLine() {
        let result = blocks("| a |\n| - |\n| 1 |\n\nAfter")
        #expect(result.count == 2)
        #expect(result.last == .paragraph([.text("After")]))
    }

    @Test func mismatchedDelimiterRowIsNotATable() {
        #expect(blocks("| a | b |\n| --- |") == [
            .paragraph([.text("| a | b |"), .softBreak, .text("| --- |")]),
        ])
    }

    @Test func paragraphFollowedByTable() {
        let result = blocks("Intro text\n| a | b |\n| - | - |\n| 1 | 2 |")
        #expect(result.count == 2)
        #expect(result.first == .paragraph([.text("Intro text")]))
    }
}
