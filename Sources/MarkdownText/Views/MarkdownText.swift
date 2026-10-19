import SwiftUI

/// Renders Markdown with native SwiftUI views.
///
/// ```swift
/// ScrollView {
///     MarkdownText(readme, baseURL: repositoryURL)
///         .padding()
/// }
/// .markdownTheme(.github)
/// ```
///
/// - Text is selectable and links open through the environment's `openURL` action, so an `OpenURLAction` set
///   with `.environment(\.openURL, …)` decides what a tap does.
/// - Code blocks are highlighted for Swift, Kotlin, JSON and shell, scroll horizontally and have a copy button.
/// - Tables scroll horizontally when they are wider than the view.
/// - Images load asynchronously; relative image and link URLs resolve against `baseURL`, which may be a file
///   URL such as `Bundle.main.resourceURL` for bundled images.
/// - Fonts follow Dynamic Type; the look comes from ``MarkdownTheme`` (see ``SwiftUI/View/markdownTheme(_:)``).
///
/// `MarkdownText` lays out the whole document in a vertical stack and does not scroll; put it in a `ScrollView`
/// for long documents.
public struct MarkdownText: View {
    /// The parsed document.
    public let document: MarkdownDocument
    /// The URL that relative links and images resolve against.
    public let baseURL: URL?

    /// Parses `markdown` and renders it.
    public init(_ markdown: String, baseURL: URL? = nil) {
        self.document = MarkdownDocument(parsing: markdown)
        self.baseURL = baseURL
    }

    /// Renders a document parsed earlier, for example off the main thread.
    public init(_ document: MarkdownDocument, baseURL: URL? = nil) {
        self.document = document
        self.baseURL = baseURL
    }

    public var body: some View {
        BlockSequence(blocks: document.blocks)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .environment(\.markdownBaseURL, baseURL)
    }
}

// MARK: - Internal environment

private struct MarkdownBaseURLKey: EnvironmentKey {
    static let defaultValue: URL? = nil
}

private struct MarkdownTextColorKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

private struct MarkdownListDepthKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    /// The base URL of the ``MarkdownText`` being rendered.
    var markdownBaseURL: URL? {
        get { self[MarkdownBaseURLKey.self] }
        set { self[MarkdownBaseURLKey.self] = newValue }
    }

    /// Replaces the theme's text color, inside block quotes.
    var markdownTextColor: Color? {
        get { self[MarkdownTextColorKey.self] }
        set { self[MarkdownTextColorKey.self] = newValue }
    }

    /// How deeply lists are nested, for the bullet style.
    var markdownListDepth: Int {
        get { self[MarkdownListDepthKey.self] }
        set { self[MarkdownListDepthKey.self] = newValue }
    }
}

/// Resolves link and image destinations.
enum MarkdownURL {
    /// Resolves a link or image destination against a base URL.
    static func resolve(_ destination: String, baseURL: URL?) -> URL? {
        let trimmed = destination.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let url = URL(string: trimmed, relativeTo: baseURL)
            ?? trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
                .flatMap { URL(string: $0, relativeTo: baseURL) }
        return url?.absoluteURL
    }
}
