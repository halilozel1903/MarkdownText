import Foundation

/// Parses the text of a paragraph, heading or table cell into inlines, following the CommonMark algorithm: a first
/// pass collects text, code spans, autolinks, delimiter runs (`*`, `_`, `~`) and brackets, resolving links as their
/// closing brackets arrive; a second pass pairs the delimiter runs into emphasis, strong emphasis and
/// strikethrough.
struct InlineParser {
    var references: [String: LinkReference]

    private enum Node {
        case inline(MarkdownInline)
        case text(String)
        case delimiter(Delimiter)
        case bracket(Bracket)
    }

    private struct Delimiter {
        var character: Character
        var count: Int
        var originalCount: Int
        var canOpen: Bool
        var canClose: Bool
    }

    private struct Bracket {
        var isImage: Bool
        var isActive: Bool
        /// Index of the first character after `[` in the source, for reference labels.
        var contentStart: Int
    }

    func parse(_ text: String) -> [MarkdownInline] {
        let characters = Array(text)
        var nodes: [Node] = []
        var brackets: [Int] = []
        var buffer = ""
        var index = 0

        func flush() {
            if !buffer.isEmpty {
                nodes.append(.text(buffer))
                buffer = ""
            }
        }

        while index < characters.count {
            let character = characters[index]
            switch character {
            case "\\":
                if index + 1 < characters.count, characters[index + 1] == "\n" {
                    flush()
                    nodes.append(.inline(.lineBreak))
                    index = Self.skipSpaces(characters, from: index + 2)
                } else if index + 1 < characters.count, characters[index + 1].isASCIIPunctuation {
                    buffer.append(characters[index + 1])
                    index += 2
                } else {
                    buffer.append("\\")
                    index += 1
                }

            case "`":
                let run = Self.runLength(characters, at: index)
                if let (code, end) = Self.codeSpan(characters, at: index, run: run) {
                    flush()
                    nodes.append(.inline(.code(code)))
                    index = end
                } else {
                    buffer += String(repeating: "`", count: run)
                    index += run
                }

            case "*", "_", "~":
                let run = Self.runLength(characters, at: index)
                if character == "~" && run > 2 {
                    buffer += String(repeating: "~", count: run)
                    index += run
                    break
                }
                let before: Character? = index > 0 ? characters[index - 1] : nil
                let after: Character? = index + run < characters.count ? characters[index + run] : nil
                let (canOpen, canClose) = Self.flanking(character, before: before, after: after)
                flush()
                nodes.append(.delimiter(Delimiter(
                    character: character, count: run, originalCount: run, canOpen: canOpen, canClose: canClose
                )))
                index += run

            case "!" where index + 1 < characters.count && characters[index + 1] == "[":
                flush()
                nodes.append(.bracket(Bracket(isImage: true, isActive: true, contentStart: index + 2)))
                brackets.append(nodes.count - 1)
                index += 2

            case "[":
                flush()
                nodes.append(.bracket(Bracket(isImage: false, isActive: true, contentStart: index + 1)))
                brackets.append(nodes.count - 1)
                index += 1

            case "]":
                flush()
                guard let openerIndex = brackets.last, case let .bracket(opener) = nodes[openerIndex] else {
                    buffer.append("]")
                    index += 1
                    break
                }
                brackets.removeLast()
                let literal = opener.isImage ? "![" : "["
                guard opener.isActive,
                      let link = resolveLink(characters, closingBracket: index, labelStart: opener.contentStart)
                else {
                    nodes[openerIndex] = .text(literal)
                    buffer.append("]")
                    index += 1
                    break
                }
                let children = Self.processEmphasis(Array(nodes[(openerIndex + 1)...]))
                nodes.removeSubrange(openerIndex...)
                if opener.isImage {
                    nodes.append(.inline(.image(source: link.destination, title: link.title, alt: children)))
                } else {
                    nodes.append(.inline(.link(destination: link.destination, title: link.title, children: children)))
                    // Links may not contain other links: earlier link openers become literal text.
                    for earlier in brackets {
                        if case var .bracket(bracket) = nodes[earlier], !bracket.isImage {
                            bracket.isActive = false
                            nodes[earlier] = .bracket(bracket)
                        }
                    }
                }
                index = link.end

            case "<":
                if let (inline, end) = Self.angleAutolink(characters, at: index) ?? Self.inlineHTML(characters, at: index) {
                    flush()
                    nodes.append(.inline(inline))
                    index = end
                } else {
                    buffer.append("<")
                    index += 1
                }

            case "&":
                if let (decoded, end) = HTMLEntities.decode(characters, at: index) {
                    buffer += decoded
                    index = end
                } else {
                    buffer.append("&")
                    index += 1
                }

            case "\n":
                var trailingSpaces = 0
                while buffer.hasSuffix(" ") {
                    buffer.removeLast()
                    trailingSpaces += 1
                }
                flush()
                nodes.append(.inline(trailingSpaces >= 2 ? .lineBreak : .softBreak))
                index = Self.skipSpaces(characters, from: index + 1)

            case "h", "w", "H", "W":
                if let (inline, end) = Self.extendedAutolink(characters, at: index) {
                    flush()
                    nodes.append(.inline(inline))
                    index = end
                } else {
                    buffer.append(character)
                    index += 1
                }

            default:
                buffer.append(character)
                index += 1
            }
        }
        flush()

        var inlines = Self.processEmphasis(nodes)
        // Trailing spaces at the end of the text are not part of it.
        if case let .text(last)? = inlines.last {
            let trimmed = last.trimmingTrailingWhitespace
            inlines[inlines.count - 1] = .text(trimmed)
            if trimmed.isEmpty {
                inlines.removeLast()
            }
        }
        return inlines
    }

