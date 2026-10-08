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

        let container = try ModelContainer(for: Note.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext

        // Welcome screen with no notes.
        try await render(ContentView(), container: container, name: "welcome-light", dark: false)
        try await render(ContentView(), container: container, name: "welcome-dark", dark: true)

        // A real note from the sample video.
        let sample = try #require(Bundle(for: Token.self).url(forResource: "sample", withExtension: "mp4", subdirectory: "Fixtures"))
        let note = Note(sourceName: "quarterly-planning-review.mp4", sourceBookmark: try? Note.bookmark(for: sample))
        context.insert(note)
        let result = try await ClipPipeline().run(url: sample, options: PipelineOptions(), thumbnailsFolder: note.thumbnailsFolder) { _ in }
        note.title = result.title
        note.content = result.content
        note.duration = result.duration
        note.status = .ready

        // A song with captions, narration with subtitles, and pictures, read
        // with Apple Speech to keep this quick.
        var quick = PipelineOptions()
        quick.engine = .apple
        quick.language = "en"
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

        // The note with its video player showing: SwiftUI's VideoPlayer crashed
        // here on macOS 27, so this path has to be rendered for real.
        UserDefaults.standard.set(true, forKey: "showsVideo")
        try await render(ContentView(initialSelection: note.id), container: container, name: "note-video", dark: false)
        UserDefaults.standard.set(false, forKey: "showsVideo")
        try await render(ContentView(initialSelection: note.id), container: container, name: "note-light", dark: false)
        try await render(ContentView(initialSelection: note.id), container: container, name: "note-dark", dark: true)
        let tall = CGSize(width: 1240, height: 1500)
        for (name, video) in made {
            try await render(ContentView(initialSelection: video.id), container: container, name: "note-\(name)", dark: false, size: tall)
        }
        try await render(ContentView(initialSelection: pictures.id), container: container, name: "note-pictures", dark: false, size: tall)
        try await render(ContentView(initialSelection: pictures.id), container: container, name: "note-pictures-dark", dark: true, size: tall)
        try await render(ContentView(initialSelection: queued.id), container: container, name: "processing-light", dark: false)
        try await render(SettingsView(), container: container, name: "settings", dark: false, size: CGSize(width: 540, height: 640))
        // List rows don't show in offscreen captures of the sidebar, so render them alone.
        let rows = VStack(alignment: .leading, spacing: 0) {
            ForEach([queued, note, pictures, failed]) { item in
                NoteRow(note: item).padding(.horizontal, 14)
                Divider()
            }
        }
        .frame(width: 290)
        .background(.background)
        try await render(rows, container: container, name: "rows", dark: false, size: CGSize(width: 290, height: 400))
        UserDefaults.standard.removeObject(forKey: "showsVideo")
        for item in [note, pictures] + made.values {
            try? FileManager.default.removeItem(at: item.thumbnailsFolder)
        }
    }

    private func render(
        _ view: some View,
        container: ModelContainer,
        name: String,
        dark: Bool,
        size: CGSize = CGSize(width: 1240, height: 860)
    ) async throws {
        let root = view
            .environment(ProcessingCenter.shared)
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
