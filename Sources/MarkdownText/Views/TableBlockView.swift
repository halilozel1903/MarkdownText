import SwiftUI

/// A GitHub Flavored Markdown table in a horizontal scroll view: columns are as wide as their widest cell, so a
/// wide table scrolls instead of squeezing its text.
struct TableBlockView: View {
    let table: MarkdownTable

    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownBaseURL) private var baseURL
    @Environment(\.markdownTextColor) private var textColorOverride
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(0..<table.columnCount, id: \.self) { column in
                        cell(table.header[column], column: column, isHeader: true, row: -1)
                    }
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(0..<table.columnCount, id: \.self) { column in
                            cell(row[column], column: column, isHeader: false, row: rowIndex)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(theme.tableBorder, lineWidth: 1)
            }
            .padding(1)
        }
        .scrollIndicators(.hidden)
        // Size to the content's height, also outside a vertical scroll view.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func cell(_ content: [MarkdownInline], column: Int, isHeader: Bool, row: Int) -> some View {
        let font = isHeader ? theme.tableHeaderFont : theme.bodyFont
        let renderer = InlineRenderer(theme: theme, baseURL: baseURL, textColor: textColorOverride ?? theme.textColor)
        let alignment = Self.alignment(table.alignments[column])
        let background: Color = isHeader ? theme.tableHeaderBackground : (row % 2 == 1 ? theme.tableStripeBackground : .clear)
        return Text(renderer.attributedString(content, font: font))
            .font(font)
            .tint(theme.linkColor)
            .multilineTextAlignment(Self.textAlignment(table.alignments[column]))
            .fixedSize()
            .padding(.horizontal, 12 * scale)
            .padding(.vertical, 8 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .background(background)
            .overlay {
                Rectangle()
                    .strokeBorder(theme.tableBorder, lineWidth: 0.5)
            }
    }

    private static func alignment(_ alignment: MarkdownTableAlignment) -> Alignment {
        switch alignment {
        case .none, .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private static func textAlignment(_ alignment: MarkdownTableAlignment) -> TextAlignment {
        switch alignment {
        case .none, .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}
