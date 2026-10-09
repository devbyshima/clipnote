import Foundation
import Observation
import SwiftData

/// Keeps Ovyl from cluttering the Mac. What Ovyl keeps is split in two:
///
/// - Your data, in Application Support: the notes, the frames and pictures
///   they show, and assistant chats. Removed only with the note or chat.
/// - What can be made again, in Caches and the temporary folder: the search
///   index, the speech model compiled for this Mac, and files used while
///   working. macOS may clear these when space runs low, and Ovyl clears
///   leftovers itself.
///
/// Originals are never copied in; notes point at them where they are.
@MainActor @Observable
final class StorageManager {
    static let shared = StorageManager()

    /// How much space each kind of thing takes, in bytes.
    struct Usage: Equatable {
        var notes: Int64 = 0
        var frames: Int64 = 0
        var chats: Int64 = 0
        var index: Int64 = 0
        var speechCache: Int64 = 0
        var temporary: Int64 = 0

        var total: Int64 { notes + frames + chats + index + speechCache + temporary }
        var clearable: Int64 { index + temporary }
    }

    private(set) var usage = Usage()
    private(set) var isMeasuring = false
    @ObservationIgnored private var swept = false

    private init() {}

    // MARK: Places

    nonisolated static var support: URL { .applicationSupportDirectory }
    nonisolated static var framesRoot: URL { Note.thumbnailsRoot }
    nonisolated static var chatsRoot: URL { support.appending(path: "Assistant", directoryHint: .isDirectory) }
    nonisolated static var indexRoot: URL { SearchIndex.defaultURL.deletingLastPathComponent() }
    nonisolated static var temporary: URL { FileManager.default.temporaryDirectory }

    /// Where Core ML keeps the speech model compiled for this Mac.
    nonisolated static var speechCacheRoot: URL {
        let bundle = Bundle.main.bundleIdentifier ?? "com.fulltimestudio.ovyl"
        return URL.cachesDirectory.appending(path: bundle, directoryHint: .isDirectory).appending(path: "com.apple.e5rt.e5bundlecache", directoryHint: .isDirectory)
    }

    // MARK: Sweeping

    /// Clears leftovers a little after launch, at low priority.
    func sweepSoon(_ center: ProcessingCenter) {
        guard !swept else { return }
        swept = true
        Task {
            try? await Task.sleep(for: .seconds(20))
            let noteIDs = Set(((try? center.context.fetch(FetchDescriptor<Note>())) ?? []).map(\.id))
            await Task.detached(priority: .utility) {
                Self.sweep(keeping: noteIDs)
            }.value
        }
    }

    /// Removes what nothing uses any more:
    /// - frame folders of notes that are gone,
    /// - notes stores set aside as unreadable more than 30 days ago,
    /// - temporary files more than a day old,
    /// - speech model builds older than the newest one, left by updates.
    nonisolated static func sweep(keeping noteIDs: Set<UUID>, now: Date = .now) {
        let files = FileManager.default
        for folder in contents(of: framesRoot) {
            guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
            if !noteIDs.contains(id) { try? files.removeItem(at: folder) }
        }
        for file in contents(of: support) where file.lastPathComponent.hasPrefix("Ovyl-unreadable-") {
            if let date = modified(file), now.timeIntervalSince(date) > 30 * 86_400 { try? files.removeItem(at: file) }
        }
        for item in contents(of: temporary) where !item.lastPathComponent.contains("savedState") {
            if let date = modified(item), now.timeIntervalSince(date) > 86_400 { try? files.removeItem(at: item) }
        }
        let builds = contents(of: speechCacheRoot).sorted { (modified($0) ?? .distantPast) > (modified($1) ?? .distantPast) }
        for old in builds.dropFirst() { try? files.removeItem(at: old) }
    }

    // MARK: Clearing

    /// Empties what can be made again right away: the search index (rebuilt
    /// in the background) and temporary files.
    func clearCaches(_ center: ProcessingCenter) async {
        await Task.detached(priority: .utility) {
            for item in Self.contents(of: Self.temporary) where !item.lastPathComponent.contains("savedState") {
                try? FileManager.default.removeItem(at: item)
            }
        }.value
        LibraryIndexer.shared.rebuild(center)
        await measure()
    }

    /// Removes the speech model compiled for this Mac. It's built again the
    /// next time a video is transcribed, which takes a few minutes once.
    func clearSpeechCache() async {
        await Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: Self.speechCacheRoot)
        }.value
        // Without the compiled form, the next load prepares it again first.
        UserDefaults.standard.removeObject(forKey: "whisperNeuralEngineCompiled")
        await measure()
    }

    // MARK: Measuring

    func measure() async {
        isMeasuring = true
        usage = await Task.detached(priority: .utility) { Self.currentUsage() }.value
        isMeasuring = false
    }

    nonisolated static func currentUsage() -> Usage {
        var usage = Usage()
        for item in contents(of: support) {
            let name = item.lastPathComponent
            if name.hasPrefix("Ovyl") || name.hasPrefix(".Ovyl") || name.hasPrefix("default.store") {
                usage.notes += size(of: item)
            }
        }
        usage.frames = size(of: framesRoot)
        usage.chats = size(of: chatsRoot)
        usage.index = size(of: indexRoot)
        usage.speechCache = size(of: speechCacheRoot)
        usage.temporary = contents(of: temporary)
            .filter { !$0.lastPathComponent.contains("savedState") }
            .reduce(0) { $0 + size(of: $1) }
        return usage
    }

    nonisolated private static func contents(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [])) ?? []
    }

    nonisolated private static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    nonisolated static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        guard values.isDirectory == true else { return Int64(values.totalFileAllocatedSize ?? 0) }
        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        while let file = enumerator?.nextObject() as? URL {
            total += Int64((try? file.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
