import SwiftUI

/// Turns inlines into an `AttributedString` for `Text`: fonts for emphasis and code, colors, strikethrough and
/// links. Links carry their URL, so `Text` opens them with the environment's `openURL` action.
struct InlineRenderer {
    var theme: MarkdownTheme
    var baseURL: URL?
    var textColor: Color

    private typealias FontKey = AttributeScopes.SwiftUIAttributes.FontAttribute
    private typealias ForegroundKey = AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute
    private typealias BackgroundKey = AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute
    private typealias StrikethroughKey = AttributeScopes.SwiftUIAttributes.StrikethroughStyleAttribute
    private typealias UnderlineKey = AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute
    private typealias LinkKey = AttributeScopes.FoundationAttributes.LinkAttribute

    private struct Style {
        var font: Font
        var isBold = false
        var isItalic = false
        var isStruck = false
        var link: URL?
    }

    func attributedString(_ inlines: [MarkdownInline], font: Font) -> AttributedString {
        var result = AttributedString()
        let style = Style(font: font)
        for inline in inlines {
            append(inline, to: &result, style: style)
        }
        return result
    }

    private func append(_ inline: MarkdownInline, to result: inout AttributedString, style: Style) {
        switch inline {
        case let .text(text):
            result += run(text, style: style)
        case .softBreak:
            result += run(" ", style: style)
        case .lineBreak:
            result += run("\n", style: style)
        case let .code(code):
            result += run(code, style: style, isCode: true)
        case let .emphasis(children):
            var inner = style
            inner.isItalic = true
            for child in children {
                append(child, to: &result, style: inner)
            }
        case let .strong(children):
            var inner = style
            inner.isBold = true
            for child in children {
                append(child, to: &result, style: inner)
            }
        case let .strikethrough(children):
            var inner = style
            inner.isStruck = true
            for child in children {
                append(child, to: &result, style: inner)
            }
        case let .link(destination, _, children):
            var inner = style
            inner.link = MarkdownURL.resolve(destination, baseURL: baseURL) ?? style.link
            for child in children {
                append(child, to: &result, style: inner)
            }
        case let .image(_, _, alt):
            // Images inside running text show their description; paragraphs of images render the images.
            let description = alt.plainText
            if !description.isEmpty {
                var text = run(description, style: style)
                if style.link == nil {
                    text[ForegroundKey.self] = theme.secondaryTextColor
                }
                result += text
            }
        case let .html(html):
            if html.isLineBreakTag {
                result += run("\n", style: style)
            }
        }
    }

    private func run(_ text: String, style: Style, isCode: Bool = false) -> AttributedString {
        var string = AttributedString(text)
        var font = isCode ? style.font.monospaced() : style.font
        if style.isBold {
            font = font.bold()
        }
        if style.isItalic {
            font = font.italic()
        }
        string[FontKey.self] = font

        if isCode {
            string[ForegroundKey.self] = theme.inlineCodeColor
            string[BackgroundKey.self] = theme.inlineCodeBackground
        } else if style.link != nil {
            string[ForegroundKey.self] = theme.linkColor
        } else {
            string[ForegroundKey.self] = textColor
        }
        if style.isStruck {
            string[StrikethroughKey.self] = .single
        }
        if let link = style.link {
            string[LinkKey.self] = link
            if theme.underlinesLinks {
                string[UnderlineKey.self] = .single
            }
        }
        return string
    }
}
