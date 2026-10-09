import Foundation
import SwiftData
import Testing
@testable import Ovyl

/// The search index, the assistant's library tools, storage cleanup, and
/// audio as its own kind of note.
@MainActor
@Suite(.serialized)
struct LibraryTests {
    // MARK: Fixtures

    private static func content() -> NoteContent {
        var content = NoteContent()
        content.summary = "The quarterly review."
        content.sections = [
            NoteSection(heading: "Budget", paragraphs: [
                Paragraph(start: 242, end: 250, text: "So, about the budget for next quarter."),
                Paragraph(start: 251, end: 260, text: "Priya owns it from now on."),
            ]),
            NoteSection(heading: "Launch", paragraphs: [
                Paragraph(start: 600, end: 610, text: "The launch moves to March fourteenth."),
            ]),
        ]
        content.screenMoments = [
            ScreenMoment(start: 574, end: 590, lines: ["Q3 Roadmap", "Ship the mobile beta"], title: "Q3 Roadmap"),
        ]
        return content
    }

    private static func snapshot(id: UUID = UUID(), title: String = "Team Sync", markdown: String? = nil, fingerprint: String = "1") -> NoteSnapshot {
        NoteSnapshot(id: id, title: title, sourceName: "team-sync.mov", folderName: "Work", kind: .video, createdAt: .now, fingerprint: fingerprint, editedMarkdown: markdown, content: content())
    }

    private static func temporaryIndex() -> SearchIndex {
        SearchIndex(url: FileManager.default.temporaryDirectory.appending(path: "ovyl-index-\(UUID().uuidString).sqlite"))
    }

