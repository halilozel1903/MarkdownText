import Testing
@testable import MarkdownText

@Suite("Inline parsing")
struct InlineParsingTests {
    private func inlines(_ markdown: String) -> [MarkdownInline] {
        MarkdownParser.parseInlines(markdown)
    }

    @Test func emphasisAndStrong() {
        #expect(inlines("*a* _b_ **c** __d__") == [
            .emphasis([.text("a")]), .text(" "),
            .emphasis([.text("b")]), .text(" "),
            .strong([.text("c")]), .text(" "),
            .strong([.text("d")]),
        ])
    }

    @Test func strongInsideEmphasis() {
        #expect(inlines("***both***") == [.emphasis([.strong([.text("both")])])])
        #expect(inlines("*a **b** c*") == [.emphasis([.text("a "), .strong([.text("b")]), .text(" c")])])
    }

    @Test func intrawordUnderscoreIsLiteral() {
        #expect(inlines("snake_case_name") == [.text("snake_case_name")])
        #expect(inlines("2 * 3 * 4") == [.text("2 * 3 * 4")])
    }

    @Test func unmatchedDelimitersStayText() {
        #expect(inlines("**open") == [.text("**open")])
        #expect(inlines("close*") == [.text("close*")])
    }

    @Test func strikethrough() {
        #expect(inlines("~~gone~~ and ~also~") == [
            .strikethrough([.text("gone")]), .text(" and "), .strikethrough([.text("also")]),
        ])
        #expect(inlines("~~~three~~~") == [.text("~~~three~~~")])
    }

    @Test func codeSpans() {
        #expect(inlines("Use `let` here") == [.text("Use "), .code("let"), .text(" here")])
        #expect(inlines("``a ` b``") == [.code("a ` b")])
        #expect(inlines("` padded `") == [.code("padded")])
        #expect(inlines("`*not emphasis*`") == [.code("*not emphasis*")])
        #expect(inlines("`unclosed") == [.text("`unclosed")])
    }

    @Test func inlineLinks() {
        #expect(inlines("[MarkdownText](https://example.com \"Home\")") == [
            .link(destination: "https://example.com", title: "Home", children: [.text("MarkdownText")]),
        ])
        #expect(inlines("[**bold** link](/docs/guide.md)") == [
            .link(destination: "/docs/guide.md", title: nil, children: [.strong([.text("bold")]), .text(" link")]),
        ])
        #expect(inlines("[parens](https://example.com/a_(b))") == [
            .link(destination: "https://example.com/a_(b)", title: nil, children: [.text("parens")]),
        ])
        #expect(inlines("[spaces](<my file.md>)") == [
            .link(destination: "my file.md", title: nil, children: [.text("spaces")]),
        ])
    }

    @Test func notALink() {
        #expect(inlines("[just brackets]") == [.text("[just brackets]")])
        #expect(inlines("[a](b") == [.text("[a](b")])
    }

    @Test func linksCannotContainLinks() {
        #expect(inlines("[a [b](/inner) c](/outer)") == [
            .text("[a "),
            .link(destination: "/inner", title: nil, children: [.text("b")]),
            .text(" c](/outer)"),
        ])
    }

    @Test func images() {
        #expect(inlines("![A *diagram*](images/diagram.png \"Flow\")") == [
            .image(source: "images/diagram.png", title: "Flow", alt: [.text("A "), .emphasis([.text("diagram")])]),
        ])
        #expect(inlines("[![badge](badge.svg)](https://example.com)") == [
            .link(
                destination: "https://example.com",
                title: nil,
                children: [.image(source: "badge.svg", title: nil, alt: [.text("badge")])]
            ),
        ])
    }

    @Test func angleAutolinks() {
        #expect(inlines("<https://example.com/path?q=1>") == [
            .link(destination: "https://example.com/path?q=1", title: nil, children: [.text("https://example.com/path?q=1")]),
        ])
        #expect(inlines("<hello@example.com>") == [
            .link(destination: "mailto:hello@example.com", title: nil, children: [.text("hello@example.com")]),
        ])
    }

    @Test func extendedAutolinks() {
        #expect(inlines("Visit https://example.com/docs.") == [
            .text("Visit "),
            .link(destination: "https://example.com/docs", title: nil, children: [.text("https://example.com/docs")]),
            .text("."),
        ])
        #expect(inlines("(see www.example.com)") == [
            .text("(see "),
            .link(destination: "http://www.example.com", title: nil, children: [.text("www.example.com")]),
            .text(")"),
        ])
        #expect(inlines("whatever") == [.text("whatever")])
    }

    @Test func backslashEscapes() {
        #expect(inlines(#"\*not emphasis\* and \[no link\]"#) == [.text("*not emphasis* and [no link]")])
        #expect(inlines(#"C:\path"#) == [.text(#"C:\path"#)])
    }

    @Test func entities() {
        #expect(inlines("&copy; 2026 &amp; &#65;&#x42; &bogus;") == [.text("© 2026 & AB &bogus;")])
    }

    @Test func lineBreaks() {
        #expect(inlines("hard  \nbreak") == [.text("hard"), .lineBreak, .text("break")])
        #expect(inlines("hard\\\nbreak") == [.text("hard"), .lineBreak, .text("break")])
        #expect(inlines("soft\nbreak") == [.text("soft"), .softBreak, .text("break")])
    }

    @Test func inlineHTML() {
        #expect(inlines("a<br>b") == [.text("a"), .html("<br>"), .text("b")])
        #expect(inlines("<kbd>⌘</kbd>") == [.html("<kbd>"), .text("⌘"), .html("</kbd>")])
        #expect(inlines("1 < 2") == [.text("1 < 2")])
        #expect([MarkdownInline.text("a"), .html("<br />"), .text("b")].plainText == "a\nb")
    }

    @Test func flankingRules() {
        let opening = InlineParser.flanking("*", before: " ", after: "a")
        #expect(opening.canOpen)
        #expect(!opening.canClose)
        let intraword = InlineParser.flanking("_", before: "a", after: "b")
        #expect(!intraword.canOpen)
        #expect(!intraword.canClose)
    }
}
