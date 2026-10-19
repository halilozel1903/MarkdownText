import Foundation

/// The bundled demo documents. They are generic sample text written for this example app, about MarkdownText
/// itself; no real project, person or data is described.
enum DemoDocuments {
    /// Where relative links and images resolve: the app bundle's resources, which hold demo-illustration.png.
    static var baseURL: URL? { Bundle.main.resourceURL }

    /// A README-style guide that uses most of the supported syntax.
    static let guide = #"""
    # Welcome to MarkdownText

    **MarkdownText** renders Markdown with *native* SwiftUI views: selectable text, highlighted code,
    scrolling tables and async images. This guide is a bundled demo document, so every link here points to
    `example.com` or to another page of the demo.

    ![Stacked document cards in soft colors, an illustration bundled with the demo app](demo-illustration.png)

    ## Features

    - Headings, **bold**, *italic*, ~~strikethrough~~ and `inline code`
    - Links that open through `OpenURLAction`, like [the code samples](code-samples.md)
    - Bare URLs become links too: https://example.com/docs
    - Three built-in themes: *default*, *GitHub* and *docs*

    > **Tip:** Text is selectable. Long-press a paragraph on iPhone, or drag across it on the Mac.

    ## Getting started

    1. Add the package to your project.
    2. Import the module and pass it a string:

       ```swift
       import MarkdownText

       MarkdownText("Hello, **world**!")
           .markdownTheme(.github)
       ```

    3. Put long documents in a `ScrollView`.

    ## Roadmap

    - [x] CommonMark blocks and inlines
    - [x] GitHub tables, task lists and autolinks
    - [ ] Footnotes
    - [ ] Math blocks

    ## Supported syntax

    | Element | Syntax | Renders as |
    | :--- | :---: | ---: |
    | Heading | `# Title` | Text with a heading font |
    | Code block | ```` ``` ```` | Highlighted, with Copy |
    | Table | `\| a \| b \|` | Horizontally scrolling grid |
    | Task | `- [x]` | Checkbox symbol |

    ---

    *This is sample text for the MarkdownText demo app.* Questions go to <hello@example.com>.
    """#

    /// Code blocks in every highlighted language.
    static let codeSamples = #"""
    # Code samples

    Fenced code blocks are highlighted for **Swift**, **Kotlin**, **JSON** and **shell**. Each block scrolls
    sideways and has a *Copy* button.

    ```swift
    import SwiftUI
    import MarkdownText

    @MainActor
    struct ReadmeView: View {
        let markdown: String
        var body: some View {
            ScrollView {
                MarkdownText(markdown)
                    .padding()
            }
            // or .docs
            .markdownTheme(.github)
        }
    }
    ```

    ```kotlin
    data class Note(
        val title: String,
        val words: Int,
    )

    fun total(notes: List<Note>) =
        notes.sumOf { it.words }
    ```

    ```json
    {
      "name": "demo-config",
      "version": 2,
      "features": ["tables", "tasks"],
      "beta": false
    }
    ```

    ```sh
    # Build and test the package
    swift build -c release
    swift test --parallel | tee test.log
    echo "Done in $SECONDS seconds"
    ```

    Unknown languages are shown as plain text:

    ```text
    Plain text keeps its   spacing.
    ```
    """#

    /// A short document for the editor's "Blank" sample.
    static let starter = #"""
    # Untitled

    Start typing **Markdown** on the left; the preview updates as you type.
    """#
}
