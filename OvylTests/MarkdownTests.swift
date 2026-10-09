import Foundation
import Testing
@testable import Ovyl

struct MarkdownTests {
    @Test func parsesBlocks() {
        let blocks = MarkdownDocument.parse("""
        # Title ##

        A paragraph
        on two lines.

        - one
          - nested
        - [x] done
        1. first

        > [!summary]- Folded summary
        > Inside.

        > Plain quote

        ```swift
        let x = 1
        ```

        ---

        | A | B |
        |:--|--:|
        | 1 | 2 |
        """)
        #expect(blocks.count == 8)
        #expect(blocks[0] == .heading(level: 1, text: "Title"))
        #expect(blocks[1] == .paragraph("A paragraph\non two lines."))
        guard case .list(let items) = blocks[2] else { Issue.record("not a list"); return }
        #expect(items.map(\.level) == [0, 1, 0, 0])
        #expect(items.map(\.marker) == [.bullet, .bullet, .task(done: true), .ordered(1)])
        #expect(items[2].text == "done")
        #expect(items[2].line == 7)
        guard case .callout(let callout) = blocks[3] else { Issue.record("not a callout"); return }
        #expect(callout.kind == "summary")
        #expect(callout.title == "Folded summary")
        #expect(callout.folded == true)
        #expect(callout.body == [.paragraph("Inside.")])
        #expect(blocks[4] == .quote([.paragraph("Plain quote")]))
        #expect(blocks[5] == .code(language: "swift", text: "let x = 1"))
        #expect(blocks[6] == .rule)
        #expect(blocks[7] == .table(MarkdownTable(header: ["A", "B"], alignments: [.leading, .trailing], rows: [["1", "2"]])))
    }

    @Test func hashtagsAndNumbersStayText() {
        #expect(MarkdownDocument.parse("#tag not a heading") == [.paragraph("#tag not a heading")])
        #expect(MarkdownDocument.parse("1.5 million people") == [.paragraph("1.5 million people")])
    }

    @Test func togglesTasks() {
        let text = "- [ ] buy milk\n> - [x] quoted"
        let once = MarkdownDocument.togglingTask(in: text, line: 0)
        #expect(once == "- [x] buy milk\n> - [x] quoted")
        #expect(MarkdownDocument.togglingTask(in: once, line: 1) == "- [x] buy milk\n> - [ ] quoted")
        // A line without a task is left alone.
        #expect(MarkdownDocument.togglingTask(in: "plain", line: 0) == "plain")
    }

    @Test func writesNotesAsObsidianMarkdown() {
        var content = NoteContent()
        content.summary = "What it covers."
        content.keyPoints = ["First", "Second"]
        content.sections = [NoteSection(heading: "Intro", paragraphs: [Paragraph(start: 65, end: 70, text: "Hello there.")])]
        content.screenMoments = [ScreenMoment(start: 66.5, end: 70, lines: ["Slide title", "Body"], title: "Slide title")]
        content.music = [TimeSpan(start: 80, end: 95)]

        let markdown = NoteMarkdown.body(of: content)
        // The summary is in the note's info, not its text.
        #expect(!markdown.contains("What it covers."))
        #expect(markdown.hasPrefix("## Key points\n\n- First\n- Second"))
        #expect(markdown.contains("## Intro\n\n[1:05](#t=65) Hello there."))
        #expect(markdown.contains("> [!screen] On screen · [1:06](#t=66.5)\n> **Slide title**\n> Body"))
        #expect(markdown.contains("> [!music] Music · [1:20](#t=80)–1:35"))

        // It reads back as the blocks the note view shows.
        let blocks = MarkdownDocument.parse(markdown)
        #expect(blocks.first == .heading(level: 2, text: "Key points"))
        #expect(blocks.contains(.paragraph("[1:05](#t=65) Hello there.")))

        // Outside Ovyl, timestamps become bold text.
        #expect(NoteMarkdown.portable(markdown).contains("**1:05** Hello there."))
        #expect(NoteMarkdown.plainText(markdown).contains("1:05 Hello there."))
    }

    @Test func readsLinks() throws {
        #expect(NoteMarkdown.seconds(in: try #require(URL(string: "#t=66.5"))) == 66.5)
        #expect(NoteMarkdown.pictureIndex(in: try #require(URL(string: "#p=2"))) == 2)
        #expect(NoteMarkdown.seconds(in: try #require(URL(string: "https://example.com/#t=5"))) == nil)
    }

    @Test @MainActor func editedTextIsKeptAndSearched() {
        let note = Note(sourceName: "talk.mp4", sourceBookmark: nil)
        var content = NoteContent()
        content.sections = [NoteSection(heading: "", paragraphs: [Paragraph(start: 0, end: 1, text: "Original")])]
        note.content = content
        #expect(note.editedMarkdown == nil)

        note.setMarkdown("# Mine\n\nRewritten **text**.")
        #expect(note.markdown == "# Mine\n\nRewritten **text**.")
        #expect(note.searchText.contains("Rewritten text."))

        // Writing back Ovyl's own text drops the edit.
        note.setMarkdown(NoteMarkdown.body(of: content))
        #expect(note.editedMarkdown == nil)
    }

    @Test func wrapsAndUnwrapsSelections() {
        let text = "make this bold"
        let bold = MarkdownEditing.toggleWrap(text, selection: NSRange(location: 10, length: 4), marker: "**")
        #expect(bold.replacement == "**bold**")
        #expect(bold.selection == NSRange(location: 12, length: 4))

        let wrapped = (text as NSString).replacingCharacters(in: bold.range, with: bold.replacement)
        let unwrapped = MarkdownEditing.toggleWrap(wrapped, selection: bold.selection, marker: "**")
        #expect((wrapped as NSString).replacingCharacters(in: unwrapped.range, with: unwrapped.replacement) == text)

        let link = MarkdownEditing.link(text, selection: NSRange(location: 0, length: 4))
        #expect(link.replacement == "[make](url)")
        #expect((("[make](url) this bold") as NSString).substring(with: link.selection) == "url")
    }

    @Test func stylesLines() {
        let text = "one\ntwo\nthree"
        let all = NSRange(location: 0, length: (text as NSString).length)
        let numbered = MarkdownEditing.toggleLines(text, selection: all, style: .numbered)
        #expect(numbered.replacement == "1. one\n2. two\n3. three")

        let heading = MarkdownEditing.toggleLines("- item", selection: NSRange(location: 3, length: 0), style: .heading2)
        #expect(heading.replacement == "## item")
        #expect(heading.selection == NSRange(location: 7, length: 0))

        // Applying a style every line has takes it off.
        let off = MarkdownEditing.toggleLines("> a\n> b", selection: NSRange(location: 0, length: 7), style: .quote)
        #expect(off.replacement == "a\nb")
        #expect(MarkdownEditing.style(of: "- [ ] task") == .task)
    }
}
