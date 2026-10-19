import SwiftUI
import Testing
@testable import MarkdownText

@Suite("Themes")
struct ThemeTests {
    @Test func withAppliesChanges() {
        let theme = MarkdownTheme.github.with {
            $0.blockSpacing = 30
            $0.showsCodeCopyButton = false
        }
        #expect(theme.blockSpacing == 30)
        #expect(!theme.showsCodeCopyButton)
        #expect(theme.headingDividerMaxLevel == 2)
    }

    @Test func headingFontLevelsAreClamped() {
        let theme = MarkdownTheme()
        #expect(theme.headingFont(level: 0) == theme.headingFonts[0])
        #expect(theme.headingFont(level: 9) == theme.headingFonts[5])
        let short = theme.with { $0.headingFonts = [.title] }
        #expect(short.headingFont(level: 4) == .title)
    }

    @Test func builtInThemesDiffer() {
        #expect(MarkdownTheme.default.headingDividerMaxLevel == 0)
        #expect(MarkdownTheme.github.headingDividerMaxLevel == 2)
        #expect(MarkdownTheme.docs.lineSpacing > MarkdownTheme.default.lineSpacing)
        #expect(MarkdownTheme.docs.bodyFont != MarkdownTheme.default.bodyFont)
    }

    @Test func codeColorsCoverEveryKind() {
        let colors = MarkdownCodeColors.github
        #expect(colors.color(for: .keyword) == colors.keyword)
        #expect(colors.color(for: .plain) == colors.plain)
        #expect(Set(CodeTokenKind.allCases.map { colors.color(for: $0) }).count > 5)
    }

    @Test func resolvesRelativeURLs() {
        let base = URL(string: "https://example.com/docs/")
        #expect(MarkdownURL.resolve("guide.md", baseURL: base)?.absoluteString == "https://example.com/docs/guide.md")
        #expect(MarkdownURL.resolve("https://other.example/x", baseURL: base)?.absoluteString == "https://other.example/x")
        #expect(MarkdownURL.resolve("", baseURL: base) == nil)
    }

    @Test func imageOnlyParagraphs() {
        let badges = MarkdownParser.parseInlines("[![CI](ci.svg)](https://example.com/ci) ![MIT](mit.svg)")
        #expect(MarkdownImageItem.imageOnly(badges) == [
            MarkdownImageItem(source: "ci.svg", alt: "CI", link: "https://example.com/ci"),
            MarkdownImageItem(source: "mit.svg", alt: "MIT", link: nil),
        ])
        #expect(MarkdownImageItem.imageOnly(MarkdownParser.parseInlines("Text ![a](b.png)")) == nil)
    }
}
