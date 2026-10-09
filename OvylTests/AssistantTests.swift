import AppKit
import FoundationModels
import SwiftData
import SwiftUI
import Testing
@testable import Ovyl

/// The assistant with a real model, and its pane rendered for checking by eye.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(5)))
struct AssistantTests {
    static let folder = FileManager.default.temporaryDirectory.appending(path: "ovyl-assistant")

    private static func library() throws -> (ProcessingCenter, Note) {
        let container = try ModelContainer(for: Note.self, Folder.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let center = ProcessingCenter(container: container)
        let note = Note(sourceName: "team-sync.mov", sourceBookmark: nil)
        note.title = "Team Sync"
        var content = NoteContent()
        content.sections = [
            NoteSection(heading: "Budget", paragraphs: [
                Paragraph(start: 242, end: 250, text: "So, about the budget for next quarter."),
                Paragraph(start: 251, end: 260, text: "From now on Priya Raman owns the budget, not Sam."),
            ]),
            NoteSection(heading: "Launch", paragraphs: [
                Paragraph(start: 600, end: 610, text: "The launch moves to March fourteenth."),
            ]),
        ]
        note.content = content
        note.duration = 700
        note.status = .ready
        center.context.insert(note)
        center.save()
        return (center, note)
    }

    /// Apple's on-device model finds the answer through the library tools.
    @Test func onDeviceModelAnswersFromTheLibrary() async throws {
        try #require(SystemLanguageModel.default.availability == .available, "Apple Intelligence is off on this Mac")
        let (center, note) = try Self.library()
        let index = SearchIndex(url: FileManager.default.temporaryDirectory.appending(path: "ovyl-index-\(UUID().uuidString).sqlite"))
        await index.update(note.snapshot(folderName: nil))
        let tools = LibraryTools(center: center, readBudget: AssistantModel.onDevice.readBudget, index: index, catchUp: {})
        var steps: [ChatStep] = []
        tools.onStep = { steps.append($0) }

        let session = LanguageModelSession(model: SystemLanguageModel.default, tools: tools.appleTools(), instructions: AssistantSession.instructions(for: .onDevice))
        let answer = try await session.respond(to: "In my Team Sync note, who owns the budget now?").content
        print("ASSISTANT \(answer) STEPS \(steps.map(\.summary))")
        #expect(!steps.isEmpty)
        #expect(answer.localizedCaseInsensitiveContains("Priya"))
        await index.clear()
    }

    /// The pane with a conversation: an attached note, a question, what the
    /// assistant did, and its answer.
    @Test func renderAssistantPane() async throws {
        try? FileManager.default.removeItem(at: Self.folder)
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let (center, note) = try Self.library()
        let defaults = UserDefaults.standard
        let showed = defaults.bool(forKey: "showAssistant")
        defaults.set(true, forKey: "showAssistant")
        defer { defaults.set(showed, forKey: "showAssistant") }

        var chat = Chat(title: "Budget")
        chat.messages = [
            ChatMessage(role: .user, text: "Who owns the budget now? Tidy the note up too.", context: [ContextItem(noteID: note.id, title: "Team Sync", detail: "Video · 11:40")]),
            ChatMessage(
                role: .assistant,
                text: "**Priya Raman** owns the budget from now on, not Sam (4:11).\n\nI rewrote **Team Sync** with a heading per topic:\n\n- **Budget**: Priya takes over for next quarter.\n- **Launch**: moves to March 14 (10:00).",
                steps: [
                    ChatStep(kind: .searched, summary: "Searched for “budget”"),
                    ChatStep(kind: .read, summary: "Read Team Sync", noteID: note.id),
                    ChatStep(kind: .edited, summary: "Rewrote Team Sync", noteID: note.id, undo: .restoreText(note.id, previous: nil)),
                ],
                model: AssistantModel.onDevice.label
            ),
        ]
        AssistantSession.shared.show(chat)
        try await render(ContentView(route: .note(note.id)), center: center, name: "assistant-light", dark: false)
        try await render(ContentView(route: .note(note.id)), center: center, name: "assistant-dark", dark: true)
        // Leaves nothing behind in the chat history.
        AssistantSession.shared.delete(chat.id)
        try await render(ContentView(route: .home), center: center, name: "assistant-new", dark: false)
        print("ASSISTANT SNAPSHOTS \(Self.folder.path)")
    }

    private func render(_ view: some View, center: ProcessingCenter, name: String, dark: Bool) async throws {
        let root = view
            .environment(center)
            .environment(\.motionTime, 6.2)
            .modelContainer(center.container)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = [.minSize]
        hosting.frame = CGRect(x: 0, y: 0, width: 1320, height: 860)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.setFrameOrigin(CGPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        try await Task.sleep(for: .seconds(1.2))
        hosting.layoutSubtreeIfNeeded()
        let frameView = window.contentView?.superview ?? hosting
        let rep = try #require(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: Self.folder.appending(path: "\(name).png"))
        window.orderOut(nil)
        window.contentView = nil
    }
}
