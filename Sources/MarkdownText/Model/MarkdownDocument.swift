import Foundation

/// A parsed Markdown document: a tree of blocks whose text is made of inlines.
///
/// ```swift
/// let document = MarkdownDocument(parsing: "# Hello\n\nSome *emphasis*.")
/// document.blocks // [.heading(level: 1, ...), .paragraph(...)]
/// ```
///
/// Parsing is pure and synchronous, so a document can be created anywhere and passed to ``MarkdownText``.
public struct MarkdownDocument: Hashable, Sendable {
    /// The top-level blocks, in document order.
    public var blocks: [MarkdownBlock]

    public init(blocks: [MarkdownBlock]) {
        self.blocks = blocks
    }

    /// Parses CommonMark with the GitHub Flavored Markdown extensions (tables, task lists, strikethrough and
    /// autolinks for bare URLs).
    public init(parsing markdown: String) {
        self = MarkdownParser.parse(markdown)
    }

    /// The document's text without any formatting, blocks separated by blank lines.
    public var plainText: String {
        blocks.map(\.plainText).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

/// A block-level element of a Markdown document.
public indirect enum MarkdownBlock: Hashable, Sendable {
    /// An ATX (`# Title`) or setext (`Title` underlined with `===`) heading, level 1 to 6.
    case heading(level: Int, content: [MarkdownInline])
    /// A paragraph of inline content.
    case paragraph([MarkdownInline])
    /// A block quote (`> ...`) holding further blocks.
    case blockQuote([MarkdownBlock])
    /// A bullet, ordered or task list.
    case list(MarkdownList)
    /// A fenced or indented code block. `language` is the first word of a fence's info string.
    case codeBlock(language: String?, code: String)
    /// A GitHub Flavored Markdown table.
    case table(MarkdownTable)
    /// A thematic break (`---`, `***` or `___`).
    case thematicBreak

    /// The block's text without formatting.
    public var plainText: String {
        switch self {
        case let .heading(_, content), let .paragraph(content):
            content.plainText
        case let .blockQuote(blocks):
            blocks.map(\.plainText).joined(separator: "\n")
        case let .list(list):
            list.items.map { item in item.blocks.map(\.plainText).joined(separator: "\n") }.joined(separator: "\n")
        case let .codeBlock(_, code):
            code
        case let .table(table):
            ([table.header] + table.rows)
                .map { row in row.map(\.plainText).joined(separator: "\t") }
                .joined(separator: "\n")
        case .thematicBreak:
            ""
        }
    }
}

/// A list and its items.
public struct MarkdownList: Hashable, Sendable {
    /// `true` for `1.` or `1)` lists, `false` for `-`, `+` and `*` lists.
    public var isOrdered: Bool
    /// The number of the first item of an ordered list.
    public var start: Int
    /// A tight list has no blank lines between its items, and renders them closer together.
    public var isTight: Bool
    public var items: [MarkdownListItem]

    public init(isOrdered: Bool, start: Int = 1, isTight: Bool = true, items: [MarkdownListItem]) {
        self.isOrdered = isOrdered
        self.start = start
        self.isTight = isTight
        self.items = items
    }
}

/// One item of a ``MarkdownList``.
public struct MarkdownListItem: Hashable, Sendable {
    /// `nil` for an ordinary item; `true` or `false` for a task list item (`- [x]` or `- [ ]`).
    public var isChecked: Bool?
    public var blocks: [MarkdownBlock]

    public init(isChecked: Bool? = nil, blocks: [MarkdownBlock]) {
        self.isChecked = isChecked
        self.blocks = blocks
    }

    /// Whether the item is a task list item.
    public var isTask: Bool { isChecked != nil }
}

/// The alignment of a table column, from the colons of the delimiter row.
public enum MarkdownTableAlignment: Hashable, Sendable {
    /// `---`
    case none
    /// `:---`
    case leading
    /// `:---:`
    case center
    /// `---:`
    case trailing
}

/// A GitHub Flavored Markdown table. Every row has exactly as many cells as there are columns.
public struct MarkdownTable: Hashable, Sendable {
    public var alignments: [MarkdownTableAlignment]
    public var header: [[MarkdownInline]]
    public var rows: [[[MarkdownInline]]]

    public init(alignments: [MarkdownTableAlignment], header: [[MarkdownInline]], rows: [[[MarkdownInline]]]) {
        self.alignments = alignments
        self.header = header
        self.rows = rows
    }

    public var columnCount: Int { alignments.count }
}

/// Inline content: text and its formatting.
public indirect enum MarkdownInline: Hashable, Sendable {
    case text(String)
    /// A line ending inside a paragraph; rendered as a space.
    case softBreak
    /// A hard line break: two spaces or a backslash before the line ending.
    case lineBreak
    /// A code span (`` `code` ``).
    case code(String)
    /// `*emphasis*` or `_emphasis_`.
    case emphasis([MarkdownInline])
    /// `**strong**` or `__strong__`.
    case strong([MarkdownInline])
    /// `~~strikethrough~~` (GitHub Flavored Markdown).
    case strikethrough([MarkdownInline])
    /// An inline, reference or autolink. `destination` is the URL as written, relative URLs included.
    case link(destination: String, title: String?, children: [MarkdownInline])
    /// An image. `alt` is its description.
    case image(source: String, title: String?, alt: [MarkdownInline])
    /// Raw inline HTML, such as `<br>` or `<kbd>`. It is not rendered, except `<br>` as a line break.
    case html(String)

    /// The inline's text without formatting.
    public var plainText: String {
        switch self {
        case let .text(text): text
        case .softBreak: " "
        case .lineBreak: "\n"
        case let .code(code): code
        case let .emphasis(children), let .strong(children), let .strikethrough(children):
            children.plainText
        case let .link(_, _, children): children.plainText
        case let .image(_, _, alt): alt.plainText
        case let .html(html): html.isLineBreakTag ? "\n" : ""
        }
    }
}

extension Array where Element == MarkdownInline {
    /// The inlines' text without formatting.
    public var plainText: String {
        map(\.plainText).joined()
    }
}

extension String {
    /// `<br>`, `<br/>` or `<br />`, in any case.
    var isLineBreakTag: Bool {
        let compact = lowercased().filter { !$0.isWhitespace }
        return compact == "<br>" || compact == "<br/>"
    }
}
