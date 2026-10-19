import AppKit
import SwiftUI

/// Prepares the window of a screenshot scene: the scene's appearance, no state restoration, centered, the app in
/// front. Put it in the background of the window's content.
///
/// scripts/screenshots-mac.sh captures the window with `screencapture -l <window id>` once the app has written its
/// ready marker. When that is not possible, it relaunches with `-render-screenshot <file>` and the app draws the
/// window into a PNG itself (see ``ScreenshotRenderer``), also only once the scene is ready.
struct ScreenshotWindow: NSViewRepresentable {
    let colorScheme: ColorScheme

    func makeNSView(context: Context) -> NSView {
        ConfiguringView(appearance: NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua))
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ConfiguringView: NSView {
        private var isConfigured = false
        private let windowAppearance: NSAppearance?

        init(appearance: NSAppearance?) {
            windowAppearance = appearance
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !isConfigured else { return }
            isConfigured = true

            window.appearance = windowAppearance
            window.isRestorable = false
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate()
            ScreenshotWindowCoordinator.shared.windowAppeared(window)
        }
    }
}

/// Keeps the screenshot window in front, and renders it when asked to once the scene is ready.
@MainActor
final class ScreenshotWindowCoordinator {
    static let shared = ScreenshotWindowCoordinator()

    private var window: NSWindow?
    private var renderer: ScreenshotRenderer?

    func windowAppeared(_ window: NSWindow) {
        guard self.window == nil else { return }
        self.window = window
        Task {
            // Let SwiftUI size the window to its content before centering it.
            try? await Task.sleep(for: .milliseconds(600))
            window.center()
            window.makeKeyAndOrderFront(nil)
            for other in NSApplication.shared.windows where other !== window && other.isVisible {
                other.orderOut(nil)
            }
        }
    }

    /// Called after the ready marker is written: every result and image is on screen.
    func sceneIsReady() {
        guard let path = ScreenshotScene.renderPath, renderer == nil else { return }
        guard let window = window ?? NSApplication.shared.windows.first(where: \.isVisible) else {
            FileHandle.standardError.write(Data("Screenshot failed: no window to render\n".utf8))
            exit(1)
        }
        renderer = ScreenshotRenderer(window: window, path: path)
    }
}

/// The fallback: draws the window into a 2x bitmap with `cacheDisplay`, refuses a blank result, writes the PNG and
/// quits. Exits with status 1 on any failure so the CI script can give up.
@MainActor
final class ScreenshotRenderer {
    private let window: NSWindow

    init(window: NSWindow, path: String) {
        self.window = window
        Task {
            // The marker is written after the images settled; give AppKit a moment to draw the last frame.
            try? await Task.sleep(for: .seconds(1))
            self.render(to: path)
        }
    }

    private func render(to path: String) {
        // The frame view holds the title bar and toolbar as well as the content.
        guard let view = window.contentView?.superview ?? window.contentView else {
            return fail("The window has no content view")
        }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()

        let bounds = view.bounds
        let scale: CGFloat = 2
        guard bounds.width > 0, bounds.height > 0,
              let bitmap = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: Int(bounds.width * scale),
                  pixelsHigh: Int(bounds.height * scale),
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bytesPerRow: 0,
                  bitsPerPixel: 0
              )
        else { return fail("Could not create a bitmap for \(bounds)") }

        // The bitmap's size in points against its pixel size makes the view draw at 2x.
        bitmap.size = bounds.size
        view.cacheDisplay(in: bounds, to: bitmap)

        guard Self.distinctColorCount(in: bitmap) > 40 else {
            return fail("The rendered image is blank")
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            return fail("Could not encode the PNG")
        }
        do {
            try png.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            return fail("Could not write \(path): \(error.localizedDescription)")
        }
        print("Rendered \(path) (\(bitmap.pixelsWide)x\(bitmap.pixelsHigh), \(png.count) bytes)")
        exit(0)
    }

    /// Samples a grid of pixels. A blank or single-color image has only a handful of colors.
    private static func distinctColorCount(in bitmap: NSBitmapImageRep) -> Int {
        var colors = Set<UInt32>()
        let step = max(1, min(bitmap.pixelsWide, bitmap.pixelsHigh) / 60)
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: step) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: step) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                colors.insert(channel(color.redComponent) << 16 | channel(color.greenComponent) << 8 | channel(color.blueComponent))
            }
        }
        return colors.count
    }

    private static func channel(_ component: CGFloat) -> UInt32 {
        UInt32(min(255, max(0, (component * 255).rounded())))
    }

    private func fail(_ message: String) {
        FileHandle.standardError.write(Data("Screenshot failed: \(message)\n".utf8))
        exit(1)
    }
}
