import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The look of rendered Markdown: fonts, colors and spacing.
///
/// Start from a built-in theme and change what you need:
///
/// ```swift
/// MarkdownText(readme)
///     .markdownTheme(.github.with {
///         $0.linkColor = .pink
///         $0.blockSpacing = 20
///     })
/// ```
///
/// Fonts are built from text styles (`.body`, `.title`, …), so they follow Dynamic Type; spacing scales with it
/// too. Colors adapt to light and dark mode.
public struct MarkdownTheme {
    // MARK: Fonts

    /// The font of paragraphs, list items, block quotes and table cells.
    public var bodyFont: Font = .body
    /// Heading fonts for levels 1 to 6. Missing levels use the last font.
    public var headingFonts: [Font] = [
        .system(.title, design: .default, weight: .bold),
        .system(.title2, design: .default, weight: .bold),
        .system(.title3, design: .default, weight: .semibold),
        .system(.headline, design: .default, weight: .semibold),
        .system(.subheadline, design: .default, weight: .semibold),
        .system(.footnote, design: .default, weight: .semibold),
    ]
    /// The font of code blocks.
    public var codeFont: Font = .system(.callout, design: .monospaced)
    /// The font of table header cells.
    public var tableHeaderFont: Font = .body.weight(.semibold)

    // MARK: Text colors

    public var textColor: Color = .primary
    public var secondaryTextColor: Color = .secondary
    public var headingColor: Color = .primary
    public var linkColor: Color = .accentColor
    /// Underline links in addition to coloring them.
    public var underlinesLinks = false

    // MARK: Code

    public var inlineCodeColor: Color = Color(light: 0xC41A5B, dark: 0xFF7AB2)
    public var inlineCodeBackground: Color = Color(light: 0xEFEFF2, dark: 0x2C2C30)
    public var codeBlockBackground: Color = Color(light: 0xF5F5F7, dark: 0x1C1C1F)
    public var codeBlockBorder: Color = Color(light: 0xE2E2E6, dark: 0x343438)
    public var codeBlockCornerRadius: CGFloat = 10
    /// Syntax colors of highlighted code blocks.
    public var codeColors: MarkdownCodeColors = .xcode
    /// Show a copy button in the header of code blocks.
    public var showsCodeCopyButton = true
    /// Show the language of code blocks in their header.
    public var showsCodeLanguage = true

    // MARK: Blocks

    public var blockQuoteBar: Color = Color(light: 0xD0D0D6, dark: 0x4A4A50)
    public var blockQuoteTextColor: Color = .secondary
    public var blockQuoteBackground: Color = .clear
    public var tableBorder: Color = Color(light: 0xDADADF, dark: 0x3A3A3F)
    public var tableHeaderBackground: Color = Color(light: 0xF2F2F5, dark: 0x232327)
    public var tableStripeBackground: Color = Color(light: 0xFAFAFB, dark: 0x19191C)
    public var dividerColor: Color = Color(light: 0xDCDCE0, dark: 0x3A3A3F)
    public var taskCheckedColor: Color = .accentColor
    /// Headings up to this level get a divider below them, as on GitHub. `0` for none.
    public var headingDividerMaxLevel = 0
    public var imageCornerRadius: CGFloat = 8

    // MARK: Spacing

    /// Space between blocks, in points at the default text size.
    public var blockSpacing: CGFloat = 14
    /// Extra space above headings that follow other blocks.
    public var headingTopSpacing: CGFloat = 8
    /// Space between the items of a tight list.
    public var listItemSpacing: CGFloat = 6
    /// Extra space between the lines of a paragraph.
    public var lineSpacing: CGFloat = 2

    /// The default theme, a variant of `.default`: system fonts, the app's accent color for links, Xcode-like
    /// code colors.
    public init() {}

    /// A copy of the theme with changes applied.
    public func with(_ changes: (inout MarkdownTheme) -> Void) -> MarkdownTheme {
        var theme = self
        changes(&theme)
        return theme
    }

    /// The font for a heading level, 1 to 6.
    public func headingFont(level: Int) -> Font {
        guard !headingFonts.isEmpty else { return bodyFont.bold() }
        return headingFonts[min(max(level, 1), headingFonts.count) - 1]
    }
}

extension MarkdownTheme {
    /// System fonts, the app's accent color for links and Xcode-like code colors.
    public static var `default`: MarkdownTheme { MarkdownTheme() }

