import AppKit
import Observation
import SwiftUI

/// The open note's media: one player shared by the right pane and the middle,
/// so the video keeps its place when it moves between them.
@MainActor @Observable
final class NoteMedia {
    let player = PlayerModel()
    private(set) var noteID: UUID?
    @ObservationIgnored private var cachedItems: [GalleryItem] = []
    @ObservationIgnored private var cacheKey: String?

    /// Switches to another note's media, stopping the last one's video.
    func show(_ note: Note?) {
        guard note?.id != noteID else { return }
        player.unload()
        noteID = note?.id
    }

    func items(for note: Note) -> [GalleryItem] {
        let key = "\(note.id)-\(note.statusRaw)-\(note.contentData?.count ?? 0)"
        if key != cacheKey {
            cachedItems = GalleryItem.items(for: note)
            cacheKey = key
        }
        return cachedItems
    }

    func play(_ note: Note, at seconds: TimeInterval) {
        show(note)
        player.load(note)
        player.seek(to: seconds)
    }
}

/// A frame grabbed from a video, or a picture a note was made from.
struct GalleryItem: Identifiable, Equatable {
    let id: UUID
    let imageURL: URL
    /// When the frame was on screen; nil for a picture.
    var time: TimeInterval?
    var title: String
    var lines: [String]

    static func items(for note: Note) -> [GalleryItem] {
        guard let content = note.content else { return [] }
        let folder = note.thumbnailsFolder
        if note.kind == .pictures {
            return content.pictures.compactMap { picture in
                picture.thumbnail.map {
                    GalleryItem(id: picture.id, imageURL: folder.appending(path: $0), time: nil, title: picture.name, lines: [])
                }
            }
        }
        return content.screenMoments
            .filter { $0.thumbnail != nil }
            .sorted { $0.start < $1.start }
            .map { moment in
                GalleryItem(
                    id: moment.id, imageURL: folder.appending(path: moment.thumbnail ?? ""), time: moment.start,
                    title: moment.title ?? moment.lines.first ?? "On screen", lines: moment.lines
                )
            }
    }
}

/// The right pane beside a note: its video (or first picture) on a dotted
/// canvas, and a bar to open its frames, show the media's info, or delete.
struct MediaPane: View {
    @Environment(ProcessingCenter.self) private var center
    @Environment(Navigator.self) private var navigator
    @AppStorage("showMedia") private var showRightPane = true
    let note: Note
    let media: NoteMedia
    @State private var isLocating = false

    private var items: [GalleryItem] { media.items(for: note) }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ZStack {
                DotGrid()
                hero
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 84)
            }
            .overlay(alignment: .bottom) {
                FloatingBar {
                    BarButton(symbol: "square.grid.2x2", title: note.kind == .pictures ? "Pictures" : "Frames", key: "F") { navigator.go(.gallery(note.id)) }
                    BarButton(symbol: "info.circle", title: "Info", key: "I") { navigator.go(.media(note.id, item: nil)) }
                    BarButton(symbol: "trash", title: "Delete", key: "D") { navigator.pendingDelete = note.id }
                }
                .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ovylCanvas, ignoresSafeAreaEdges: .top)
        .fileImporter(isPresented: $isLocating, allowedContentTypes: [.audiovisualContent]) { result in
            guard case .success(let url) = result else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            note.sourceBookmark = try? Note.bookmark(for: url)
            note.sourceName = url.lastPathComponent
            center.save()
            media.player.reload(note)
        }
    }

    private var toolbar: some View {
        CenteredBar {
            PillGroup {
                PillButton(symbol: "xmark", help: "Close (⌘P)") { showRightPane = false }
                PillButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Open in the middle (I)") {
                    navigator.go(.media(note.id, item: nil))
                }
            }
        } title: {
            Text(note.sourceName)
                .font(.system(size: 13, weight: .medium))
                .truncationMode(.middle)
        } trailing: {
            PillGroup {
                PillMenu(help: "More") {
                    if note.kind != .text {
                        Button("Show in Finder", systemImage: "folder") { note.revealSource() }
                    }
                    if note.kind == .video {
                        Button(note.mediaKind == .audio ? "Locate Recording…" : "Locate Video…", systemImage: "magnifyingglass") { isLocating = true }
                    }
                    if note.kind != .text {
                        Divider()
                        Button("Process Again", systemImage: "arrow.clockwise") { center.enqueue(note) }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: MainWindowStyler.barHeight)
        .background(WindowDragHandle())
    }

    @ViewBuilder
    private var hero: some View {
        if note.kind == .text {
            EmptyState(symbol: "doc.text", title: "Written in Ovyl", message: "This note has no video, audio or pictures.")
        } else if note.kind == .pictures {
            if let first = items.first {
                Thumbnail(url: first.imageURL)
                    .aspectRatio(contentMode: .fit)
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
                    .onTapGesture(count: 2) { navigator.go(.media(note.id, item: 0)) }
            } else {
                EmptyState(symbol: "photo", title: "No pictures yet")
            }
        } else {
            VideoHero(note: note, player: media.player) { isLocating = true }
        }
    }
}

/// A note's video sized to fit, or a bar for audio, or a way to find a video
/// that moved.
struct VideoHero: View {
    let note: Note
    let player: PlayerModel
    var locate: () -> Void

    var body: some View {
        Group {
            if player.isUnavailable {
                VStack(spacing: 10) {
                    Image(systemName: note.mediaKind == .audio ? "waveform.slash" : "video.slash")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.ovylSecondary)
                    Text(note.mediaKind == .audio ? "Recording not found" : "Video not found")
                        .font(.system(size: 15, weight: .semibold))
                    Text("\(note.sourceName) was moved or deleted. The note is safe.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.ovylSecondary)
                        .multilineTextAlignment(.center)
                    FilledButton(title: "Locate…", action: locate)
                        .padding(.top, 4)
                }
                .padding(24)
                .frame(maxWidth: 300)
                .background(Color.ovylSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if let avPlayer = player.player {
                if player.hasVideo {
                    PlayerView(player: avPlayer)
                        .aspectRatio(player.aspectRatio ?? 16 / 9, contentMode: .fit)
                        .background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                } else {
                    PlayerView(player: avPlayer)
                        .frame(height: 56)
                        .frame(maxWidth: 520)
                        .background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            } else {
                Color.black
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay { ProgressView().controlSize(.small).tint(.white) }
            }
        }
        .task(id: note.id) { player.load(note) }
    }
}

/// An image from the note's thumbnail folder, cached.
struct Thumbnail: View {
    let url: URL

    var body: some View {
        if let image = ThumbnailCache.image(at: url) {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            Rectangle()
                .fill(Color.ovylFill)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
        }
    }
}

@MainActor
enum ThumbnailCache {
    private static let cache = NSCache<NSURL, NSImage>()

    static func image(at url: URL) -> NSImage? {
        if let image = cache.object(forKey: url as NSURL) { return image }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
