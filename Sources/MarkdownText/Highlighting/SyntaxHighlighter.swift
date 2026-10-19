import Foundation

/// The languages ``SyntaxHighlighter`` knows. Other code blocks are shown without colors.
public enum CodeLanguage: String, CaseIterable, Hashable, Sendable {
    case swift
    case kotlin
    case json
    case shell

    /// The language of a fence's info string, with common aliases: `kt`, `kts`, `jsonc`, `sh`, `bash`, `zsh`,
    /// `console` and `shell-session`.
    public init?(infoString: String?) {
        guard let name = infoString?.lowercased() else { return nil }
        switch name {
        case "swift": self = .swift
        case "kotlin", "kt", "kts": self = .kotlin
        case "json", "jsonc", "json5", "geojson": self = .json
        case "sh", "bash", "zsh", "shell", "console", "shell-session", "terminal": self = .shell
        default: return nil
        }
    }

    /// The name shown above a code block.
    public var displayName: String {
        switch self {
        case .swift: "Swift"
        case .kotlin: "Kotlin"
        case .json: "JSON"
        case .shell: "Shell"
        }
    }
}

/// What a piece of highlighted code is.
public enum CodeTokenKind: String, CaseIterable, Hashable, Sendable {
    case plain
    case keyword
    case string
    case number
    case comment
    /// A type name (capitalized identifiers in Swift and Kotlin).
    case type
    /// A function call in Swift or Kotlin, or the command of a shell line.
    case function
    /// An attribute or annotation (`@MainActor`, `#Preview`, `@Composable`) or a shell option (`--verbose`).
    case attribute
    /// A JSON object key.
    case property
    /// A shell variable (`$HOME`, `${name}`).
    case variable
    /// `true`, `false`, `nil` and `null`.
    case literal
}

/// A run of code of one ``CodeTokenKind``.
public struct CodeToken: Hashable, Sendable {
    public var kind: CodeTokenKind
    public var text: String

    public init(_ kind: CodeTokenKind, _ text: String) {
        self.kind = kind
        self.text = text
    }
}

/// A small, dependency-free tokenizer for Swift, Kotlin, JSON and shell code. It recognizes comments, strings,
/// numbers, keywords, literals, types, function calls, attributes, JSON keys and shell variables, which is what a
/// README or documentation page needs; it is not a full grammar.
public enum SyntaxHighlighter {
    /// Splits code into tokens. Concatenating their text gives back the code unchanged. Without a language the
    /// result is one plain token.
    public static func tokens(for code: String, language: CodeLanguage?) -> [CodeToken] {
        guard let language else {
            return code.isEmpty ? [] : [CodeToken(.plain, code)]
        }
        var tokenizer = Tokenizer(characters: Array(code), language: language)
        return tokenizer.run()
    }

    private static let swiftKeywords: Set<String> = [
        "actor", "any", "as", "associatedtype", "async", "await", "break", "case", "catch", "class", "continue",
        "convenience", "default", "defer", "deinit", "didSet", "do", "else", "enum", "extension", "fallthrough",
        "fileprivate", "final", "for", "func", "get", "guard", "if", "import", "in", "indirect", "init", "inout",
        "internal", "is", "isolated", "lazy", "let", "macro", "mutating", "nonisolated", "open", "operator",
        "override", "package", "private", "protocol", "public", "repeat", "required", "rethrows", "return", "self",
        "Self", "set", "some", "static", "struct", "subscript", "super", "switch", "throw", "throws", "try",
        "typealias", "unowned", "var", "weak", "where", "while", "willSet", "consuming", "borrowing", "sending",
    ]

    private static let kotlinKeywords: Set<String> = [
        "abstract", "annotation", "as", "break", "by", "catch", "class", "companion", "const", "constructor",
        "continue", "crossinline", "data", "do", "else", "enum", "external", "final", "finally", "for", "fun", "get",
        "if", "import", "in", "infix", "init", "inline", "inner", "interface", "internal", "is", "lateinit",
        "noinline", "object", "open", "operator", "out", "override", "package", "private", "protected", "public",
        "reified", "return", "sealed", "set", "super", "suspend", "tailrec", "this", "throw", "try", "typealias",
        "val", "value", "var", "vararg", "when", "where", "while",
    ]

    private static let shellKeywords: Set<String> = [
        "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac", "in",
        "function", "return", "export", "local", "readonly", "set", "unset", "source", "alias", "select", "time",
    ]

    private static let literals: Set<String> = ["true", "false", "nil", "null"]