    // MARK: - Links

    private struct ResolvedLink {
        var destination: String
        var title: String?
        var end: Int
    }

    /// Resolves the link whose text ends at the `]` at `closingBracket`: an inline link `(destination "title")`,
    /// a full `[label]`, collapsed `[]` or shortcut reference.
    private func resolveLink(_ characters: [Character], closingBracket: Int, labelStart: Int) -> ResolvedLink? {
        let next = closingBracket + 1
        if next < characters.count, characters[next] == "(", let inline = Self.inlineLinkTail(characters, at: next) {
            return inline
        }

        let text = String(characters[labelStart..<closingBracket])
        if next < characters.count, characters[next] == "[" {
            if let (label, end) = LinkSyntax.parseLabel(characters, at: next) {
                let key = (label.isBlank ? text : label).normalizedLinkLabel
                if let reference = references[key] {
                    return ResolvedLink(destination: reference.destination, title: reference.title, end: end)
                }
                return nil
            }
        }
        if let reference = references[text.normalizedLinkLabel], !text.isBlank {
            return ResolvedLink(destination: reference.destination, title: reference.title, end: next)
        }
        return nil
    }

    /// `(destination "title")` starting at the `(` at `index`.
    private static func inlineLinkTail(_ characters: [Character], at index: Int) -> ResolvedLink? {
        var cursor = index + 1
        LinkSyntax.skipWhitespace(characters, &cursor)
        guard cursor < characters.count else { return nil }
        if characters[cursor] == ")" {
            return ResolvedLink(destination: "", title: nil, end: cursor + 1)
        }
        guard let destination = LinkSyntax.parseDestination(characters, &cursor) else { return nil }
        let afterDestination = cursor
        LinkSyntax.skipWhitespace(characters, &cursor)
        var title: String?
        if cursor > afterDestination, cursor < characters.count, "\"'(".contains(characters[cursor]) {
            guard let parsed = LinkSyntax.parseTitle(characters, &cursor) else { return nil }
            title = parsed
            LinkSyntax.skipWhitespace(characters, &cursor)
        }
        guard cursor < characters.count, characters[cursor] == ")" else { return nil }
        return ResolvedLink(destination: destination, title: title, end: cursor + 1)
    }

    /// `<https://example.com>` or `<someone@example.com>`.
    private static func angleAutolink(_ characters: [Character], at index: Int) -> (MarkdownInline, Int)? {
        var cursor = index + 1
        var body = ""
        while cursor < characters.count {
            let character = characters[cursor]
            if character == ">" { break }
            if character.isWhitespace || character == "<" { return nil }
            body.append(character)
            cursor += 1
        }
        guard cursor < characters.count, !body.isEmpty else { return nil }
        let end = cursor + 1

        // A URI: a scheme of 2 to 32 characters, a colon, then anything.
        if let colon = body.firstIndex(of: ":") {
            let scheme = body[..<colon]
            if (2...32).contains(scheme.count), let first = scheme.first, first.isASCIILetter,
               scheme.allSatisfy({ $0.isASCIIAlphanumeric || $0 == "+" || $0 == "." || $0 == "-" }) {
                return (.link(destination: body, title: nil, children: [.text(body)]), end)
            }
        }
        // An email address.
        let parts = body.split(separator: "@", omittingEmptySubsequences: false)
        if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
           parts[0].allSatisfy({ $0.isASCIIAlphanumeric || ".!#$%&'*+/=?^_`{|}~-".contains($0) }),
           parts[1].allSatisfy({ $0.isASCIIAlphanumeric || $0 == "." || $0 == "-" }),
           parts[1].first?.isASCIIAlphanumeric == true, parts[1].last?.isASCIIAlphanumeric == true {
            return (.link(destination: "mailto:" + body, title: nil, children: [.text(body)]), end)
        }
        return nil
    }

    /// Raw inline HTML: an open or closing tag, or a comment. Kept as ``MarkdownInline/html(_:)``.
    private static func inlineHTML(_ characters: [Character], at index: Int) -> (MarkdownInline, Int)? {
        var cursor = index + 1
        guard cursor < characters.count else { return nil }

        if characters[cursor] == "!" {
            // <!-- comment -->
            guard cursor + 2 < characters.count, characters[cursor + 1] == "-", characters[cursor + 2] == "-" else {
                return nil
            }
            cursor += 3
            while cursor + 2 < characters.count {
                if characters[cursor] == "-", characters[cursor + 1] == "-", characters[cursor + 2] == ">" {
                    return (.html(String(characters[index...(cursor + 2)])), cursor + 3)
                }
                cursor += 1
            }
            return nil
        }

        if characters[cursor] == "/" {
            cursor += 1
        }
        guard cursor < characters.count, characters[cursor].isASCIILetter else { return nil }
        while cursor < characters.count, characters[cursor].isASCIIAlphanumeric || characters[cursor] == "-" {
            cursor += 1
        }
        var quote: Character?
        while cursor < characters.count {
            let character = characters[cursor]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "<" {
                return nil
            } else if character == ">" {
                return (.html(String(characters[index...cursor])), cursor + 1)
            }
            cursor += 1
        }
        return nil
    }

    /// GitHub's extended autolinks: `https://…`, `http://…` and `www.…` in running text.
    private static func extendedAutolink(_ characters: [Character], at index: Int) -> (MarkdownInline, Int)? {
        if index > 0 {
            let previous = characters[index - 1]
            guard previous.isWhitespace || "*_~(\"'".contains(previous) else { return nil }
        }
        let prefixes = ["https://", "http://", "www."]
        let lowered = String(characters[index..<min(characters.count, index + 8)]).lowercased()
        guard let prefix = prefixes.first(where: { lowered.hasPrefix($0) }) else { return nil }

        var end = index
        while end < characters.count, !characters[end].isWhitespace, characters[end] != "<" {
            end += 1
        }
        var link = Array(characters[index..<end])
        // Trailing punctuation is not part of the link, nor is an unbalanced closing parenthesis.
        while let last = link.last {
            if "?!.,:*_~'\"".contains(last) {
                link.removeLast()
            } else if last == ")", link.filter({ $0 == ")" }).count > link.filter({ $0 == "(" }).count {
                link.removeLast()
            } else {
                break
            }
        }
        let text = String(link)
        let host = text.dropFirst(prefix.count).prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        guard !host.isEmpty, host.contains(".") || prefix != "www.",
              host.allSatisfy({ $0.isASCIIAlphanumeric || $0 == "." || $0 == "-" || $0 == "_" || $0 == ":" }),
              host.last != "."
        else { return nil }
        let destination = prefix == "www." ? "http://" + text : text
        return (.link(destination: destination, title: nil, children: [.text(text)]), index + link.count)
    }

    // MARK: - Code spans

    /// A code span opened by `run` backticks at `index`: its content and the index after the closing run.
    private static func codeSpan(_ characters: [Character], at index: Int, run: Int) -> (String, Int)? {
        var cursor = index + run
        while cursor < characters.count {
            if characters[cursor] == "`" {
                let closing = runLength(characters, at: cursor)
                if closing == run {
                    var content = String(characters[(index + run)..<cursor]).replacingOccurrences(of: "\n", with: " ")
                    if content.count >= 2, content.first == " ", content.last == " ",
                       !content.allSatisfy({ $0 == " " }) {
                        content = String(content.dropFirst().dropLast())
                    }
                    return (content, cursor + closing)
                }
                cursor += closing
            } else {
                cursor += 1
            }
        }
        return nil
    }

    // MARK: - Emphasis

