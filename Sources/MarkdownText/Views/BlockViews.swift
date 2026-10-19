import SwiftUI

/// Blocks stacked vertically with the theme's spacing.
struct BlockSequence: View {
    let blocks: [MarkdownBlock]
    /// Spacing in place of the theme's block spacing, for tight list items.
    var spacing: CGFloat?

    @Environment(\.markdownTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: (spacing ?? theme.blockSpacing) * scale) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                BlockView(block: block)
                    .padding(.top, index > 0 && block.isHeading ? theme.headingTopSpacing * scale : 0)
            }
        }
    }
}

extension MarkdownBlock {
    var isHeading: Bool {
        if case .heading = self { return true }
        return false
    }
}

/// One block.
struct BlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case let .heading(level, content):
            HeadingView(level: level, content: content)
        case let .paragraph(content):
            ParagraphView(content: content)
        case let .blockQuote(blocks):
            BlockQuoteView(blocks: blocks)
        case let .list(list):
            ListBlockView(list: list)
        case let .codeBlock(language, code):
            CodeBlockView(language: language, code: code)
        case let .table(table):
            TableBlockView(table: table)
        case .thematicBreak:
            ThematicBreakView()
        }
    }
}

// MARK: - Headings and paragraphs

struct HeadingView: View {
    let level: Int
    let content: [MarkdownInline]

    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownBaseURL) private var baseURL

    var body: some View {
        let font = theme.headingFont(level: level)
        let renderer = InlineRenderer(theme: theme, baseURL: baseURL, textColor: theme.headingColor)
        VStack(alignment: .leading, spacing: 6) {
            Text(renderer.attributedString(content, font: font))
                .font(font)
                .tint(theme.linkColor)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHeading(Self.accessibilityLevel(level))
            if level <= theme.headingDividerMaxLevel {
                Rectangle()
                    .fill(theme.dividerColor)
                    .frame(height: 1)
            }
        }
    }

    static func accessibilityLevel(_ level: Int) -> AccessibilityHeadingLevel {
        switch level {
        case 1: .h1
        case 2: .h2
        case 3: .h3
        case 4: .h4
        case 5: .h5
        default: .h6
        }
    }
}

struct ParagraphView: View {
    let content: [MarkdownInline]

    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownBaseURL) private var baseURL
    @Environment(\.markdownTextColor) private var textColorOverride

    var body: some View {
        if let images = MarkdownImageItem.imageOnly(content) {
            ImageParagraphView(items: images)
        } else {
            let renderer = InlineRenderer(theme: theme, baseURL: baseURL, textColor: textColorOverride ?? theme.textColor)
            let text = renderer.attributedString(content, font: theme.bodyFont)
            if !text.characters.isEmpty {
                Text(text)
                    .font(theme.bodyFont)
                    .lineSpacing(theme.lineSpacing)
                    .tint(theme.linkColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Block quotes

struct BlockQuoteView: View {
    let blocks: [MarkdownBlock]

    @Environment(\.markdownTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let hasBackground = theme.blockQuoteBackground != .clear
        BlockSequence(blocks: blocks)
            .padding(.vertical, hasBackground ? 10 * scale : 2)
            .padding(.leading, 16 * scale)
            .padding(.trailing, hasBackground ? 12 * scale : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.blockQuoteBar)
                    .frame(width: 4)
            }
            .background(theme.blockQuoteBackground, in: RoundedRectangle(cornerRadius: 6))
            .environment(\.markdownTextColor, theme.blockQuoteTextColor)
    }
}

// MARK: - Lists

struct ListBlockView: View {
    let list: MarkdownList

    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownListDepth) private var depth
    @Environment(\.markdownTextColor) private var textColorOverride
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: (list.isTight ? theme.listItemSpacing : theme.blockSpacing) * scale) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8 * scale) {
                    marker(index: index, item: item)
                        .frame(minWidth: markerWidth, alignment: .trailing)
                    BlockSequence(blocks: item.blocks, spacing: list.isTight ? theme.listItemSpacing : nil)
                }
            }
        }
        .environment(\.markdownListDepth, depth + 1)
    }

    private var markerWidth: CGFloat {
        if list.items.contains(where: \.isTask) {
            return 20 * scale
        }
        guard list.isOrdered else { return 12 * scale }
        let digits = String(list.start + max(list.items.count - 1, 0)).count
        return CGFloat(digits * 9 + 8) * scale
    }

    @ViewBuilder
    private func marker(index: Int, item: MarkdownListItem) -> some View {
        if let isChecked = item.isChecked {
            Text(Image(systemName: isChecked ? "checkmark.square.fill" : "square"))
                .font(theme.bodyFont)
                .foregroundStyle(isChecked ? theme.taskCheckedColor : theme.secondaryTextColor)
                .accessibilityLabel(isChecked ? "Completed" : "Not completed")
        } else if list.isOrdered {
            Text(verbatim: "\(list.start + index).")
                .font(theme.bodyFont)
                .monospacedDigit()
                .foregroundStyle(textColorOverride ?? theme.textColor)
        } else {
            Text(Self.bullets[depth % Self.bullets.count])
                .font(theme.bodyFont)
                .foregroundStyle(theme.secondaryTextColor)
                .accessibilityHidden(true)
        }
    }

    private static let bullets = ["•", "◦", "▪︎"]
}

// MARK: - Thematic breaks

struct ThematicBreakView: View {
    @Environment(\.markdownTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.dividerColor)
            .frame(height: 1)
            .padding(.vertical, 4)
            .accessibilityHidden(true)
    }
}
