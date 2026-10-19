import Foundation

extension Character {
    /// CommonMark's ASCII punctuation, the characters a backslash can escape.
    var isASCIIPunctuation: Bool {
        guard let ascii = asciiValue else { return false }
        return (33...47).contains(ascii) || (58...64).contains(ascii) || (91...96).contains(ascii) || (123...126).contains(ascii)
    }

    /// Unicode punctuation or symbol, as used by the emphasis flanking rules.
    var isMarkdownPunctuation: Bool {
        isPunctuation || isSymbol
    }

    var isASCIIDigit: Bool {
        guard let ascii = asciiValue else { return false }
        return (48...57).contains(ascii)
    }

    var isASCIILetter: Bool {
        guard let ascii = asciiValue else { return false }
        return (65...90).contains(ascii) || (97...122).contains(ascii)
    }

    var isASCIIAlphanumeric: Bool {
        isASCIIDigit || isASCIILetter
    }

    var isSpaceOrTab: Bool {
        self == " " || self == "\t"
    }
}

extension StringProtocol {
    /// The number of leading spaces (tabs are expanded before block parsing).
    var leadingSpaces: Int {
        var count = 0
        for character in self {
            guard character == " " else { break }
            count += 1
        }
        return count
    }

    /// Whether the line has only spaces and tabs.
    var isBlank: Bool {
        allSatisfy(\.isSpaceOrTab)
    }

    /// The text without up to `count` leading spaces.
    func droppingLeadingSpaces(_ count: Int) -> String {
        String(dropFirst(Swift.min(count, leadingSpaces)))
    }

    /// The text without leading spaces and tabs.
    var trimmingLeadingWhitespace: String {
        String(drop(while: \.isSpaceOrTab))
    }

    /// The text without trailing spaces and tabs.
    var trimmingTrailingWhitespace: String {
        var characters = Array(self)
        while let last = characters.last, last.isSpaceOrTab {
            characters.removeLast()
        }
        return String(characters)
    }

    /// The text without leading and trailing spaces and tabs.
    var trimmingSpacesAndTabs: String {
        trimmingLeadingWhitespace.trimmingTrailingWhitespace
    }
}

extension String {
    /// Replaces tabs in the line's leading whitespace with spaces up to the next multiple of four columns.
    var expandingLeadingTabs: String {
        guard contains("\t") else { return self }
        var result = ""
        var column = 0
        var index = startIndex
        while index < endIndex {
            let character = self[index]
            if character == "\t" {
                let width = 4 - column % 4
                result += String(repeating: " ", count: width)
                column += width
            } else if character == " " {
                result.append(" ")
                column += 1
            } else {
                break
            }
            index = self.index(after: index)
        }
        return result + self[index...]
    }

    /// Resolves backslash escapes and entity references, as in link destinations, titles and info strings.
    var unescapingMarkdown: String {
        let characters = Array(self)
        var result = ""
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\\", index + 1 < characters.count, characters[index + 1].isASCIIPunctuation {
                result.append(characters[index + 1])
                index += 2
            } else if character == "&", let (decoded, end) = HTMLEntities.decode(characters, at: index) {
                result += decoded
                index = end
            } else {
                result.append(character)
                index += 1
            }
        }
        return result
    }

    /// The label as reference definitions match it: trimmed, inner whitespace collapsed, case folded.
    var normalizedLinkLabel: String {
        split(whereSeparator: \.isWhitespace).joined(separator: " ").uppercased().lowercased()
    }
}

/// Parsing of link destinations, titles and labels, shared by inline links and reference definitions.
enum LinkSyntax {
    /// Skips spaces, tabs and line endings.
    static func skipWhitespace(_ characters: [Character], _ index: inout Int) {
        while index < characters.count, characters[index].isWhitespace {
            index += 1
        }
    }

    /// Parses a link destination at `index`: `<...>` or a run of non-space characters with balanced
    /// parentheses. Returns the unescaped destination and moves `index` past it.
    static func parseDestination(_ characters: [Character], _ index: inout Int) -> String? {
        guard index < characters.count else { return nil }
        if characters[index] == "<" {
            var cursor = index + 1
            var raw = ""
            while cursor < characters.count {
                let character = characters[cursor]
                if character == "\n" || character == "<" { return nil }
                if character == ">" {
                    index = cursor + 1
                    return raw.unescapingMarkdown
                }
                if character == "\\", cursor + 1 < characters.count, characters[cursor + 1].isASCIIPunctuation {
                    raw.append(character)
                    raw.append(characters[cursor + 1])
                    cursor += 2
                    continue
                }
                raw.append(character)
                cursor += 1
            }
            return nil
        }

        var cursor = index
        var depth = 0
        var raw = ""
        while cursor < characters.count {
            let character = characters[cursor]
            if character.isWhitespace || (character.asciiValue.map { $0 < 32 || $0 == 127 } ?? false) { break }
            if character == "\\", cursor + 1 < characters.count, characters[cursor + 1].isASCIIPunctuation {
                raw.append(character)
                raw.append(characters[cursor + 1])
                cursor += 2
                continue
            }
            if character == "(" {
                depth += 1
                if depth > 32 { return nil }
            } else if character == ")" {
                if depth == 0 { break }
                depth -= 1
            }
            raw.append(character)
            cursor += 1
        }
        guard depth == 0, cursor > index else { return nil }
        index = cursor
        return raw.unescapingMarkdown
    }