    /// Looks like a README on GitHub: dividers under first and second level headings, GitHub's link, code and
    /// quote colors, and its syntax colors.
    public static var github: MarkdownTheme {
        MarkdownTheme().with {
            $0.headingFonts = [
                .system(.title, design: .default, weight: .semibold),
                .system(.title2, design: .default, weight: .semibold),
                .system(.title3, design: .default, weight: .semibold),
                .system(.headline, design: .default, weight: .semibold),
                .system(.subheadline, design: .default, weight: .semibold),
                .system(.subheadline, design: .default, weight: .semibold),
            ]
            $0.textColor = Color(light: 0x1F2328, dark: 0xF0F6FC)
            $0.headingColor = Color(light: 0x1F2328, dark: 0xF0F6FC)
            $0.secondaryTextColor = Color(light: 0x59636E, dark: 0x9198A1)
            $0.linkColor = Color(light: 0x0969DA, dark: 0x4493F8)
            $0.inlineCodeColor = Color(light: 0x1F2328, dark: 0xF0F6FC)
            $0.inlineCodeBackground = Color(light: 0xEFF1F3, dark: 0x262C36)
            $0.codeBlockBackground = Color(light: 0xF6F8FA, dark: 0x151B23)
            $0.codeBlockBorder = Color(light: 0xD1D9E0, dark: 0x3D444D)
            $0.codeBlockCornerRadius = 6
            $0.codeColors = .github
            $0.blockQuoteBar = Color(light: 0xD1D9E0, dark: 0x3D444D)
            $0.blockQuoteTextColor = Color(light: 0x59636E, dark: 0x9198A1)
            $0.tableBorder = Color(light: 0xD1D9E0, dark: 0x3D444D)
            $0.tableHeaderBackground = Color(light: 0xF6F8FA, dark: 0x151B23)
            $0.tableStripeBackground = Color(light: 0xF6F8FA, dark: 0x151B23)
            $0.dividerColor = Color(light: 0xD1D9E0, dark: 0x3D444D)
            $0.taskCheckedColor = Color(light: 0x1F883D, dark: 0x3FB950)
            $0.headingDividerMaxLevel = 2
            $0.imageCornerRadius = 6
            $0.blockSpacing = 16
        }
    }

    /// A reading theme for documentation: serif body text with roomier lines, rounded headings in an indigo
    /// accent, tinted quote callouts and a warm code palette.
    public static var docs: MarkdownTheme {
        MarkdownTheme().with {
            $0.bodyFont = .system(.body, design: .serif)
            $0.headingFonts = [
                .system(.largeTitle, design: .rounded, weight: .bold),
                .system(.title2, design: .rounded, weight: .bold),
                .system(.title3, design: .rounded, weight: .semibold),
                .system(.headline, design: .rounded, weight: .semibold),
                .system(.subheadline, design: .rounded, weight: .semibold),
                .system(.footnote, design: .rounded, weight: .semibold),
            ]
            $0.tableHeaderFont = .system(.body, design: .rounded, weight: .semibold)
            $0.textColor = Color(light: 0x2B2A33, dark: 0xE8E6F0)
            $0.headingColor = Color(light: 0x3B2F8F, dark: 0xB9AEFF)
            $0.secondaryTextColor = Color(light: 0x6B6878, dark: 0xA3A0B2)
            $0.linkColor = Color(light: 0x5B4BDB, dark: 0xA99BFF)
            $0.underlinesLinks = true
            $0.inlineCodeColor = Color(light: 0x8A3B12, dark: 0xFFB37A)
            $0.inlineCodeBackground = Color(light: 0xF6EFE7, dark: 0x2E2620)
            $0.codeBlockBackground = Color(light: 0xFBF8F3, dark: 0x1E1A17)
            $0.codeBlockBorder = Color(light: 0xEADFD0, dark: 0x3A322B)
            $0.codeBlockCornerRadius = 12
            $0.codeColors = .warm
            $0.blockQuoteBar = Color(light: 0x7C6CF0, dark: 0x8F82FF)
            $0.blockQuoteTextColor = Color(light: 0x3E3B4C, dark: 0xD6D3E3)
            $0.blockQuoteBackground = Color(light: 0xF3F1FF, dark: 0x221F35)
            $0.tableBorder = Color(light: 0xE2DEF2, dark: 0x3A3650)
            $0.tableHeaderBackground = Color(light: 0xF3F1FF, dark: 0x221F35)
            $0.tableStripeBackground = Color(light: 0xFAF9FF, dark: 0x1A1828)
            $0.dividerColor = Color(light: 0xE2DEF2, dark: 0x3A3650)
            $0.taskCheckedColor = Color(light: 0x5B4BDB, dark: 0xA99BFF)
            $0.imageCornerRadius = 14
            $0.blockSpacing = 16
            $0.headingTopSpacing = 12
            $0.lineSpacing = 5
        }
    }
}

/// The syntax colors of highlighted code blocks.
public struct MarkdownCodeColors {
    public var plain: Color
    public var keyword: Color
    public var string: Color
    public var number: Color
    public var comment: Color
    public var type: Color
    public var function: Color
    public var attribute: Color
    public var property: Color
    public var variable: Color
    public var literal: Color