    private struct Tokenizer {
        let characters: [Character]
        let language: CodeLanguage
        var index = 0
        var tokens: [CodeToken] = []
        /// Shell: whether the next word is a command (at the start of a line or after `|`, `;`, `&&`).
        var expectsCommand = true

        init(characters: [Character], language: CodeLanguage) {
            self.characters = characters
            self.language = language
        }

        mutating func run() -> [CodeToken] {
            while index < characters.count {
                let character = characters[index]
                if character == "\n" {
                    expectsCommand = true
                    emit(.plain, from: index, to: index + 1)
                } else if isLineCommentStart() {
                    let end = endOfLine(from: index)
                    emit(.comment, from: index, to: end)
                } else if language == .swift || language == .kotlin, starts(with: "/*") {
                    let end = find("*/", from: index + 2).map { $0 + 2 } ?? characters.count
                    emit(.comment, from: index, to: end)
                } else if character == "\"" || (character == "'" && language != .json && language != .swift) {
                    readString(quote: character)
                } else if character.isASCIIDigit, !previousIsIdentifier() {
                    readNumber()
                } else if (character == "@" || (character == "#" && language == .swift)), nextIsIdentifierStart() {
                    let end = identifierEnd(from: index + 1)
                    emit(.attribute, from: index, to: end)
                } else if language == .shell, character == "$" {
                    readShellVariable()
                } else if language == .shell, character == "-", previousIsSpaceOrStart(), index + 1 < characters.count,
                          characters[index + 1] == "-" || characters[index + 1].isASCIILetter {
                    var end = index + 1
                    while end < characters.count, !characters[end].isWhitespace, characters[end] != "=" {
                        end += 1
                    }
                    emit(.attribute, from: index, to: end)
                } else if character.isLetter || character == "_" {
                    readWord()
                } else {
                    if language == .shell, character == "|" || character == ";" || character == "&" || character == "(" {
                        expectsCommand = true
                    }
                    emit(.plain, from: index, to: index + 1)
                }
            }
            return tokens
        }

        // MARK: Pieces

        private mutating func readString(quote: Character) {
            let start = index
            if (language == .swift || language == .kotlin), starts(with: "\"\"\"") {
                let end = find("\"\"\"", from: index + 3).map { $0 + 3 } ?? characters.count
                emit(.string, from: start, to: end)
                return
            }
            var cursor = index + 1
            let escapes = !(language == .shell && quote == "'")
            while cursor < characters.count {
                let character = characters[cursor]
                if escapes && character == "\\" {
                    cursor += 2
                    continue
                }
                if character == quote {
                    cursor += 1
                    break
                }
                if character == "\n" && language != .shell { break }
                cursor += 1
            }
            let end = min(cursor, characters.count)
            var kind = CodeTokenKind.string
            if language == .json {
                // A string followed by a colon is an object key.
                var next = end
                while next < characters.count, characters[next] == " " || characters[next] == "\t" {
                    next += 1
                }
                if next < characters.count, characters[next] == ":" {
                    kind = .property
                }
            }
            expectsCommand = false
            emit(kind, from: start, to: end)
        }

        private mutating func readNumber() {
            var end = index
            while end < characters.count {
                let character = characters[end]
                let isExponentSign = (character == "-" || character == "+") && end > index
                    && (characters[end - 1] == "e" || characters[end - 1] == "E")
                    && !characters[index..<end].contains(where: { $0 == "x" || $0 == "X" })
                if character.isHexDigit || character == "." || character == "_" || character == "x" || character == "X"
                    || character == "L" || character == "f" || character == "u" || character == "U" || isExponentSign {
                    // A dot only belongs to the number when a digit follows it (not `1..<5` or `value.1.name`).
                    if character == ".", !(end + 1 < characters.count && characters[end + 1].isASCIIDigit) { break }
                    end += 1
                } else {
                    break
                }
            }
            if language == .shell, end < characters.count, !characters[end].isWhitespace, !";|&)".contains(characters[end]) {
                // Part of a word such as `v2` or a path; read it as a word instead.
                readWord()
                return
            }
            emit(.number, from: index, to: end)
        }