    /// Parses a link title at `index`: `"..."`, `'...'` or `(...)`. Returns the unescaped title and moves
    /// `index` past it.
    static func parseTitle(_ characters: [Character], _ index: inout Int) -> String? {
        guard index < characters.count else { return nil }
        let opening = characters[index]
        let closing: Character
        switch opening {
        case "\"": closing = "\""
        case "'": closing = "'"
        case "(": closing = ")"
        default: return nil
        }
        var cursor = index + 1
        var raw = ""
        while cursor < characters.count {
            let character = characters[cursor]
            if character == "\\", cursor + 1 < characters.count, characters[cursor + 1].isASCIIPunctuation {
                raw.append(character)
                raw.append(characters[cursor + 1])
                cursor += 2
                continue
            }
            if character == closing {
                index = cursor + 1
                return raw.unescapingMarkdown
            }
            if opening == "(" && character == "(" { return nil }
            raw.append(character)
            cursor += 1
        }
        return nil
    }

    /// Parses a link label `[...]` at `index` (which must be the `[`). Returns the raw label and the index after
    /// the closing bracket.
    static func parseLabel(_ characters: [Character], at index: Int) -> (label: String, end: Int)? {
        guard index < characters.count, characters[index] == "[" else { return nil }
        var cursor = index + 1
        var label = ""
        while cursor < characters.count {
            let character = characters[cursor]
            if character == "\\", cursor + 1 < characters.count, characters[cursor + 1].isASCIIPunctuation {
                label.append(character)
                label.append(characters[cursor + 1])
                cursor += 2
                continue
            }
            if character == "[" { return nil }
            if character == "]" {
                return label.count <= 999 ? (label, cursor + 1) : nil
            }
            label.append(character)
            cursor += 1
        }
        return nil
    }
}

/// HTML entity references: the common named ones and every numeric reference.
enum HTMLEntities {
    static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "copy": "©", "reg": "®", "trade": "™", "hellip": "…", "mdash": "—", "ndash": "–",
        "laquo": "«", "raquo": "»", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
        "bull": "•", "middot": "·", "times": "×", "divide": "÷", "deg": "°", "plusmn": "±",
        "para": "¶", "sect": "§", "euro": "€", "pound": "£", "yen": "¥", "cent": "¢",
        "larr": "←", "rarr": "→", "uarr": "↑", "darr": "↓", "harr": "↔", "hearts": "♥",
        "frac12": "½", "frac14": "¼", "frac34": "¾", "sup2": "²", "sup3": "³", "micro": "µ",
        "iexcl": "¡", "iquest": "¿", "shy": "\u{00AD}", "ensp": "\u{2002}", "emsp": "\u{2003}",
        "thinsp": "\u{2009}", "zwj": "\u{200D}", "zwnj": "\u{200C}", "dagger": "†", "Dagger": "‡",
        "permil": "‰", "prime": "′", "Prime": "″", "infin": "∞", "ne": "≠", "le": "≤", "ge": "≥",
        "auml": "ä", "ouml": "ö", "uuml": "ü", "Auml": "Ä", "Ouml": "Ö", "Uuml": "Ü", "szlig": "ß",
        "eacute": "é", "egrave": "è", "aacute": "á", "agrave": "à", "ccedil": "ç", "ntilde": "ñ",
    ]

    /// Decodes the entity starting with `&` at `index`. Returns the text and the index after the `;`.
    static func decode(_ characters: [Character], at index: Int) -> (String, Int)? {
        guard index < characters.count, characters[index] == "&" else { return nil }
        var cursor = index + 1
        guard cursor < characters.count else { return nil }

        if characters[cursor] == "#" {
            cursor += 1
            var isHex = false
            if cursor < characters.count, characters[cursor] == "x" || characters[cursor] == "X" {
                isHex = true
                cursor += 1
            }
            let start = cursor
            while cursor < characters.count, cursor - start < (isHex ? 6 : 7),
                  isHex ? characters[cursor].isHexDigit : characters[cursor].isASCIIDigit {
                cursor += 1
            }
            guard cursor > start, cursor < characters.count, characters[cursor] == ";" else { return nil }
            let digits = String(characters[start..<cursor])
            guard let value = UInt32(digits, radix: isHex ? 16 : 10) else { return nil }
            let scalar = (value == 0 ? nil : Unicode.Scalar(value)) ?? "\u{FFFD}"
            return (String(Character(scalar)), cursor + 1)
        }

        let start = cursor
        while cursor < characters.count, cursor - start < 32, characters[cursor].isASCIIAlphanumeric {
            cursor += 1
        }
        guard cursor > start, cursor < characters.count, characters[cursor] == ";",
              let decoded = named[String(characters[start..<cursor])]
        else { return nil }
        return (decoded, cursor + 1)
    }
}
