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
    private(set) var processingID: UUID?
    private(set) var speechPhase: WhisperService.Phase = .idle

    @ObservationIgnored private var queue: [UUID] = []
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var currentRun: Task<PipelineResult, any Error>?
    @ObservationIgnored private let pipeline = ClipPipeline()
    @ObservationIgnored private var started = false

    private init() {
        container = Self.makeContainer()
    }

    var context: ModelContext { container.mainContext }

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Picks up notes left unfinished when the app last quit, and loads the
    /// speech model in the background so the first video starts quickly.
    func start() {
        guard !started, !Self.isRunningTests else { return }
        started = true
        let unfinished = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.createdAt)])
        for note in (try? context.fetch(unfinished)) ?? [] where note.status == .queued || note.status == .processing {
            enqueue(note)
        }
        prepareSpeechModel()
    }

    func prepareSpeechModel() {
        guard WhisperEngine.isBundled else { return }
        Task {
            let phases = await WhisperService.shared.phases()
            await WhisperService.shared.prepare()
            for await phase in phases { speechPhase = phase }
        }
    }

    // MARK: Importing

    /// Makes a note from each video or audio file, and one note from all
    /// the pictures, in file name order.
    @discardableResult
    func importFiles(_ urls: [URL]) -> [Note] {
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
            case nil:
                skipped.append(url.lastPathComponent)
            }
        }
        if !pictures.isEmpty {
            let note = Note(pictures: Self.inReadingOrder(pictures))
            context.insert(note)
            created.append(note)
        }
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
        if processingID == note.id {
            currentRun?.cancel()
        } else {
            queue.removeAll { $0 == note.id }
            markStopped(note)
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

        note.status = .processing
        note.stage = note.kind == .pictures ? "Opening pictures" : "Opening video"
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
            }
        }
        currentRun = run
        defer { currentRun = nil }

        do {
            let result = try await run.value
            if !note.titleEdited { note.title = result.title }
            note.content = result.content
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
        note.stage = update.stage
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
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "Ovyl.store")
        let schema = Schema([Note.self])
        if let container = try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url)) {
            return container
        }
        // An unreadable store is set aside rather than crashing the app.
        let aside = folder.appending(path: "Ovyl-unreadable-\(Int(Date.now.timeIntervalSince1970)).store")
        try? FileManager.default.moveItem(at: url, to: aside)
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