        private mutating func readShellVariable() {
            var end = index + 1
            if end < characters.count, characters[end] == "{" {
                end = (find("}", from: end).map { $0 + 1 }) ?? characters.count
            } else if end < characters.count, characters[end] == "(" {
                emit(.plain, from: index, to: index + 1)
                return
            } else {
                while end < characters.count,
                      characters[end].isASCIIAlphanumeric || characters[end] == "_" || "?#@*!$".contains(characters[end]) && end == index + 1 {
                    end += 1
                }
            }
            if end == index + 1 {
                // A prompt (`$ swift build`) or a lone dollar sign.
                emit(.plain, from: index, to: end)
                return
            }
            expectsCommand = false
            emit(.variable, from: index, to: end)
        }

        private mutating func readWord() {
            var end = index
            if language == .shell {
                while end < characters.count, !characters[end].isWhitespace, !";|&()\"'=$<>`".contains(characters[end]) {
                    end += 1
                }
            } else {
                end = identifierEnd(from: index)
            }
            let word = String(characters[index..<end])
            let kind: CodeTokenKind
            switch language {
            case .swift, .kotlin:
                let keywords = language == .swift ? SyntaxHighlighter.swiftKeywords : SyntaxHighlighter.kotlinKeywords
                if SyntaxHighlighter.literals.contains(word) {
                    kind = .literal
                } else if keywords.contains(word) {
                    kind = .keyword
                } else if word.first?.isUppercase == true {
                    kind = .type
                } else if nextNonSpace(from: end) == "(" || (language == .kotlin && nextNonSpace(from: end) == "{" && isCallContext()) {
                    kind = .function
                } else {
                    kind = .plain
                }
            case .json:
                kind = SyntaxHighlighter.literals.contains(word) ? .literal : .plain
            case .shell:
                if SyntaxHighlighter.shellKeywords.contains(word) {
                    kind = .keyword
                    // `if`, `then`, `do` and friends are followed by a command.
                    expectsCommand = !["in", "function", "export", "local", "readonly", "unset", "alias"].contains(word)
                    emit(kind, from: index, to: end)
                    return
                } else if SyntaxHighlighter.literals.contains(word) {
                    kind = .literal
                } else if expectsCommand {
                    kind = .function
                } else {
                    kind = .plain
                }
                expectsCommand = false
            }
            emit(kind, from: index, to: end)
        }

        // MARK: Helpers

        private mutating func emit(_ kind: CodeTokenKind, from start: Int, to end: Int) {
            let end = max(end, start + 1)
            let text = String(characters[start..<min(end, characters.count)])
            if let last = tokens.last, last.kind == kind, kind == .plain {
                tokens[tokens.count - 1].text += text
            } else {
                tokens.append(CodeToken(kind, text))
            }
            index = min(end, characters.count)
        }

        private func isLineCommentStart() -> Bool {
            switch language {
            case .swift, .kotlin, .json:
                return starts(with: "//")
            case .shell:
                return characters[index] == "#" && previousIsSpaceOrStart()
            }
        }

        private func starts(with text: String) -> Bool {
            let pattern = Array(text)
            guard index + pattern.count <= characters.count else { return false }
            return Array(characters[index..<(index + pattern.count)]) == pattern
        }

        private func find(_ text: String, from start: Int) -> Int? {
            let pattern = Array(text)
            guard !pattern.isEmpty, start <= characters.count - pattern.count else { return nil }
            for position in start...(characters.count - pattern.count)
            where Array(characters[position..<(position + pattern.count)]) == pattern {
                return position
            }
            return nil
        }

        private func endOfLine(from start: Int) -> Int {
            var end = start
            while end < characters.count, characters[end] != "\n" {
                end += 1
            }
            return end
        }

        private func identifierEnd(from start: Int) -> Int {
            var end = start
            while end < characters.count, characters[end].isLetter || characters[end].isNumber || characters[end] == "_" {
                end += 1
            }
            return end
        }

        private func nextIsIdentifierStart() -> Bool {
            index + 1 < characters.count && (characters[index + 1].isLetter || characters[index + 1] == "_")
        }

        private func previousIsIdentifier() -> Bool {
            guard index > 0 else { return false }
            let previous = characters[index - 1]
            return previous.isLetter || previous.isNumber || previous == "_"
        }

        private func previousIsSpaceOrStart() -> Bool {
            index == 0 || characters[index - 1].isWhitespace
        }

        private func nextNonSpace(from start: Int) -> Character? {
            var cursor = start
            while cursor < characters.count, characters[cursor] == " " {
                cursor += 1
            }
            return cursor < characters.count ? characters[cursor] : nil
        }

        /// Kotlin: `items.forEach {` is a call with a trailing lambda; `class A {` is not.
        private func isCallContext() -> Bool {
            index > 0 && characters[index - 1] == "."
        }
    }
}