    /// Whether a delimiter run can open and close emphasis, from the characters around it.
    static func flanking(_ character: Character, before: Character?, after: Character?) -> (canOpen: Bool, canClose: Bool) {
        let beforeIsWhitespace = before?.isWhitespace ?? true
        let afterIsWhitespace = after?.isWhitespace ?? true
        let beforeIsPunctuation = before?.isMarkdownPunctuation ?? false
        let afterIsPunctuation = after?.isMarkdownPunctuation ?? false

        let leftFlanking = !afterIsWhitespace && (!afterIsPunctuation || beforeIsWhitespace || beforeIsPunctuation)
        let rightFlanking = !beforeIsWhitespace && (!beforeIsPunctuation || afterIsWhitespace || afterIsPunctuation)

        if character == "_" {
            return (
                leftFlanking && (!rightFlanking || beforeIsPunctuation),
                rightFlanking && (!leftFlanking || afterIsPunctuation)
            )
        }
        return (leftFlanking, rightFlanking)
    }

    /// Pairs delimiter runs into emphasis, strong emphasis and strikethrough; what is left becomes text.
    private static func processEmphasis(_ input: [Node]) -> [MarkdownInline] {
        var nodes = input
        var closerIndex = 0
        while closerIndex < nodes.count {
            guard case let .delimiter(closer) = nodes[closerIndex], closer.canClose else {
                closerIndex += 1
                continue
            }

            var openerIndex = closerIndex - 1
            var found = false
            while openerIndex >= 0 {
                if case let .delimiter(opener) = nodes[openerIndex], opener.character == closer.character, opener.canOpen {
                    if closer.character == "~" {
                        if opener.count == closer.count {
                            found = true
                            break
                        }
                    } else {
                        let bothCanBoth = opener.canClose || closer.canOpen
                        let sum = opener.originalCount + closer.originalCount
                        let ruleOfThree = bothCanBoth && sum % 3 == 0
                            && !(opener.originalCount % 3 == 0 && closer.originalCount % 3 == 0)
                        if !ruleOfThree {
                            found = true
                            break
                        }
                    }
                }
                openerIndex -= 1
            }

            guard found, case var .delimiter(opener) = nodes[openerIndex] else {
                closerIndex += 1
                continue
            }
            var remainingCloser = closer
            let used = closer.character == "~" ? closer.count : (closer.count >= 2 && opener.count >= 2 ? 2 : 1)
            let children = finalize(Array(nodes[(openerIndex + 1)..<closerIndex]))
            let wrapped: MarkdownInline
            if closer.character == "~" {
                wrapped = .strikethrough(children)
            } else if used == 2 {
                wrapped = .strong(children)
            } else {
                wrapped = .emphasis(children)
            }
            opener.count -= used
            remainingCloser.count -= used

            var rebuilt = Array(nodes[..<openerIndex])
            if opener.count > 0 {
                rebuilt.append(.delimiter(opener))
            }
            rebuilt.append(.inline(wrapped))
            let nextIndex = rebuilt.count
            if remainingCloser.count > 0 {
                rebuilt.append(.delimiter(remainingCloser))
            }
            rebuilt.append(contentsOf: nodes[(closerIndex + 1)...])
            nodes = rebuilt
            closerIndex = nextIndex
        }
        return finalize(nodes)
    }

    /// Turns leftover delimiters and brackets into text and merges adjacent text.
    private static func finalize(_ nodes: [Node]) -> [MarkdownInline] {
        var result: [MarkdownInline] = []
        func appendText(_ text: String) {
            guard !text.isEmpty else { return }
            if case let .text(previous)? = result.last {
                result[result.count - 1] = .text(previous + text)
            } else {
                result.append(.text(text))
            }
        }
        for node in nodes {
            switch node {
            case let .inline(inline):
                if case let .text(text) = inline {
                    appendText(text)
                } else {
                    result.append(inline)
                }
            case let .text(text):
                appendText(text)
            case let .delimiter(delimiter):
                appendText(String(repeating: delimiter.character, count: delimiter.count))
            case let .bracket(bracket):
                appendText(bracket.isImage ? "![" : "[")
            }
        }
        return result
    }

    // MARK: - Helpers

    private static func runLength(_ characters: [Character], at index: Int) -> Int {
        var end = index
        while end < characters.count, characters[end] == characters[index] {
            end += 1
        }
        return end - index
    }

    private static func skipSpaces(_ characters: [Character], from index: Int) -> Int {
        var cursor = index
        while cursor < characters.count, characters[cursor] == " " {
            cursor += 1
        }
        return cursor
    }
}