    public init(
        plain: Color, keyword: Color, string: Color, number: Color, comment: Color, type: Color,
        function: Color, attribute: Color, property: Color, variable: Color, literal: Color
    ) {
        self.plain = plain
        self.keyword = keyword
        self.string = string
        self.number = number
        self.comment = comment
        self.type = type
        self.function = function
        self.attribute = attribute
        self.property = property
        self.variable = variable
        self.literal = literal
    }

    /// The color for a kind of token.
    public func color(for kind: CodeTokenKind) -> Color {
        switch kind {
        case .plain: plain
        case .keyword: keyword
        case .string: string
        case .number: number
        case .comment: comment
        case .type: type
        case .function: function
        case .attribute: attribute
        case .property: property
        case .variable: variable
        case .literal: literal
        }
    }

    /// Close to Xcode's default light and dark presentations.
    public static var xcode: MarkdownCodeColors {
        MarkdownCodeColors(
            plain: Color(light: 0x1D1D1F, dark: 0xE6E6E9),
            keyword: Color(light: 0xAD3DA4, dark: 0xFF7AB2),
            string: Color(light: 0xD12F1B, dark: 0xFF8170),
            number: Color(light: 0x272AD8, dark: 0xD9C97C),
            comment: Color(light: 0x707F8C, dark: 0x7F8C98),
            type: Color(light: 0x0B4F79, dark: 0x5DD8FF),
            function: Color(light: 0x326D74, dark: 0x67B7A4),
            attribute: Color(light: 0x947100, dark: 0xFFA14F),
            property: Color(light: 0x3E8087, dark: 0x6BDFFF),
            variable: Color(light: 0x0F68A0, dark: 0x41A1C0),
            literal: Color(light: 0xAD3DA4, dark: 0xFF7AB2)
        )
    }

    /// GitHub's syntax colors.
    public static var github: MarkdownCodeColors {
        MarkdownCodeColors(
            plain: Color(light: 0x1F2328, dark: 0xE6EDF3),
            keyword: Color(light: 0xCF222E, dark: 0xFF7B72),
            string: Color(light: 0x0A3069, dark: 0xA5D6FF),
            number: Color(light: 0x0550AE, dark: 0x79C0FF),
            comment: Color(light: 0x59636E, dark: 0x8B949E),
            type: Color(light: 0x953800, dark: 0xFFA657),
            function: Color(light: 0x8250DF, dark: 0xD2A8FF),
            attribute: Color(light: 0x0550AE, dark: 0x79C0FF),
            property: Color(light: 0x0550AE, dark: 0x7EE787),
            variable: Color(light: 0x953800, dark: 0xFFA657),
            literal: Color(light: 0x0550AE, dark: 0x79C0FF)
        )
    }

    /// Warm colors that sit on the docs theme's paper-like code blocks.
    public static var warm: MarkdownCodeColors {
        MarkdownCodeColors(
            plain: Color(light: 0x3B302A, dark: 0xEDE3D9),
            keyword: Color(light: 0x8E3FB5, dark: 0xD7A6FF),
            string: Color(light: 0x2F7A3B, dark: 0x9BDB8F),
            number: Color(light: 0xB35A00, dark: 0xFFB86B),
            comment: Color(light: 0x988A7E, dark: 0x8C8075),
            type: Color(light: 0x1F6E8C, dark: 0x7FCBEA),
            function: Color(light: 0x5B4BDB, dark: 0xB2A6FF),
            attribute: Color(light: 0xB0306A, dark: 0xFF8FC0),
            property: Color(light: 0x1F6E8C, dark: 0x7FCBEA),
            variable: Color(light: 0xB0306A, dark: 0xFF8FC0),
            literal: Color(light: 0xB35A00, dark: 0xFFB86B)
        )
    }
}

// MARK: - Environment

private struct MarkdownThemeKey: EnvironmentKey {
    static var defaultValue: MarkdownTheme { .default }
}

extension EnvironmentValues {
    /// The theme ``MarkdownText`` renders with.
    public var markdownTheme: MarkdownTheme {
        get { self[MarkdownThemeKey.self] }
        set { self[MarkdownThemeKey.self] = newValue }
    }
}

extension View {
    /// Sets the theme of ``MarkdownText`` views inside this view.
    public func markdownTheme(_ theme: MarkdownTheme) -> some View {
        environment(\.markdownTheme, theme)
    }
}

// MARK: - Adaptive colors

extension Color {
    /// A color with one value in light mode and another in dark mode, from `0xRRGGBB` values.
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        })
        #else
        self.init(red: Double((light >> 16) & 0xFF) / 255, green: Double((light >> 8) & 0xFF) / 255, blue: Double(light & 0xFF) / 255)
        #endif
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
#elseif canImport(AppKit)
private extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif
