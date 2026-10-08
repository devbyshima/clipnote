import Foundation
import SwiftData

enum NoteStatus: String, Codable {
    case queued, processing, ready, failed
}

/// What a note was made from.
enum NoteKind: String, Codable {
    /// A video or audio file.
    case video
    /// One or more pictures, read in order.
    case pictures
}

@Model
final class Note {
    var id = UUID()
    var title = ""
    /// True once the user renames the note, so reprocessing keeps their title.
    var titleEdited = false
    var createdAt = Date.now
    var sourceName = ""
    /// Security-scoped bookmark to the original video (or the first picture),
    /// for playback and reprocessing.
    var sourceBookmark: Data?
    var kindRaw = NoteKind.video.rawValue
    /// Bookmarks to every picture, in order, for a note made from pictures.
    var pictureBookmarks: [Data] = []
    var duration: Double = 0
    var statusRaw = NoteStatus.queued.rawValue
    var stage = ""
    var progress: Double = 0
    var errorMessage: String?
    @Attribute(.externalStorage) var contentData: Data?
    /// Plain text of the whole note, for sidebar search.
    var searchText = ""

    init(sourceName: String, sourceBookmark: Data?) {
        self.sourceName = sourceName
        self.sourceBookmark = sourceBookmark
        self.title = Self.title(fromFileName: sourceName)
    }

    /// A note made from pictures, read in the order given.
    init(pictures: [(name: String, bookmark: Data?)]) {
        let first = pictures.first?.name ?? ""
        self.sourceName = pictures.count > 1 ? "\(first) and \(pictures.count - 1) more" : first
        self.kindRaw = NoteKind.pictures.rawValue
        self.pictureBookmarks = pictures.compactMap(\.bookmark)
        self.sourceBookmark = pictureBookmarks.first
        self.title = Self.title(fromFileName: first)
    }

    var kind: NoteKind { NoteKind(rawValue: kindRaw) ?? .video }

    var status: NoteStatus {
        get { NoteStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    var content: NoteContent? {
        get { contentData.flatMap { try? JSONDecoder().decode(NoteContent.self, from: $0) } }
        set {
            contentData = newValue.flatMap { try? JSONEncoder().encode($0) }
            searchText = newValue?.plainText ?? ""
        }
    }

    var displayTitle: String {
        title.isEmpty ? Self.title(fromFileName: sourceName) : title
    }

    var thumbnailsFolder: URL { Self.thumbnailsRoot.appending(path: id.uuidString, directoryHint: .isDirectory) }

    nonisolated static var thumbnailsRoot: URL {
        URL.applicationSupportDirectory.appending(path: "Thumbnails", directoryHint: .isDirectory)
    }

    /// "team_sync-2026-03 FINAL.mov" → "Team Sync 2026 03 Final".
    nonisolated static func title(fromFileName name: String) -> String {
        // A bare extension such as ".mp4" has no name to use.
        let base = name.hasPrefix(".") && !name.dropFirst().contains(".") ? "" : (name as NSString).deletingPathExtension
        let words = base
            .replacing(/[_\-.]+/, with: " ")
            .split(separator: " ")
            .map { word -> String in
                let w = String(word)
                let first = String(w.prefix(1)).uppercased()
                return w == w.uppercased() && w.count > 1 && w.contains(where: \.isLetter)
                    ? first + w.dropFirst().lowercased()
                    : first + w.dropFirst()
            }
        let title = words.joined(separator: " ")
        return title.isEmpty ? "Untitled Video" : title
    }
}

extension Note {
    /// Resolves the bookmark to the original file. The caller must balance
    /// `startAccessingSecurityScopedResource` on the returned URL.
    func resolveSource() -> URL? {
        guard let sourceBookmark, let resolved = Self.resolve(sourceBookmark) else { return nil }
        if let fresh = resolved.fresh { self.sourceBookmark = fresh }
        return resolved.url
    }

    /// The pictures that can still be found, in order. The caller must
    /// balance `startAccessingSecurityScopedResource` on each URL.
    func resolvePictures() -> [URL] {
        var urls: [URL] = []
        for (index, bookmark) in pictureBookmarks.enumerated() {
            guard let resolved = Self.resolve(bookmark) else { continue }
            if let fresh = resolved.fresh { pictureBookmarks[index] = fresh }
            urls.append(resolved.url)
        }
        return urls
    }

    /// The bookmark's URL, and a fresh bookmark when the old one went stale.
    private static func resolve(_ bookmark: Data) -> (url: URL, fresh: Data?)? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        guard stale, url.startAccessingSecurityScopedResource() else { return (url, nil) }
        defer { url.stopAccessingSecurityScopedResource() }
        return (url, try? Self.bookmark(for: url))
    }

    static func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}
