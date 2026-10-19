import Testing
@testable import MarkdownText

@Suite("Syntax highlighting")
struct SyntaxHighlighterTests {
    private func kinds(_ code: String, _ language: CodeLanguage) -> [CodeTokenKind: [String]] {
        var result: [CodeTokenKind: [String]] = [:]
        for token in SyntaxHighlighter.tokens(for: code, language: language) where token.kind != .plain {
            result[token.kind, default: []].append(token.text)
        }
        return result
    }

    @Test func languageAliases() {
        #expect(CodeLanguage(infoString: "Swift") == .swift)
        #expect(CodeLanguage(infoString: "kt") == .kotlin)
        #expect(CodeLanguage(infoString: "bash") == .shell)
        #expect(CodeLanguage(infoString: "jsonc") == .json)
        #expect(CodeLanguage(infoString: "ruby") == nil)
        #expect(CodeLanguage(infoString: nil) == nil)
    }

    @Test(arguments: [
        ("struct Item: Identifiable { let id = 42 }", CodeLanguage.swift),
        ("fun main() { println(\"Hi\") } // done", CodeLanguage.kotlin),
        ("{ \"name\": \"Demo\", \"count\": 3 }", CodeLanguage.json),
        ("$ swift build -c release # build", CodeLanguage.shell),
    ])
    func tokensRebuildTheCode(code: String, language: CodeLanguage) {
        let tokens = SyntaxHighlighter.tokens(for: code, language: language)
        #expect(tokens.map(\.text).joined() == code)
    }

    @Test func swift() {
        let code = """
        @MainActor
        struct Greeting: View {
            let count = 3 // three
            var body: some View { Text("Hello") }
        }
        """
        let result = kinds(code, .swift)
        #expect(result[.attribute] == ["@MainActor"])
        #expect(result[.keyword] == ["struct", "let", "var", "some"])
        #expect(result[.type] == ["Greeting", "View", "View", "Text"])
        #expect(result[.number] == ["3"])
        #expect(result[.comment] == ["// three"])
        #expect(result[.string] == ["\"Hello\""])
    }

    @Test func swiftMultilineStringAndBlockComment() {
        let code = "/* note */ let s = \"\"\"\nline\n\"\"\""
        let result = kinds(code, .swift)
        #expect(result[.comment] == ["/* note */"])
        #expect(result[.string] == ["\"\"\"\nline\n\"\"\""])
    }

    @Test func kotlin() {
        let code = "data class User(val name: String) { fun greet() = println(\"Hi $name\") }"
        let result = kinds(code, .kotlin)
        #expect(result[.keyword] == ["data", "class", "val", "fun"])
        #expect(result[.type] == ["User", "String"])
        #expect(result[.function] == ["greet", "println"])
        #expect(result[.string] == ["\"Hi $name\""])
    }

    @Test func json() {
        let code = "{\"name\": \"Demo\", \"tags\": [true, null], \"size\": 1.5e3}"
        let result = kinds(code, .json)
        #expect(result[.property] == ["\"name\"", "\"tags\"", "\"size\""])
        #expect(result[.string] == ["\"Demo\""])
        #expect(result[.literal] == ["true", "null"])
        #expect(result[.number] == ["1.5e3"])
    }

    @Test func shell() {
        let code = "export PATH=\"$HOME/bin\" # setup\nswift build --configuration release | tee log.txt"
        let result = kinds(code, .shell)
        #expect(result[.keyword] == ["export"])
        #expect(result[.comment] == ["# setup"])
        #expect(result[.string] == ["\"$HOME/bin\""])
        #expect(result[.function] == ["swift", "tee"])
        #expect(result[.attribute] == ["--configuration"])
    }

    @Test func shellVariablesAndPrompt() {
        let result = kinds("$ echo ${USER} $1", .shell)
        #expect(result[.variable] == ["${USER}", "$1"])
        #expect(result[.function] == ["echo"])
    }

    @Test func noLanguageIsOnePlainToken() {
        #expect(SyntaxHighlighter.tokens(for: "anything", language: nil) == [CodeToken(.plain, "anything")])
        #expect(SyntaxHighlighter.tokens(for: "", language: nil).isEmpty)
    }
}
