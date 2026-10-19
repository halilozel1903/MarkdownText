import Foundation

/// The Markdown parser: CommonMark with the GitHub Flavored Markdown extensions.
///
/// Supported: ATX and setext headings, paragraphs, emphasis, strong emphasis, code spans, inline, reference and
/// autolinks, images, block quotes, bullet and ordered lists (tight and loose), fenced and indented code blocks,
/// thematic breaks, hard and soft line breaks, backslash escapes and entity references; from GitHub Flavored
/// Markdown, tables with column alignment, task list items, `~~strikethrough~~` and links for bare
/// `https://`, `http://` and `www.` URLs. HTML blocks are kept as text and inline HTML is dropped, except `<br>`.
public enum MarkdownParser {
    /// Parses Markdown into a ``MarkdownDocument``.
    public static func parse(_ markdown: String) -> MarkdownDocument {
        let blockParser = BlockParser()
        let rawBlocks = blockParser.parse(markdown)
        let inlineParser = InlineParser(references: blockParser.references)
        return MarkdownDocument(blocks: rawBlocks.map { convert($0, inlineParser) })
    }

    /// Parses inline Markdown only (emphasis, code, links and so on), as in a single paragraph.
    public static func parseInlines(_ markdown: String) -> [MarkdownInline] {
        InlineParser(references: [:]).parse(markdown)
    }

    private static func convert(_ block: RawBlock, _ parser: InlineParser) -> MarkdownBlock {
        switch block {
        case let .paragraph(text):
            return .paragraph(parser.parse(text))
        case let .heading(level, text):
            return .heading(level: level, content: parser.parse(text))
        case let .quote(blocks):
            return .blockQuote(blocks.map { convert($0, parser) })
        case let .list(ordered, start, tight, items):
            return .list(MarkdownList(
                isOrdered: ordered,
                start: start,
                isTight: tight,
                items: items.map { item in
                    MarkdownListItem(isChecked: item.isChecked, blocks: item.blocks.map { convert($0, parser) })
                }
            ))
        case let .code(language, code):
            return .codeBlock(language: language, code: code)
        case let .table(alignments, header, rows):
            return .table(MarkdownTable(
                alignments: alignments,
                header: header.map { parser.parse($0) },
                rows: rows.map { row in row.map { parser.parse($0) } }
            ))
        case .thematicBreak:
            return .thematicBreak
        }
    }
}