    private static func center() throws -> ProcessingCenter {
        let container = try ModelContainer(for: Note.self, Folder.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ProcessingCenter(container: container)
    }

    private static func readyNote(_ title: String, in center: ProcessingCenter) -> Note {
        let note = Note(sourceName: "\(title).mov", sourceBookmark: nil)
        note.title = title
        note.content = content()
        note.duration = 700
        note.status = .ready
        center.context.insert(note)
        center.save()
        return note
    }

    // MARK: Passages

    @Test func passagesCoverSpeechScreenAndSummary() {
        let passages = Self.snapshot().passages
        #expect(passages.first?.kind == .title)
        #expect(passages.contains { $0.kind == .summary && $0.text.contains("quarterly review") })
        let budget = passages.first { $0.text.contains("budget") }
        #expect(budget?.kind == .speech)
        #expect(budget?.start == 242)
        #expect(budget?.heading == "Budget")
        #expect(passages.contains { $0.kind == .screen && $0.heading == "Q3 Roadmap" && $0.start == 574 })
    }

    @Test func editedTextIsCutByBlockUnderItsHeading() {
        let markdown = "## Money\n\n[4:02](#t=242) The budget is Priya's.\n\n## Dates\n\nLaunch on March 14."
        let passages = NoteSnapshot.passages(ofMarkdown: markdown)
        #expect(passages.count == 2)
        #expect(passages[0].heading == "Money")
        #expect(passages[0].start == 242)
        #expect(passages[0].text.contains("budget"))
        #expect(passages[1].heading == "Dates")
        #expect(passages[1].start == nil)
    }

    // MARK: Index

    @Test func findsWordsWithTheirTimeAndMarksThem() async {
        let index = Self.temporaryIndex()
        let id = UUID()
        await index.update(Self.snapshot(id: id))
        let matches = await index.search("budget")
        #expect(matches.first?.noteID == id)
        let best = try? #require(matches.first?.best)
        #expect(best?.kind == .speech)
        #expect(best?.start == 242)
        #expect(best?.snippet.contains("\u{1}budget\u{2}") == true)
        // Words match as prefixes while they're typed, and accents don't matter.
        #expect(await index.search("budg").first?.noteID == id)
        #expect(await index.search("prïya").first?.noteID == id)
        // Every word has to be there.
        #expect(await index.search("budget zebra").isEmpty)
        // Text read off the screen is found too.
        #expect(await index.search("mobile beta").first?.best.kind == .screen)
        await index.clear()
    }

    @Test func titlesRankAboveMentions() async {
        let index = Self.temporaryIndex()
        let named = UUID()
        let mentioning = UUID()
        await index.update(Self.snapshot(id: named, title: "Launch Plan"))
        await index.update(Self.snapshot(id: mentioning, title: "Weekly"))
        let matches = await index.search("launch")
        #expect(matches.first?.noteID == named)
        #expect(matches.count == 2)
        await index.clear()
    }

    @Test func reconcileDropsGoneNotesAndListsChangedOnes() async {
        let index = Self.temporaryIndex()
        let kept = UUID(), gone = UUID(), changed = UUID(), new = UUID()
        await index.update(Self.snapshot(id: kept, fingerprint: "a"))
        await index.update(Self.snapshot(id: gone, fingerprint: "a"))
        await index.update(Self.snapshot(id: changed, fingerprint: "a"))
        let stale = await index.reconcile([kept: "a", changed: "b", new: "a"])
        #expect(Set(stale) == [changed, new])
        #expect(await index.search("budget").map(\.noteID).contains(gone) == false)
        await index.clear()
    }

    @Test func searchCanBeLimitedToAFolder() async {
        let index = Self.temporaryIndex()
        let inside = UUID(), outside = UUID()
        await index.update(Self.snapshot(id: inside))
        await index.update(Self.snapshot(id: outside))
        let matches = await index.search("budget", in: [inside])
        #expect(matches.map(\.noteID) == [inside])
        await index.clear()
    }

    @Test func matchExpressionQuotesWordsAsPrefixes() {
        #expect(SearchIndex.matchExpression("budget  q3") == "\"budget\"* \"q3\"*")
        #expect(SearchIndex.matchExpression("\"; DROP") == "\"DROP\"*")
        #expect(SearchIndex.matchExpression("  ,. ") == nil)
    }

    // MARK: Assistant tools

    @Test func toolsFindReadAndQuoteTimes() async throws {
        let center = try Self.center()
        let note = Self.readyNote("Team Sync", in: center)
        let index = Self.temporaryIndex()
        await index.update(note.snapshot(folderName: nil))
        let tools = LibraryTools(center: center, readBudget: 2_400, index: index, catchUp: {})
        var steps: [ChatStep] = []
        tools.onStep = { steps.append($0) }

        let found = await tools.run("search_library", .object(["query": .string("Priya budget")]))
        #expect(found.contains("Team Sync"))
        #expect(found.contains(LibraryTools.ref(note.id)))

        let read = await tools.run("read_note", .object(["note": .string(LibraryTools.ref(note.id))]))
        #expect(read.contains("Priya owns it"))
        // Timestamp links read as plain times.
        #expect(read.contains("[4:02]"))
        #expect(!read.contains("#t="))

        let said = await tools.run("read_transcript", .object(["note": .string("team sync"), "from": .string("5:00"), "to": .string("11:00")]))
        #expect(said.contains("[10:00] The launch moves"))
        #expect(!said.contains("budget"))

        let frames = await tools.run("read_frames", .object(["note": .string("Team Sync")]))
        #expect(frames.contains("[9:34] Frame Q3 Roadmap"))

        #expect(steps.map(\.kind) == [.searched, .read, .read, .read])
        await index.clear()
    }

    @Test func toolsChangeNotesAndUndo() async throws {
        let center = try Self.center()
        let note = Self.readyNote("Team Sync", in: center)
        let tools = LibraryTools(center: center, readBudget: 40_000, index: Self.temporaryIndex(), catchUp: {})
        var steps: [ChatStep] = []
        tools.onStep = { steps.append($0) }

        // Combine: a new note of text, in a folder made for it.
        _ = await tools.run("create_note", .object([
            "title": .string("Planning, combined"),
            "markdown": .string("# Planning, combined\n\n## Budget\n\nPriya owns it."),
            "folder": .string("Plans"),
        ]))
        let made = try #require(center.context.fetch(FetchDescriptor<Note>()).first { $0.displayTitle == "Planning, combined" })
        #expect(made.kind == .text)
        #expect(made.status == .ready)
        // The title isn't repeated as a heading.
        #expect(made.markdown.hasPrefix("## Budget"))
        let folder = try #require(center.context.fetch(FetchDescriptor<Folder>()).first)
        #expect(folder.name == "Plans")
        #expect(made.folderID == folder.id)

        // Restructure: rewrite, then undo back to Ovyl's text.
        let original = note.markdown
        _ = await tools.run("update_note", .object(["note": .string("Team Sync"), "markdown": .string("## Summary\n\nShort and clear.")]))
        #expect(note.markdown.contains("Short and clear."))
        _ = await tools.run("rename_note", .object(["note": .string("Team Sync"), "title": .string("Q3 Review")]))
        #expect(note.displayTitle == "Q3 Review")

        for step in steps.reversed() {
            if let undo = step.undo { tools.undo(undo) }
        }
        #expect(note.markdown == original)
        #expect(note.editedMarkdown == nil)
        #expect(note.displayTitle == "Team Sync")
        #expect(try center.context.fetch(FetchDescriptor<Note>()).count == 1)
    }

    @Test func longNotesAreReadInParts() async throws {
        let center = try Self.center()
        let note = center.createTextNote(title: "Long", markdown: (1...40).map { "Paragraph \($0) " + String(repeating: "word ", count: 30) }.joined(separator: "\n\n"))
        let tools = LibraryTools(center: center, readBudget: 1_000, index: Self.temporaryIndex(), catchUp: {})
        let first = await tools.run("read_note", .object(["note": .string(LibraryTools.ref(note.id))]))
        #expect(first.contains("Part 1 of"))
        #expect(first.contains("Part 2 continues it"))
        let second = await tools.run("read_note", .object(["note": .string("Long"), "part": .number(2)]))
        #expect(second.contains("Part 2 of"))
        #expect(!second.contains("Paragraph 1 "))
    }

    @Test func notesAreFoundByIdOrTitle() throws {
        let center = try Self.center()
        let note = Self.readyNote("Lecture 4", in: center)
        let tools = LibraryTools(center: center, readBudget: 1_000, index: Self.temporaryIndex(), catchUp: {})
        #expect(tools.resolve("[\(LibraryTools.ref(note.id))]")?.id == note.id)
        #expect(tools.resolve("lecture 4")?.id == note.id)
        #expect(tools.resolve("“Lecture”")?.id == note.id)
        #expect(tools.resolve("nothing like it") == nil)
    }

    @Test func claudeToolSchemasAreObjects() throws {
        for spec in LibraryTools.specs {
            #expect(spec.inputSchema["type"] == .string("object"))
            _ = try spec.generationSchema()
        }
        let data = try JSONEncoder().encode([ClaudeBlock.toolUse(id: "t1", name: "read_note", input: .object(["note": .string("x")])), .toolResult(id: "t1", content: "ok")])
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"type\":\"tool_use\""))
        #expect(text.contains("\"tool_use_id\":\"t1\""))
    }

    // MARK: Storage

    @Test func sweepRemovesFramesOfGoneNotesOnly() throws {
        let root = StorageManager.framesRoot
        let kept = UUID(), gone = UUID()
        for id in [kept, gone] {
            try FileManager.default.createDirectory(at: root.appending(path: id.uuidString), withIntermediateDirectories: true)
        }
        let existing = Set(((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).compactMap(UUID.init))
        StorageManager.sweep(keeping: existing.subtracting([gone]))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: kept.uuidString).path))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: gone.uuidString).path))
        try? FileManager.default.removeItem(at: root.appending(path: kept.uuidString))
    }

    // MARK: Audio

    @Test func audioFilesAreTheirOwnKind() {
        #expect(ProcessingCenter.kind(of: URL(filePath: "/tmp/talk.m4a")) == .video)
        #expect(Note(sourceName: "talk.m4a", sourceBookmark: nil).mediaKind == .audio)
        #expect(Note(sourceName: "talk.mp3", sourceBookmark: nil).mediaKind == .audio)
        #expect(Note(sourceName: "talk.mov", sourceBookmark: nil).mediaKind == .video)
        #expect(Note.title(fromFileName: ".m4a") == "Untitled Recording")
    }

    @Test(.timeLimit(.minutes(5))) func audioOnlyRecordingIsTranscribed() async throws {
        try #require(AppleSpeechEngine.isAvailable)
        final class Token {}
        let url = try #require(Bundle(for: Token.self).url(forResource: "sample-audio", withExtension: "m4a", subdirectory: "Fixtures"))
        var options = PipelineOptions()
        options.engine = .apple
        options.language = "en"
        options.smartFormatting = false
        let folder = FileManager.default.temporaryDirectory.appending(path: "ovyl-tests-\(UUID().uuidString)")
        let result = try await ClipPipeline().run(url: url, options: options, thumbnailsFolder: folder) { _ in }
        let transcript = result.content.paragraphs.map(\.text).joined(separator: " ").lowercased()
        #expect(transcript.contains("quarterly planning"))
        // No picture, so nothing is read off a screen.
        #expect(result.content.screenMoments.isEmpty)
        #expect(result.duration > 20)
    }
}
