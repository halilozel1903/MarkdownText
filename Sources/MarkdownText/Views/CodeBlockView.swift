import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A code block: a header with the language and a copy button, and the highlighted code in a horizontal scroll
/// view so long lines never wrap.
struct CodeBlockView: View {
    let language: String?
    let code: String

    @Environment(\.markdownTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                header
                Rectangle()
                    .fill(theme.codeBlockBorder)
                    .frame(height: 1)
            }
            ScrollView(.horizontal) {
                Text(Self.highlighted(code, language: language, theme: theme))
                    .font(theme.codeFont)
                    .lineSpacing(2)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.horizontal, 14 * scale)
                    .padding(.vertical, 12 * scale)
            }
            .scrollIndicators(.hidden)
            // Size to the content's height, also outside a vertical scroll view.
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.codeBlockBackground, in: RoundedRectangle(cornerRadius: theme.codeBlockCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: theme.codeBlockCornerRadius)
                .strokeBorder(theme.codeBlockBorder, lineWidth: 1)
        }
    }

    private var showsHeader: Bool {
        theme.showsCodeCopyButton || (theme.showsCodeLanguage && languageName != nil)
    }

    private var languageName: String? {
        guard let language else { return nil }
        return CodeLanguage(infoString: language)?.displayName ?? language
    }

    private var header: some View {
        HStack(spacing: 8) {
            if theme.showsCodeLanguage, let languageName {
                Text(languageName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondaryTextColor)
            }
            Spacer(minLength: 8)
            if theme.showsCodeCopyButton {
                Button(action: copy) {
                    Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isCopied ? theme.taskCheckedColor : theme.secondaryTextColor)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isCopied ? "Copied" : "Copy code")
            }
        }
        .padding(.horizontal, 14 * scale)
        .padding(.vertical, 8 * scale)
    }

    private func copy() {
        Self.copyToPasteboard(code)
        isCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            isCopied = false
        }
    }

    static func copyToPasteboard(_ text: String) {
        #if os(iOS) || os(visionOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    /// The code as colored runs, using the theme's syntax colors.
    static func highlighted(_ code: String, language: String?, theme: MarkdownTheme) -> AttributedString {
        let tokens = SyntaxHighlighter.tokens(for: code, language: CodeLanguage(infoString: language))
        var result = AttributedString()
        for token in tokens {
            var run = AttributedString(token.text)
            run[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = theme.codeColors.color(for: token.kind)
            result += run
        }
        return result
    }
}
