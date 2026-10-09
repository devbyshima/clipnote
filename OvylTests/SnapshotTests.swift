import AppKit
import SwiftData
import SwiftUI
import Testing
@testable import Ovyl

/// Renders the real window offscreen to PNGs, for checking the layout by eye.
/// Files land in the test host's temporary folder; the path is printed.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(10)))
struct SnapshotTests {
    private final class Token {}

    static let folder = FileManager.default.temporaryDirectory.appending(path: "ovyl-snapshots")

    @Test func renderWindows() async throws {
        try? FileManager.default.removeItem(at: Self.folder)
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        print("Snapshots: \(Self.folder.path)")

        let container = try ModelContainer(for: Note.self, Folder.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let defaults = UserDefaults.standard
        let layoutKeys = ["showSidebar", "showMedia", "mediaPaneWidth", "galleryPaneWidth", "propertiesFolded"]
        layoutKeys.forEach(defaults.removeObject(forKey:))

        // Home with no notes.
        try await render(ContentView(), container: container, name: "welcome-light", dark: false)
        try await render(ContentView(), container: container, name: "welcome-dark", dark: true)

        // A real note from the sample video.
        let sample = try #require(Bundle(for: Token.self).url(forResource: "sample", withExtension: "mp4", subdirectory: "Fixtures"))
        let note = Note(sourceName: "quarterly-planning-review.mp4", sourceBookmark: try? Note.bookmark(for: sample))
        context.insert(note)
        // Read with Apple Speech to keep this quick; the integration tests cover Whisper.
        var quick = PipelineOptions()
        quick.engine = .apple
        quick.language = "en"
        let result = try await ClipPipeline().run(url: sample, options: quick, thumbnailsFolder: note.thumbnailsFolder) { _ in }
        note.title = result.title
        note.content = result.content
        note.duration = result.duration
        note.status = .ready

        // A song with captions, narration with subtitles, and pictures.
        var made: [String: Note] = [:]
        for (name, title) in [("captions-music", "sleep-tips.mp4"), ("captions-speech", "morning-routine.mp4")] {
            let url = try #require(Bundle(for: Token.self).url(forResource: name, withExtension: "mp4", subdirectory: "Fixtures"))
            let video = Note(sourceName: title, sourceBookmark: try? Note.bookmark(for: url))
            video.createdAt = .now.addingTimeInterval(-60)
            context.insert(video)
            let output = try await ClipPipeline().run(url: url, options: quick, thumbnailsFolder: video.thumbnailsFolder) { _ in }
            video.title = output.title
            video.content = output.content
            video.duration = output.duration
            video.status = .ready
            made[name] = video
        }
        let pictureURLs = try ["picture-1", "picture-2"].map {
            try #require(Bundle(for: Token.self).url(forResource: $0, withExtension: "png", subdirectory: "Fixtures"))
        }
        let pictures = Note(pictures: pictureURLs.map { ($0.lastPathComponent, try? Note.bookmark(for: $0)) })
        pictures.createdAt = .now.addingTimeInterval(-120)
        context.insert(pictures)
        let read = try await ClipPipeline().run(pictures: pictureURLs, options: quick, thumbnailsFolder: pictures.thumbnailsFolder) { _ in }
        pictures.title = read.title
        pictures.content = read.content
        pictures.status = .ready

        let queued = Note(sourceName: "team_offsite-day2.mov", sourceBookmark: nil)
        queued.createdAt = .now.addingTimeInterval(60)
        queued.status = .processing
        queued.stage = "Transcribing speech · Reading on-screen text"
        queued.progress = 0.42
        context.insert(queued)

        let failed = Note(sourceName: "old-recording.mp4", sourceBookmark: nil)
        failed.createdAt = .now.addingTimeInterval(-86_400)
        failed.status = .failed
        failed.errorMessage = ClipError.fileMissing.errorDescription
        context.insert(failed)
        try context.save()

        let folder = Folder(name: "Planning")
        context.insert(folder)
        note.folderID = folder.id
        made["captions-speech"]?.folderID = folder.id
        try context.save()

        try await render(ContentView(), container: container, name: "home-light", dark: false)
        try await render(ContentView(), container: container, name: "home-dark", dark: true)
        // The note in reader mode with its video on the right: SwiftUI's
        // VideoPlayer crashed on macOS 27, so this path has to be rendered for real.
        try await render(ContentView(initialSelection: note.id), container: container, name: "note-light", dark: false)
        try await render(ContentView(initialSelection: note.id), container: container, name: "note-dark", dark: true)
        try await render(ContentView(route: .gallery(note.id)), container: container, name: "note-gallery", dark: false)
        try await render(ContentView(route: .media(note.id, item: 0)), container: container, name: "note-frame", dark: false)
        try await render(ContentView(route: .media(note.id, item: nil)), container: container, name: "media-info", dark: true)
        try await render(ContentView(route: .note(note.id), showsNoteInfo: true), container: container, name: "note-info", dark: false)
        try await render(ContentView(route: .note(note.id), showsNoteInfo: true), container: container, name: "note-info-dark", dark: true)
        try await render(ContentView(route: .note(note.id), startsEditing: true), container: container, name: "note-editing", dark: false) { window in
            // Select a word, to show the formatting bar.
            guard let textView = Self.find(NSTextView.self, in: window.contentView!) else { return }
            window.makeFirstResponder(textView)
            let range = (textView.string as NSString).range(of: "Revenue")
            textView.setSelectedRange(range)
        }
        try await render(ContentView(route: .note(note.id), startsEditing: true), container: container, name: "note-editing-dark", dark: true)
        defaults.set(false, forKey: "showSidebar")
        defaults.set(false, forKey: "showMedia")
        try await render(ContentView(initialSelection: note.id), container: container, name: "note-collapsed", dark: false)
        layoutKeys.forEach(defaults.removeObject(forKey:))
        let tall = CGSize(width: 1320, height: 1500)
        for (name, video) in made {
            try await render(ContentView(initialSelection: video.id), container: container, name: "note-\(name)", dark: false, size: tall)
        }
        try await render(ContentView(initialSelection: pictures.id), container: container, name: "note-pictures", dark: false, size: tall)
        try await render(ContentView(initialSelection: pictures.id), container: container, name: "note-pictures-dark", dark: true, size: tall)
        try await render(ContentView(initialSelection: queued.id), container: container, name: "processing-light", dark: false)
        try await render(ContentView(initialSelection: failed.id), container: container, name: "failed-dark", dark: true)
        try await render(SettingsView(), container: container, name: "settings", dark: false, size: CGSize(width: 540, height: 640))
        for item in [note, pictures] + made.values {
            try? FileManager.default.removeItem(at: item.thumbnailsFolder)
        }
    }

    /// The editor grows with its text, so the page scrolls as one.
    @Test func editorGrowsWithText() async throws {
        final class Box { var text = "# Title\n\nA line." }
        let box = Box()
        let text = Binding(get: { box.text }, set: { box.text = $0 })
        let hosting = NSHostingView(rootView: ScrollView {
            MarkdownEditor(text: text, focusOnAppear: false).frame(width: 600)
        }.frame(width: 640, height: 400))
        hosting.frame = CGRect(x: 0, y: 0, width: 640, height: 400)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let textView = try #require(Self.find(NSTextView.self, in: hosting))
        let before = textView.frame.height
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.insertText(String(repeating: "\nAnother line of text.", count: 30), replacementRange: textView.selectedRange())
        try await Task.sleep(for: .milliseconds(300))
        hosting.layoutSubtreeIfNeeded()
        #expect(text.wrappedValue.hasSuffix("Another line of text."))
        #expect(textView.frame.height > before + 300)
        window.contentView = nil
    }

    /// The pane headers sit in the top row with the traffic lights centered
    /// beside them, and clicks there reach the headers, not the titlebar.
    @Test func topRowIsPartOfTheWindow() async throws {
        let container = try ModelContainer(for: Note.self, Folder.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let hosting = NSHostingView(rootView: ContentView().environment(ProcessingCenter.shared).modelContainer(container))
        hosting.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.contentView = hosting
        window.setFrameOrigin(CGPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        try await Task.sleep(for: .seconds(1))
        hosting.layoutSubtreeIfNeeded()
        // The app's run loop updates its windows after each event.
        window.update()

        let close = try #require(window.standardWindowButton(.closeButton))
        let lights = close.convert(close.bounds, to: nil)
        #expect(abs(lights.midY - (window.frame.height - MainWindowStyler.barHeight / 2)) <= 1)

        // The middle of the search row, well clear of the traffic lights.
        let frameView = try #require(hosting.superview)
        let hit = frameView.hitTest(NSPoint(x: 700, y: frameView.bounds.height - MainWindowStyler.barHeight / 2))
        #expect(hit?.isDescendant(of: hosting) == true)
        window.orderOut(nil)
        window.contentView = nil
    }

    /// Away from the caret, Markdown syntax is hidden; on the caret's line it shows.
    @Test func editorHidesSyntaxAwayFromTheCaret() async throws {
        final class Box { var text = "## Heading\n\nSome **bold** words." }
        let box = Box()
        let text = Binding(get: { box.text }, set: { box.text = $0 })
        let hosting = NSHostingView(rootView: MarkdownEditor(text: text, focusOnAppear: false).frame(width: 600, height: 300))
        hosting.frame = CGRect(x: 0, y: 0, width: 600, height: 300)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let textView = try #require(Self.find(NSTextView.self, in: hosting))
        let storage = try #require(textView.textStorage)
        func fontSize(at location: Int) -> CGFloat {
            (storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont)?.pointSize ?? 0
        }
        let boldMarker = (storage.string as NSString).range(of: "**").location

        // Caret on the last line: the heading's "##" hides, the bold's "**" shows.
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: storage.length, length: 0))
        #expect(fontSize(at: 0) < 1)
        #expect(fontSize(at: boldMarker) > 10)

        // Caret on the heading: the other way round.
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        #expect(fontSize(at: 0) > 10)
        #expect(fontSize(at: boldMarker) < 1)
        window.contentView = nil
    }

    private static func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = find(type, in: subview) { return match }
        }
        return nil
    }

    private func render(
        _ view: some View,
        container: ModelContainer,
        name: String,
        dark: Bool,
        size: CGSize = CGSize(width: 1320, height: 860),
        prepare: ((NSWindow) -> Void)? = nil
    ) async throws {
        // The empty states' motion is held at a settled moment.
        let root = view
            .environment(ProcessingCenter.shared)
            .environment(\.motionTime, 6.2)
            .modelContainer(container)
        let hosting = NSHostingView(rootView: root)
        // Like a SwiftUI window: content sets the minimum size, not the size.
        hosting.sizingOptions = [.minSize]
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.setFrameOrigin(CGPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        try await Task.sleep(for: .seconds(1.5))
        if let prepare {
            prepare(window)
            try await Task.sleep(for: .seconds(0.6))
        }
        hosting.layoutSubtreeIfNeeded()

        let frameView = window.contentView?.superview ?? hosting
        let rep = try #require(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: Self.folder.appending(path: "\(name).png"))
        // The container is private to the app, so the image also goes to the
        // log, where scripts/snapshots.sh picks it up.
        print("SNAPSHOT \(name) \(data.base64EncodedString())")
        // Tear the views down now, so nothing renders after the test ends.
        window.orderOut(nil)
        window.contentView = nil
    }
}
