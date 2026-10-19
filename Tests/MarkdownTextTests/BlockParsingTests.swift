import Testing
@testable import MarkdownText

@Suite("Block parsing")
struct BlockParsingTests {
    private func blocks(_ markdown: String) -> [MarkdownBlock] {
        MarkdownDocument(parsing: markdown).blocks
    }

    @Test func atxHeadings() {
        let result = blocks("# One\n## Two ##\n###### Six\n####### Seven")
        #expect(result == [
            .heading(level: 1, content: [.text("One")]),
            .heading(level: 2, content: [.text("Two")]),
            .heading(level: 6, content: [.text("Six")]),
            .paragraph([.text("####### Seven")]),
        ])
    }

    @Test func headingNeedsASpace() {
        #expect(blocks("#hashtag") == [.paragraph([.text("#hashtag")])])
    }

    @Test func setextHeadings() {
        let result = blocks("Title\n=====\n\nSubtitle\n---")
        #expect(result == [
            .heading(level: 1, content: [.text("Title")]),
            .heading(level: 2, content: [.text("Subtitle")]),
        ])
    }

    @Test func paragraphsAreSeparatedByBlankLines() {
        let result = blocks("First line\nsecond line\n\nNext paragraph")
        #expect(result == [
            .paragraph([.text("First line"), .softBreak, .text("second line")]),
            .paragraph([.text("Next paragraph")]),
        ])
    }

    @Test func thematicBreaks() {
        #expect(blocks("***") == [.thematicBreak])
        #expect(blocks("- - -") == [.thematicBreak])
        #expect(blocks("___") == [.thematicBreak])
        #expect(blocks("Text\n\n---\n\nMore") == [.paragraph([.text("Text")]), .thematicBreak, .paragraph([.text("More")])])
    }

    @Test func fencedCodeBlockKeepsItsContent() {
        let markdown = """
        ```swift
        let answer = 42

          print(answer)
        ```
        """
        #expect(blocks(markdown) == [.codeBlock(language: "swift", code: "let answer = 42\n\n  print(answer)")])
    }

    @Test func tildeFenceAndUnclosedFence() {
        #expect(blocks("~~~\nplain\n~~~") == [.codeBlock(language: nil, code: "plain")])
        #expect(blocks("```json\n{}") == [.codeBlock(language: "json", code: "{}")])
    }

    @Test func fenceInfoStringUsesTheFirstWord() {
        #expect(blocks("```kotlin title=\"Main.kt\"\nfun main() {}\n```") == [
            .codeBlock(language: "kotlin", code: "fun main() {}"),
        ])
    }

    @Test func indentedCodeBlock() {
        #expect(blocks("    let x = 1\n    let y = 2") == [.codeBlock(language: nil, code: "let x = 1\nlet y = 2")])
    }

    @Test func blockQuoteWithLazyContinuation() {
        let result = blocks("> Quoted *text*\ncontinues here\n\nAfter")
        #expect(result == [
            .blockQuote([
                .paragraph([.text("Quoted "), .emphasis([.text("text")]), .softBreak, .text("continues here")]),
            ]),
            .paragraph([.text("After")]),
        ])
    }

    @Test func nestedBlockQuote() {
        #expect(blocks("> outer\n>> inner") == [
            .blockQuote([
                .paragraph([.text("outer")]),
                .blockQuote([.paragraph([.text("inner")])]),
            ]),
        ])
    }

    @Test func linkReferenceDefinitionsAreRemoved() {
        let markdown = """
        See [the guide][guide] and [Docs].

        [guide]: https://example.com/guide "The Guide"
        [docs]: <https://example.com/docs>
        """
        #expect(blocks(markdown) == [
            .paragraph([
                .text("See "),
                .link(destination: "https://example.com/guide", title: "The Guide", children: [.text("the guide")]),
                .text(" and "),
                .link(destination: "https://example.com/docs", title: nil, children: [.text("Docs")]),
                .text("."),
            ]),
        ])
    }

    @Test func crlfLineEndings() {
        #expect(blocks("# Title\r\n\r\nBody") == [.heading(level: 1, content: [.text("Title")]), .paragraph([.text("Body")])])
    }

    @Test func emptyDocument() {
        #expect(blocks("").isEmpty)
        #expect(blocks("\n\n   \n").isEmpty)
    }

    @Test func plainText() {
        let document = MarkdownDocument(parsing: "# Title\n\nSome **bold** text.")
        #expect(document.plainText == "Title\n\nSome bold text.")
    }
}
