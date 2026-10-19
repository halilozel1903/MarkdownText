import MarkdownText
import SwiftUI

/// The built-in themes, for the theme pickers of the demo.
enum ThemeChoice: String, CaseIterable, Identifiable {
    case standard
    case github
    case docs

    var id: Self { self }

    var title: String {
        switch self {
        case .standard: "Default"
        case .github: "GitHub"
        case .docs: "Docs"
        }
    }

    var theme: MarkdownTheme {
        switch self {
        case .standard: .default
        case .github: .github
        case .docs: .docs
        }
    }
}

/// The tabs of the iPhone demo.
enum DemoTab: Hashable {
    case guide
    case code
    case editor
}
