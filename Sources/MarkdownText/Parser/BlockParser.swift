import Foundation

/// A block whose text is not yet parsed into inlines. Inline parsing runs once every link reference definition
/// of the document is known.
indirect enum RawBlock: Equatable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case quote([RawBlock])
    case list(ordered: Bool, start: Int, tight: Bool, items: [RawListItem])
    case code(language: String?, code: String)
    case table(alignments: [MarkdownTableAlignment], header: [String], rows: [[String]])
    case thematicBreak
}

struct RawListItem: Equatable {
    var isChecked: Bool?
    var blocks: [RawBlock]
}

/// A link reference definition: `[label]: destination "title"`.
struct LinkReference: Equatable {
    var destination: String
    var title: String?
}

/// Splits Markdown into blocks, line by line. Container blocks (block quotes and list items) collect their lines,
/// strip their markers and indentation, and parse the result recursively.
final class BlockParser {
    private(set) var references: [String: LinkReference] = [:]

    func parse(_ markdown: String) -> [RawBlock] {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{0000}", with: "\u{FFFD}")
        let lines = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).expandingLeadingTabs }
        return parseBlocks(lines).blocks
    }

    // MARK: - Blocks

    /// Parses lines into blocks. `blankBetweenBlocks` reports a blank line between two of the blocks, which makes a
    /// list item loose.
    func parseBlocks(_ lines: [String]) -> (blocks: [RawBlock], blankBetweenBlocks: Bool) {
        var blocks: [RawBlock] = []
        var index = 0
        var pendingBlank = false
        var blankBetweenBlocks = false

        func append(_ block: RawBlock) {
            if pendingBlank && !blocks.isEmpty {
                blankBetweenBlocks = true
            }
            pendingBlank = false
            blocks.append(block)
        }

        while index < lines.count {
            let line = lines[index]

            if line.isBlank {
                pendingBlank = true
                index += 1
                continue
            }

            // Indented code block.
            if line.leadingSpaces >= 4 {
                var code: [String] = []
                while index < lines.count, lines[index].isBlank || lines[index].leadingSpaces >= 4 {
                    code.append(lines[index].isBlank ? "" : lines[index].droppingLeadingSpaces(4))
                    index += 1
                }
                while code.last == "" {
                    code.removeLast()
                }
                append(.code(language: nil, code: code.joined(separator: "\n")))
                // Blank lines that ended the block separate it from the next one.
                if index > 0, lines[index - 1].isBlank {
                    pendingBlank = true
                }
                continue
            }

            if let fence = Fence(opening: line) {
                index += 1
                var code: [String] = []
                while index < lines.count {
                    if fence.isClosed(by: lines[index]) {
                        index += 1
                        break
                    }
                    code.append(lines[index].droppingLeadingSpaces(fence.indent))
                    index += 1
                }
                append(.code(language: fence.language, code: code.joined(separator: "\n")))
                continue
            }

            if let heading = Self.atxHeading(line) {
                append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if Self.isThematicBreak(line) {
                append(.thematicBreak)
                index += 1
                continue
            }

            if Self.stripQuoteMarker(line) != nil {
                var quoted: [String] = []
                while index < lines.count {
                    let current = lines[index]
                    if let stripped = Self.stripQuoteMarker(current) {
                        quoted.append(stripped)
                        index += 1
                    } else if !current.isBlank, let last = quoted.last, Self.isParagraphContinuation(last),
                              !Self.startsBlock(current, interruptingParagraph: true) {
                        // A lazy continuation line of a paragraph inside the quote.
                        quoted.append(current)
                        index += 1
                    } else {
                        break
                    }
                }
                append(.quote(parseBlocks(quoted).blocks))
                continue
            }

            if let marker = ListMarker(line) {
                let (list, end) = parseList(lines, from: index, first: marker)
                append(list)
                index = end
                continue
            }

            if let table = Self.parseTable(lines, at: index) {
                append(table.block)
                index = table.end
                continue
            }

            // Paragraph, or a setext heading.
            var paragraph = [line.trimmingLeadingWhitespace]
            var headingLevel: Int?
            index += 1
            while index < lines.count {
                let current = lines[index]
                if current.isBlank { break }
                if let level = Self.setextLevel(current) {
                    headingLevel = level
                    index += 1
                    break
                }
                if current.leadingSpaces < 4 && Self.startsBlock(current, interruptingParagraph: true) { break }
                if Self.parseTable(lines, at: index) != nil { break }
                paragraph.append(current.trimmingLeadingWhitespace)
                index += 1
            }

            let text = paragraph.joined(separator: "\n")
            let remaining = extractReferenceDefinitions(from: text)
            if let headingLevel {
                if remaining.isBlank {
                    // Only definitions above the underline: the underline is paragraph text.
                    append(.paragraph(headingLevel == 1 ? "===" : "---"))
                } else {
                    append(.heading(level: headingLevel, text: remaining.trimmingSpacesAndTabs))
                }
            } else if !remaining.isBlank {
                append(.paragraph(remaining.trimmingTrailingWhitespace))
            }
        }

        return (blocks, blankBetweenBlocks)
    }

    // MARK: - Lists

    private func parseList(_ lines: [String], from start: Int, first: ListMarker) -> (RawBlock, Int) {
        var index = start
        var marker = first
        var items: [RawListItem] = []
        var isTight = true

        while true {
            var itemLines = [marker.content]
            index += 1
            while index < lines.count {
                let current = lines[index]
                if current.isBlank {
                    // An item may start with at most one blank line.
                    if itemLines.count == 1 && itemLines[0].isBlank { break }
                    var next = index
                    while next < lines.count, lines[next].isBlank {
                        next += 1
                    }
                    guard next < lines.count, lines[next].leadingSpaces >= marker.contentIndent else { break }
                    itemLines.append(contentsOf: Array(repeating: "", count: next - index))
                    index = next
                    continue
                }
                if current.leadingSpaces >= marker.contentIndent {
                    itemLines.append(String(current.dropFirst(marker.contentIndent)))
                    index += 1
                    continue
                }
                if let last = itemLines.last, Self.isParagraphContinuation(last),
                   !Self.startsBlock(current, interruptingParagraph: true), ListMarker(current) == nil {
                    itemLines.append(current.trimmingLeadingWhitespace)
                    index += 1
                    continue
                }
                break
            }

            var isChecked: Bool?
            if let task = Self.taskMarker(itemLines[0]) {
                isChecked = task.isChecked
                itemLines[0] = task.rest
            }
            let (blocks, blankBetweenBlocks) = parseBlocks(itemLines)
            if blankBetweenBlocks {
                isTight = false
            }
            items.append(RawListItem(isChecked: isChecked, blocks: blocks))

            var next = index
            while next < lines.count, lines[next].isBlank {
                next += 1
            }
            guard next < lines.count,
                  !Self.isThematicBreak(lines[next]),
                  let nextMarker = ListMarker(lines[next]),
                  nextMarker.isOrdered == first.isOrdered,
                  nextMarker.delimiter == first.delimiter
            else { break }
            if next > index {
                isTight = false
            }
            index = next
            marker = nextMarker
        }

        return (.list(ordered: first.isOrdered, start: first.number, tight: isTight, items: items), index)
    }

    /// `[ ] rest` or `[x] rest` at the start of a list item.
    static func taskMarker(_ line: String) -> (isChecked: Bool, rest: String)? {
        let characters = Array(line)
        guard characters.count >= 4, characters[0] == "[", characters[2] == "]", characters[3].isSpaceOrTab else {
            return nil
        }
        let isChecked: Bool
        switch characters[1] {
        case " ": isChecked = false
        case "x", "X": isChecked = true
        default: return nil
        }
        let rest = String(characters[4...]).trimmingLeadingWhitespace
        guard !rest.isEmpty else { return nil }
        return (isChecked, rest)
    }

    // MARK: - Line classification

    /// Whether the line opens a block that ends a paragraph.
    static func startsBlock(_ line: String, interruptingParagraph: Bool) -> Bool {
        guard line.leadingSpaces < 4 else { return false }
        if Fence(opening: line) != nil || atxHeading(line) != nil || isThematicBreak(line) || stripQuoteMarker(line) != nil {
            return true
        }
        if let marker = ListMarker(line) {
            guard interruptingParagraph else { return true }
            // An empty item, or an ordered list not starting at 1, cannot interrupt a paragraph.
            return !marker.content.isBlank && (!marker.isOrdered || marker.number == 1)
        }
        return false
    }

    /// Whether the line can be followed by a lazy continuation line: it is paragraph text.
    static func isParagraphContinuation(_ line: String) -> Bool {
        !line.isBlank && line.leadingSpaces < 4 && !startsBlock(line, interruptingParagraph: false)
            && setextLevel(line) == nil
    }

    static func atxHeading(_ line: String) -> (level: Int, text: String)? {
        guard line.leadingSpaces <= 3 else { return nil }
        let content = line.trimmingLeadingWhitespace
        let hashes = content.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let rest = content.dropFirst(hashes)
        guard rest.isEmpty || rest.first?.isSpaceOrTab == true else { return nil }

        var text = Array(rest.trimmingSpacesAndTabs)
        // An optional closing sequence of #s, preceded by a space (or making up the whole text).
        if let lastNonHash = text.lastIndex(where: { $0 != "#" }) {
            if lastNonHash < text.count - 1, text[lastNonHash].isSpaceOrTab {
                text = Array(String(text[...lastNonHash]).trimmingTrailingWhitespace)
            }
        } else {
            text = []
        }
        return (hashes, String(text))
    }

    static func isThematicBreak(_ line: String) -> Bool {
        guard line.leadingSpaces <= 3 else { return false }
        let marks = line.filter { !$0.isSpaceOrTab }
        guard let first = marks.first, "*-_".contains(first), marks.count >= 3 else { return false }
        return marks.allSatisfy { $0 == first }
    }

    /// The level of a setext underline: 1 for `===`, 2 for `---`.
    static func setextLevel(_ line: String) -> Int? {
        guard line.leadingSpaces <= 3 else { return nil }
        let content = line.trimmingSpacesAndTabs
        guard let first = content.first, first == "=" || first == "-", content.allSatisfy({ $0 == first }) else {
            return nil
        }
        return first == "=" ? 1 : 2
    }

    /// The line without its `>` marker and one following space, or `nil` when it is not quoted.
    static func stripQuoteMarker(_ line: String) -> String? {
        guard line.leadingSpaces <= 3 else { return nil }
        let content = line.trimmingLeadingWhitespace
        guard content.first == ">" else { return nil }
        var rest = content.dropFirst()
        if rest.first == " " || rest.first == "\t" {
            rest = rest.dropFirst()
        }
        return String(rest).expandingLeadingTabs
    }

    // MARK: - Tables

    static func parseTable(_ lines: [String], at index: Int) -> (block: RawBlock, end: Int)? {
        guard index + 1 < lines.count else { return nil }
        let headerLine = lines[index]
        let delimiterLine = lines[index + 1]
        guard headerLine.leadingSpaces < 4, headerLine.contains("|") || delimiterLine.contains("|"),
              let alignments = delimiterRow(delimiterLine)
        else { return nil }
        let header = splitRow(headerLine)
        guard header.count == alignments.count else { return nil }

        var rows: [[String]] = []
        var end = index + 2
        while end < lines.count {
            let line = lines[end]
            if line.isBlank || startsBlock(line, interruptingParagraph: true) { break }
            var cells = splitRow(line)
            if cells.count < alignments.count {
                cells += Array(repeating: "", count: alignments.count - cells.count)
            } else if cells.count > alignments.count {
                cells = Array(cells.prefix(alignments.count))
            }
            rows.append(cells)
            end += 1
        }
        return (.table(alignments: alignments, header: header, rows: rows), end)
    }

    /// The alignments of a delimiter row such as `| :--- | :---: | ---: |`.
    static func delimiterRow(_ line: String) -> [MarkdownTableAlignment]? {
        guard line.leadingSpaces < 4 else { return nil }
        let cells = splitRow(line)
        guard !cells.isEmpty else { return nil }
        var alignments: [MarkdownTableAlignment] = []
        for cell in cells {
            let leading = cell.hasPrefix(":")
            let trailing = cell.hasSuffix(":") && cell.count > 1
            let dashes = cell.dropFirst(leading ? 1 : 0).dropLast(trailing ? 1 : 0)
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            switch (leading, trailing) {
            case (true, true): alignments.append(.center)
            case (true, false): alignments.append(.leading)
            case (false, true): alignments.append(.trailing)
            case (false, false): alignments.append(.none)
            }
        }
        return alignments
    }

    /// Splits a table row on unescaped pipes, without the optional outer pipes. Cells are trimmed; escaped pipes
    /// stay escaped for the inline parser.
    static func splitRow(_ line: String) -> [String] {
        var content = Array(line.trimmingSpacesAndTabs)
        if content.first == "|" {
            content.removeFirst()
        }
        if content.last == "|", !(content.count >= 2 && content[content.count - 2] == "\\") {
            content.removeLast()
        }
        var cells: [String] = []
        var current = ""
        var index = 0
        while index < content.count {
            let character = content[index]
            if character == "\\", index + 1 < content.count {
                // `\|` becomes a literal pipe inside the cell; other escapes are left for the inline parser.
                if content[index + 1] == "|" {
                    current.append("|")
                } else {
                    current.append(character)
                    current.append(content[index + 1])
                }
                index += 2
                continue
            }
            if character == "|" {
                cells.append(current.trimmingSpacesAndTabs)
                current = ""
            } else {
                current.append(character)
            }
            index += 1
        }
        cells.append(current.trimmingSpacesAndTabs)
        return cells
    }

    // MARK: - Link reference definitions

    /// Removes the link reference definitions at the start of a paragraph, records them, and returns the rest.
    func extractReferenceDefinitions(from text: String) -> String {
        guard text.hasPrefix("[") else { return text }
        var characters = Array(text)
        while let (reference, label, end) = Self.parseReferenceDefinition(characters) {
            let key = label.normalizedLinkLabel
            if references[key] == nil {
                references[key] = reference
            }
            characters = Array(characters[end...])
        }
        return String(characters)
    }

    /// Parses one definition at the start of `characters`. Returns it with its label and the index after it
    /// (past its line ending).
    static func parseReferenceDefinition(_ characters: [Character]) -> (LinkReference, String, Int)? {
        guard let (label, afterLabel) = LinkSyntax.parseLabel(characters, at: 0),
              !label.isBlank, afterLabel < characters.count, characters[afterLabel] == ":"
        else { return nil }
        var index = afterLabel + 1
        LinkSyntax.skipWhitespace(characters, &index)
        guard let destination = LinkSyntax.parseDestination(characters, &index) else { return nil }
        let afterDestination = index

        // The rest of a line, if it holds only spaces, ends the definition.
        func endOfLine(from start: Int) -> Int? {
            var cursor = start
            while cursor < characters.count, characters[cursor].isSpaceOrTab {
                cursor += 1
            }
            if cursor == characters.count { return cursor }
            return characters[cursor] == "\n" ? cursor + 1 : nil
        }

        var titleStart = afterDestination
        LinkSyntax.skipWhitespace(characters, &titleStart)
        if titleStart > afterDestination {
            var cursor = titleStart
            if let title = LinkSyntax.parseTitle(characters, &cursor), let end = endOfLine(from: cursor) {
                return (LinkReference(destination: destination, title: title), label, end)
            }
        }
        guard let end = endOfLine(from: afterDestination) else { return nil }
        return (LinkReference(destination: destination, title: nil), label, end)
    }
}

