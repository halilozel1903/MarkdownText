import MarkdownText
import SwiftUI

/// The MarkdownText demo for the Mac: a live editor, Markdown source on the left and the rendered preview on the
/// right, with the theme and a bundled sample document picked in the toolbar. There is no sidebar; both panes
/// have opaque backgrounds.
@main
struct MarkdownMacApp: App {
    var body: some Scene {
        WindowGroup("MarkdownText Editor") {
            MacEditorView(scene: ScreenshotScene.current)
                .modifier(MacWindowSize(scene: ScreenshotScene.current))
        }
        .defaultSize(width: MacWindowSize.screenshotSize.width, height: MacWindowSize.screenshotSize.height)
        .windowResizability(ScreenshotScene.current == nil ? .contentMinSize : .contentSize)
    }
}

/// A fixed size for screenshots, so every capture has the same frame; a minimum size otherwise.
struct MacWindowSize: ViewModifier {
    static let screenshotSize = CGSize(width: 1180, height: 760)
    let scene: ScreenshotScene?

    func body(content: Content) -> some View {
        if let scene {
            content
                .frame(width: Self.screenshotSize.width, height: Self.screenshotSize.height)
                .preferredColorScheme(scene.colorScheme)
                .background(ScreenshotWindow(colorScheme: scene.colorScheme))
        } else {
            content
                .frame(minWidth: 760, minHeight: 480)
        }
    }
}

enum DemoSample: String, CaseIterable, Identifiable {
    case guide = "Guide"
    case code = "Code Samples"
    case blank = "Blank"

    var id: Self { self }

    var markdown: String {
        switch self {
        case .guide: DemoDocuments.guide
        case .code: DemoDocuments.codeSamples
        case .blank: DemoDocuments.starter
        }
    }
}

struct MacEditorView: View {
    let scene: ScreenshotScene?

    @State private var source: String
    @State private var sample: DemoSample
    @State private var theme: ThemeChoice

    init(scene: ScreenshotScene?) {
        self.scene = scene
        _source = State(initialValue: DemoDocuments.guide)
        _sample = State(initialValue: .guide)
        _theme = State(initialValue: scene?.theme ?? .github)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                PaneHeader(title: "Markdown", detail: "\(source.split(separator: "\n", omittingEmptySubsequences: false).count) lines")
                TextEditor(text: $source)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))

            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)

            VStack(spacing: 0) {
                PaneHeader(title: "Preview", detail: "\(theme.title) theme")
                ScrollView {
                    MarkdownText(source, baseURL: DemoDocuments.baseURL)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 20)
                }
            }
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .markdownTheme(theme.theme)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("MarkdownText Editor")
        .navigationSubtitle(sample.rawValue)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Theme", selection: $theme) {
                    ForEach(ThemeChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            ToolbarItem {
                Menu {
                    ForEach(DemoSample.allCases) { item in
                        Button(item.rawValue) {
                            sample = item
                            source = item.markdown
                        }
                    }
                } label: {
                    Label("Load Sample", systemImage: "doc.text")
                }
                .help("Replace the text with a bundled sample document")
            }
        }
        .signalsScreenshotReady(scene, when: true)
    }
}

struct PaneHeader: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
