import Foundation
import SwiftUI

/// Scenes used by CI to capture the README screenshots. Launch with `-screenshot <scene>`; normal launches are
/// unaffected.
///
/// MarkdownText is a UI library, so the scenes render the example app's bundled demo documents (generic sample
/// text about the library, see ``DemoDocuments``) and its bundled illustration; nothing is loaded from the
/// network. Each scene writes its ready marker only once it is on screen.
enum ScreenshotScene: String {
    /// iPhone: the top of the guide document, light mode, default theme.
    case document
    /// iPhone: the code samples document, dark mode, GitHub theme.
    case code
    /// Mac: the live editor with its preview, light mode, docs theme.
    case editor

    /// The scene this launch asked for. A `mac-` or `iphone-` prefix is accepted too.
    static var current: ScreenshotScene? {
        guard var name = argument(after: "-screenshot") else { return nil }
        for prefix in ["mac-", "iphone-"] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }
        return ScreenshotScene(rawValue: name)
    }

    /// Where the ready marker goes: `-screenshot-marker <path>` (the Mac script passes one), or
    /// `tmp/screenshot-ready` in the app's container (what the iPhone script watches).
    static var markerURL: URL {
        if let path = argument(after: "-screenshot-marker") {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("screenshot-ready")
    }

    /// Mac only: `-render-screenshot <file>` asks the app to draw its window into a PNG itself once ready, the
    /// fallback when `screencapture` cannot capture the window.
    static var renderPath: String? {
        argument(after: "-render-screenshot")
    }

    private static func argument(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    /// The iPhone tab the scene opens.
    var tab: DemoTab {
        switch self {
        case .document: .guide
        case .code: .code
        case .editor: .editor
        }
    }

    var theme: ThemeChoice {
        switch self {
        case .document: .standard
        case .code: .github
        case .editor: .docs
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .document, .editor: .light
        case .code: .dark
        }
    }
}

extension View {
    /// Tells the screenshot scripts that the scene is on screen by writing the ready marker once `isReady` is true
    /// and the bundled image has had time to load and the layout to settle.
    func signalsScreenshotReady(_ scene: ScreenshotScene?, when isReady: Bool) -> some View {
        task(id: isReady) {
            guard let scene, isReady else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            do {
                try scene.rawValue.write(to: ScreenshotScene.markerURL, atomically: true, encoding: .utf8)
                print("Screenshot scene \(scene.rawValue) is ready")
            } catch {
                print("Could not write the screenshot marker: \(error)")
                return
            }
            #if os(macOS)
            await MainActor.run {
                ScreenshotWindowCoordinator.shared.sceneIsReady()
            }
            #endif
        }
    }
}