/// The opening line of a fenced code block.
struct Fence {
    var character: Character
    var length: Int
    var indent: Int
    var language: String?

    init?(opening line: String) {
        let indent = line.leadingSpaces
        guard indent <= 3 else { return nil }
        let content = line.dropFirst(indent)
        guard let character = content.first, character == "`" || character == "~" else { return nil }
        let length = content.prefix(while: { $0 == character }).count
        guard length >= 3 else { return nil }
        let info = content.dropFirst(length).trimmingSpacesAndTabs
        if character == "`" && info.contains("`") { return nil }
        self.character = character
        self.length = length
        self.indent = indent
        let word = info.split(whereSeparator: \.isWhitespace).first.map { String($0).unescapingMarkdown }
        self.language = word?.isEmpty == false ? word : nil
    }

    func isClosed(by line: String) -> Bool {
        guard line.leadingSpaces <= 3 else { return false }
        let content = line.trimmingSpacesAndTabs
        return content.count >= length && content.allSatisfy { $0 == character }
    }
}

/// A list item marker: `-`, `+`, `*`, or a number followed by `.` or `)`.
struct ListMarker: Equatable {
    var isOrdered: Bool
    var delimiter: Character
    var number: Int
    /// The column where the item's content starts; continuation lines are indented at least this far.
    var contentIndent: Int
    /// The text after the marker on its line.
    var content: String

