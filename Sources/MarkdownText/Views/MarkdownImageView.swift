import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

/// An image of a paragraph that holds only images (a screenshot, or a row of badges), possibly linked.
struct MarkdownImageItem: Hashable {
    var source: String
    var alt: String
    var link: String?

    /// The images of a paragraph made only of images, linked images and whitespace; `nil` for any other paragraph.
    static func imageOnly(_ inlines: [MarkdownInline]) -> [MarkdownImageItem]? {
        var items: [MarkdownImageItem] = []
        for inline in inlines {
            switch inline {
            case let .image(source, _, alt):
                items.append(MarkdownImageItem(source: source, alt: alt.plainText, link: nil))
            case let .link(destination, _, children):
                guard let linked = imageOnly(children) else { return nil }
                items += linked.map { MarkdownImageItem(source: $0.source, alt: $0.alt, link: destination) }
            case .softBreak, .lineBreak:
                continue
            case let .text(text) where text.isBlank:
                continue
            default:
                return nil
            }
        }
        return items.isEmpty ? nil : items
    }
}

/// One image fills the width (never wider than its natural size); several flow in rows, like badges.
struct ImageParagraphView: View {
    let items: [MarkdownImageItem]

    var body: some View {
        if items.count == 1, let item = items.first {
            LinkedImage(item: item)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            FlowLayout(spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    LinkedImage(item: item)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// An image that opens its link, if any, with the environment's `openURL` action.
struct LinkedImage: View {
    let item: MarkdownImageItem

    @Environment(\.markdownBaseURL) private var baseURL
    @Environment(\.openURL) private var openURL

    var body: some View {
        let image = MarkdownImageView(url: MarkdownURL.resolve(item.source, baseURL: baseURL), alt: item.alt)
        if let link = item.link.flatMap({ MarkdownURL.resolve($0, baseURL: baseURL) }) {
            Button {
                openURL(link)
            } label: {
                image
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isLink)
        } else {
            image
        }
    }
}

/// Loads an image asynchronously: remote URLs with `URLSession`, file URLs (bundled resources) from disk. Shows a
/// placeholder while loading and the image's description when it cannot be loaded or decoded (SVG badges, for
/// example).
struct MarkdownImageView: View {
    let url: URL?
    let alt: String

    @Environment(\.markdownTheme) private var theme
    @State private var phase = Phase.loading

    private enum Phase {
        case loading
        case loaded(PlatformImage)
        case failed
    }

    var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(alt.isEmpty ? "Image" : alt)
            .accessibilityAddTraits(.isImage)
            .task(id: url) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case let .loaded(image):
            Image(platformImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: image.size.width)
                .clipShape(RoundedRectangle(cornerRadius: image.size.height > 60 ? theme.imageCornerRadius : 0))
        case .loading:
            RoundedRectangle(cornerRadius: theme.imageCornerRadius)
                .fill(theme.codeBlockBackground)
                .frame(maxWidth: 320)
                .frame(height: 120)
                .overlay { ProgressView() }
        case .failed:
            Label(alt.isEmpty ? "Image" : alt, systemImage: "photo")
                .font(.footnote)
                .foregroundStyle(theme.secondaryTextColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(theme.inlineCodeBackground, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func load() async {
        guard let url else {
            phase = .failed
            return
        }
        if let cached = ImageCache.shared.image(for: url) {
            phase = .loaded(cached)
            return
        }
        phase = .loading
        do {
            let data: Data
            if url.isFileURL {
                data = try Data(contentsOf: url)
            } else {
                let (body, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                data = body
            }
            guard let image = PlatformImage(data: data) else {
                phase = .failed
                return
            }
            ImageCache.shared.insert(image, for: url)
            phase = .loaded(image)
        } catch {
            if !Task.isCancelled {
                phase = .failed
            }
        }
    }
}

/// Decoded images by URL, shared by every ``MarkdownText``.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSURL, PlatformImage>()

    init() {
        cache.countLimit = 100
    }

    func image(for url: URL) -> PlatformImage? {
        cache.object(forKey: url as NSURL)
    }

    func insert(_ image: PlatformImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

/// Places views in rows, wrapping to a new row when the width runs out.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width.map { min(width, $0) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            if size.width > maxWidth {
                size = subviews[index].sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            }
            if !current.items.isEmpty, current.width + spacing + size.width > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.width += (current.items.isEmpty ? 0 : spacing) + size.width
            current.height = max(current.height, size.height)
            current.items.append((index, size))
        }
        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
