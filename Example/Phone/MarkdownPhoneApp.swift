import MarkdownText
import SwiftUI

/// The MarkdownText demo for iPhone: the bundled guide, a page of highlighted code samples and a small editor with
/// a preview. A theme menu switches between the built-in themes.
@main
struct MarkdownPhoneApp: App {
    var body: some Scene {
        WindowGroup {
            PhoneRootView(scene: ScreenshotScene.current)
        }
    }
}

struct PhoneRootView: View {
    let scene: ScreenshotScene?

    @State private var tab: DemoTab
    @State private var theme: ThemeChoice

    init(scene: ScreenshotScene?) {
        self.scene = scene
        _tab = State(initialValue: scene?.tab ?? .guide)
        _theme = State(initialValue: scene?.theme ?? .standard)
    }

    var body: some View {
        TabView(selection: $tab) {
            DocumentScreen(title: "Guide", markdown: DemoDocuments.guide, theme: $theme, scene: scene == .document ? scene : nil)
                .tabItem { Label("Guide", systemImage: "book") }
                .tag(DemoTab.guide)
            DocumentScreen(title: "Code Samples", markdown: DemoDocuments.codeSamples, theme: $theme, scene: scene == .code ? scene : nil)
                .tabItem { Label("Code", systemImage: "chevron.left.forwardslash.chevron.right") }
                .tag(DemoTab.code)
            PhoneEditorScreen(theme: $theme)
                .tabItem { Label("Editor", systemImage: "square.and.pencil") }
                .tag(DemoTab.editor)
        }
        .preferredColorScheme(scene?.colorScheme)
        // Link handling: the guide's link to code-samples.md switches tabs; other links open as usual.
        .environment(\.openURL, OpenURLAction { url in
            if url.lastPathComponent == "code-samples.md" {
                tab = .code
                return .handled
            }
            return .systemAction
        })
    }
}

/// Inline titles with a visible bar: iOS 26 can drop a large title while a scroll view settles under it.
private struct InlineNavigation: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

extension View {
    func inlineNavigation(_ title: String) -> some View {
        modifier(InlineNavigation(title: title))
    }
}

struct ThemeMenu: View {
    @Binding var theme: ThemeChoice

    var body: some View {
        Menu {
            Picker("Theme", selection: $theme) {
                ForEach(ThemeChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
        } label: {
            Label("Theme", systemImage: "paintpalette")
        }
    }
}

// MARK: - Documents

struct DocumentScreen: View {
    let title: String
    let markdown: String
    @Binding var theme: ThemeChoice
    let scene: ScreenshotScene?

    var body: some View {
        NavigationStack {
            ScrollView {
                MarkdownText(markdown, baseURL: DemoDocuments.baseURL)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }
            .markdownTheme(theme.theme)
            .inlineNavigation(title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ThemeMenu(theme: $theme)
                }
            }
        }
        .signalsScreenshotReady(scene, when: true)
    }
}

// MARK: - Editor

struct PhoneEditorScreen: View {
    @Binding var theme: ThemeChoice

    @State private var source = DemoDocuments.starter
    @State private var mode = Mode.write

    enum Mode: String, CaseIterable, Identifiable {
        case write = "Write"
        case preview = "Preview"
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                switch mode {
                case .write:
                    TextEditor(text: $source)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, 12)
                case .preview:
                    ScrollView {
                        MarkdownText(source, baseURL: DemoDocuments.baseURL)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                    }
                }
            }
            .markdownTheme(theme.theme)
            .inlineNavigation("Editor")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Guide") { source = DemoDocuments.guide }
                        Button("Code Samples") { source = DemoDocuments.codeSamples }
                        Button("Blank") { source = DemoDocuments.starter }
                    } label: {
                        Label("Load Sample", systemImage: "doc.text")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ThemeMenu(theme: $theme)
                }
            }
        }
    }
}
