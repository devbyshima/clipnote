import Foundation
import Observation
import SwiftData
import UniformTypeIdentifiers

/// Owns the notes store and the queue of notes waiting to be made. Notes are
/// made one at a time, in the order they were added.
@MainActor @Observable
final class ProcessingCenter {
    static let shared = ProcessingCenter()

    let container: ModelContainer
    var isImporterPresented = false
    var importError: String?
    /// The most recently imported note, so the window can select it.
    private(set) var lastImportedID: UUID?
    /// A folder just made, so the sidebar can start renaming it.
    var folderToRename: UUID?
    private(set) var processingID: UUID?
    private(set) var speechPhase: WhisperService.Phase = .idle

    @ObservationIgnored private var queue: [UUID] = []
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var currentRun: Task<PipelineResult, any Error>?
    @ObservationIgnored private let pipeline = ClipPipeline()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var observingSpeech = false

    private init() {
        container = Self.makeContainer()
    }

    /// A center over another store, for tests.
    init(container: ModelContainer) {
        self.container = container
    }

    var context: ModelContext { container.mainContext }

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Picks up notes left unfinished when the app last quit. The speech
    /// model isn't loaded until a video needs it, so launching stays light.
    func start() {
        guard !started, !Self.isRunningTests else { return }
        started = true
        observeSpeechModel()
        LibraryIndexer.shared.start(self)
        StorageManager.shared.sweepSoon(self)
        let unfinished = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.createdAt)])
        for note in (try? context.fetch(unfinished)) ?? [] where note.status == .queued || note.status == .processing {
            enqueue(note)
        }
    }

    /// Starts loading the speech model, so it's ready by the time a video's
    /// audio has been read. Loading twice is harmless.
    func prepareSpeechModel() {
        guard WhisperEngine.isBundled, !Self.isRunningTests else { return }
        observeSpeechModel()
        Task { await WhisperService.shared.prepare() }
    }

    /// Follows the speech model's state for the sidebar.
    private func observeSpeechModel() {
        guard WhisperEngine.isBundled, !observingSpeech else { return }
        observingSpeech = true
        Task {
            for await phase in await WhisperService.shared.phases() { speechPhase = phase }
        }
    }

    // MARK: Importing

    /// Makes a note from each video or audio file, and one note from all
    /// the pictures, in file name order, in `folderID` when given.
    @discardableResult
    func importFiles(_ urls: [URL], into folderID: UUID? = nil) -> [Note] {
        var created: [Note] = []
        var pictures: [(name: String, bookmark: Data?)] = []
        var skipped: [String] = []
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            switch Self.kind(of: url) {
            case .video:
                let note = Note(sourceName: url.lastPathComponent, sourceBookmark: try? Note.bookmark(for: url))
                context.insert(note)
                created.append(note)
            case .pictures:
                pictures.append((url.lastPathComponent, try? Note.bookmark(for: url)))
            case .text, nil:
                skipped.append(url.lastPathComponent)
            }
        }
        if !pictures.isEmpty {
            let note = Note(pictures: Self.inReadingOrder(pictures))
            context.insert(note)
            created.append(note)
        }
        for note in created { note.folderID = folderID }
        save()
        if !skipped.isEmpty {
            importError = "Ovyl makes notes from videos, audio, and pictures. Skipped: \(skipped.joined(separator: ", "))."
        }
        for note in created { enqueue(note) }
        if let last = created.last { lastImportedID = last.id }
        return created
    }

    nonisolated static func kind(of url: URL) -> NoteKind? {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
        guard let type else { return nil }
        if type.conforms(to: .audiovisualContent) { return .video }
        if type.conforms(to: .image) { return .pictures }
        return nil
    }

    /// By file name, the way Finder sorts: "Shot 2" before "Shot 10".
    nonisolated static func inReadingOrder<T>(_ files: [(name: String, bookmark: T)]) -> [(name: String, bookmark: T)] {
        files.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: Queue

    func enqueue(_ note: Note) {
        guard note.kind != .text else { return }
        // A video will need the speech model unless Apple Speech goes first.
        if note.kind == .video, PipelineOptions.fromDefaults().engine != .apple {
            prepareSpeechModel()
        }
        note.status = .queued
        note.stage = "Waiting"
        note.progress = 0
        note.errorMessage = nil
        if processingID != note.id, !queue.contains(note.id) { queue.append(note.id) }
        save()
        if worker == nil {
            worker = Task { await drain() }
        }
    }

    func stop(_ note: Note) {
        let wasProcessing = processingID == note.id
        if wasProcessing {
            currentRun?.cancel()
        } else {
            queue.removeAll { $0 == note.id }
            markStopped(note)
        }
        // With nothing else to make, the speech model stops getting ready.
        if queue.isEmpty, wasProcessing || processingID == nil {
            Task { await WhisperService.shared.standDown() }
        }
    }

    func delete(_ note: Note) {
        stop(note)
        try? FileManager.default.removeItem(at: note.thumbnailsFolder)
        context.delete(note)
        save()
    }

    func save() {
        try? context.save()
    }

    // MARK: Folders

    /// Makes a folder named "Untitled folder" (numbered if taken) and asks the
    /// sidebar to rename it.
    /// Makes a folder with the next free "Untitled folder" name, ready to be
    /// named where it shows: a pinned one in the sidebar, an unpinned one on
    /// its card on Home.
    @discardableResult
    func createFolder(named given: String? = nil, pinned: Bool = true) -> Folder {
        let folders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        let trimmed = given?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = trimmed.isEmpty ? nextFolderName() : trimmed
        let folder = Folder(name: name, colorName: Folder.colors[folders.count % Folder.colors.count])
        folder.isPinned = pinned
        context.insert(folder)
        save()
        folderToRename = folder.id
        return folder
    }

    /// "Untitled folder", or the first "Untitled folder 2", 3… not taken.
    func nextFolderName() -> String {
        let taken = Set(((try? context.fetch(FetchDescriptor<Folder>())) ?? []).map(\.name))
        var name = "Untitled folder"
        var number = 2
        while taken.contains(name) {
            name = "Untitled folder \(number)"
            number += 1
        }
        return name
    }

    /// Pins the folder to the sidebar, or takes it off.
    func setPinned(_ folder: Folder, _ pinned: Bool) {
        guard folder.isPinned != pinned else { return }
        folder.isPinned = pinned
        save()
    }

    func rename(_ folder: Folder, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != folder.name else { return }
        folder.name = name
        save()
    }

    /// Deletes the folder; its notes stay, out of any folder.
    func delete(_ folder: Folder) {
        let id = folder.id
        let inside = FetchDescriptor<Note>(predicate: #Predicate { $0.folderID == id })
        for note in (try? context.fetch(inside)) ?? [] { note.folderID = nil }
        context.delete(folder)
        save()
    }

    /// Makes a note of text, as the assistant does when it combines notes.
    @discardableResult
    func createTextNote(title: String, markdown: String, in folderID: UUID? = nil) -> Note {
        let note = Note(title: title, markdown: markdown)
        note.folderID = folderID
        context.insert(note)
        save()
        return note
    }

    func move(_ noteIDs: [UUID], to folderID: UUID?) {
        for id in noteIDs { note(with: id)?.folderID = folderID }
        save()
    }

    func note(with id: UUID) -> Note? {
        var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func drain() async {
        while !queue.isEmpty {
            let id = queue.removeFirst()
            await process(id)
        }
        worker = nil
    }

    private func process(_ id: UUID) async {
        guard let note = note(with: id) else { return }
        processingID = id
        defer { processingID = nil }

        // Text written in Ovyl has nothing to process.
        guard note.kind != .text else {
            note.status = .ready
            save()
            return
        }
        note.status = .processing
        note.stage = "Opening \(note.mediaKind.noun)"
        note.progress = 0
        save()

        let urls = note.kind == .pictures ? note.resolvePictures() : note.resolveSource().map { [$0] } ?? []
        guard !urls.isEmpty else {
            fail(note, note.kind == .pictures ? ClipError.notPicture : ClipError.fileMissing)
            return
        }
        let accessed = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { for url in accessed { url.stopAccessingSecurityScopedResource() } }

        let options = PipelineOptions.fromDefaults()
        let folder = note.thumbnailsFolder
        try? FileManager.default.removeItem(at: folder)

        let pipeline = pipeline
        let kind = note.kind
        let onUpdate: @Sendable (PipelineUpdate) -> Void = { update in
            Task { @MainActor in ProcessingCenter.shared.apply(update, to: id) }
        }
        let run = Task(priority: .userInitiated) {
            switch kind {
            case .video:
                try await pipeline.run(url: urls[0], options: options, thumbnailsFolder: folder, onUpdate: onUpdate)
            case .pictures:
                try await pipeline.run(pictures: urls, options: options, thumbnailsFolder: folder, onUpdate: onUpdate)
            case .text:
                throw CancellationError()
            }
        }
        currentRun = run
        defer { currentRun = nil }

        do {
            let result = try await run.value
            if !note.titleEdited { note.title = result.title }
            // Made again, the note's text is Ovyl's new text, not earlier edits.
            note.editedMarkdown = nil
            note.content = result.content
            note.updatedAt = .now
            note.duration = result.duration
            note.status = .ready
            note.stage = ""
            note.progress = 1
            note.errorMessage = nil
        } catch is CancellationError {
            markStopped(note)
        } catch {
            if run.isCancelled { markStopped(note) } else { fail(note, error) }
        }
        save()
    }

    private func apply(_ update: PipelineUpdate, to id: UUID) {
        guard processingID == id, let note = note(with: id), note.status == .processing else { return }
        // Between steps the note keeps saying what it last did.
        if update.stage != ProgressBoard.between { note.stage = update.stage }
        note.progress = max(note.progress, update.fraction)
    }

    private func fail(_ note: Note, _ error: any Error) {
        note.status = .failed
        note.stage = ""
        note.errorMessage = error.localizedDescription
        save()
    }

    private func markStopped(_ note: Note) {
        note.status = .failed
        note.stage = ""
        note.errorMessage = "Processing was stopped."
        save()
    }

    // MARK: Store

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([Note.self, Folder.self])
        // Tests run inside the app, so they keep to memory and never touch
        // the notes store of a copy of Ovyl that's open.
        if isRunningTests, let container = try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)) {
            return container
        }
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "Ovyl.store")
        // Another copy of Ovyl closing can hold the store a moment, so it's
        // tried again before it's thought unreadable.
        for attempt in 0..<3 {
            if let container = try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url)) {
                return container
            }
            if attempt < 2 { Thread.sleep(forTimeInterval: 0.5) }
        }
        // An unreadable store is set aside rather than crashing the app, with
        // its journal, so nothing written to it is left behind.
        let aside = folder.appending(path: "Ovyl-unreadable-\(Int(Date.now.timeIntervalSince1970)).store")
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.moveItem(at: URL(fileURLWithPath: url.path + suffix), to: URL(fileURLWithPath: aside.path + suffix))
        }
        if let container = try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url)) {
            return container
        }
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        } catch {
            fatalError("Ovyl couldn't create its notes store: \(error)")
        }
    }
}
