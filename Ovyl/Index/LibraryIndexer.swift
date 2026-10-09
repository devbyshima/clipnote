import Foundation
import SwiftData

/// Keeps the search index in step with the notes. Whenever the store saves,
/// it compares each note's fingerprint with what it last indexed and
/// reindexes what changed; on launch it reconciles the whole library.
@MainActor
final class LibraryIndexer {
    static let shared = LibraryIndexer()

    private let index = SearchIndex.shared
    private var indexed: [UUID: String] = [:]
    private var pass: Task<Void, Never>?
    private var again = false
    private var observer: (any NSObjectProtocol)?

    private init() {}

    /// Reconciles now and after every save.
    func start(_ center: ProcessingCenter) {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { LibraryIndexer.shared.schedule(center) }
        }
        schedule(center, delay: .zero, full: true)
    }

    /// Indexes the library again from scratch, as after clearing caches.
    func rebuild(_ center: ProcessingCenter) {
        indexed = [:]
        Task {
            await index.clear()
            schedule(center, delay: .zero, full: true)
        }
    }

    /// Indexes whatever changed, a moment after the last save, so a burst of
    /// saves while typing makes one pass.
    private func schedule(_ center: ProcessingCenter, delay: Duration = .milliseconds(700), full: Bool = false) {
        if pass != nil {
            again = true
            return
        }
        pass = Task {
            try? await Task.sleep(for: delay)
            await run(center, full: full)
            pass = nil
            if again {
                again = false
                schedule(center)
            }
        }
    }

    /// Waits for any pass under way, then makes one more; for tests and the
    /// assistant, which want the index current.
    func catchUp(_ center: ProcessingCenter) async {
        while let pass { await pass.value }
        await run(center, full: false)
    }

    private func run(_ center: ProcessingCenter, full: Bool) async {
        let notes = (try? center.context.fetch(FetchDescriptor<Note>())) ?? []
        let folders = (try? center.context.fetch(FetchDescriptor<Folder>())) ?? []
        var folderNames: [UUID: String] = [:]
        for folder in folders { folderNames[folder.id] = folder.name }

        // Only finished notes have text to index.
        var current: [UUID: String] = [:]
        for note in notes where note.status == .ready {
            current[note.id] = note.indexFingerprint(folderName: note.folderID.flatMap { folderNames[$0] })
        }

        let stale: [UUID]
        if full {
            stale = await index.reconcile(current)
        } else {
            for id in indexed.keys where current[id] == nil { await index.remove(id) }
            stale = current.filter { indexed[$0.key] != $0.value }.map(\.key)
        }
        for id in stale {
            guard let note = notes.first(where: { $0.id == id }) else { continue }
            let snapshot = note.snapshot(folderName: note.folderID.flatMap { folderNames[$0] })
            await index.update(snapshot)
        }
        indexed = current
    }
}