    init?(_ line: String) {
        let indent = line.leadingSpaces
        guard indent <= 3 else { return nil }
        let characters = Array(line.dropFirst(indent))
        guard let first = characters.first else { return nil }

        let markerWidth: Int
        if first == "-" || first == "+" || first == "*" {
            isOrdered = false
            delimiter = first
            number = 1
            markerWidth = 1
        } else {
            let digits = characters.prefix(while: \.isASCIIDigit)
            guard (1...9).contains(digits.count), characters.count > digits.count,
                  characters[digits.count] == "." || characters[digits.count] == ")",
                  let value = Int(String(digits))
            else { return nil }
            isOrdered = true
            delimiter = characters[digits.count]
            number = value
            markerWidth = digits.count + 1
        }

        let after = Array(characters.dropFirst(markerWidth))
        if after.isEmpty || String(after).isBlank {
            contentIndent = indent + markerWidth + 1
            content = ""
            return
        }
        guard after[0].isSpaceOrTab else { return nil }
        let spaces = after.prefix(while: \.isSpaceOrTab).count
        if spaces >= 5 {
            // The content is an indented code block: only one space belongs to the marker.
            contentIndent = indent + markerWidth + 1
            content = String(after.dropFirst(1))
        } else {
            contentIndent = indent + markerWidth + spaces
            content = String(after.dropFirst(spaces))
        }
    }
}
