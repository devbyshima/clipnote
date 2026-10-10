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
                if isMissing {
                    MissingMediaState(isAudio: note.mediaKind == .audio, fileName: note.sourceName) { isLocating = true }
                        .padding(.bottom, 64)
                } else {
                    DotGrid()
                    hero
                        .padding(.horizontal, 28)
                        .padding(.top, 24)
                        .padding(.bottom, 84)
                }
            }
            .task(id: note.id) { if note.kind == .video { media.player.load(note) } }
            .overlay(alignment: .bottom) {
                FloatingBar {
                    if note.hasGallery {
                        BarButton(symbol: "square.grid.2x2", title: note.kind == .pictures ? "Pictures" : "Frames", key: "F") { navigator.go(.gallery(note.id)) }
                    }
                    BarButton(symbol: "info.circle", title: "Info", key: "I") { navigator.go(.media(note.id, item: nil)) }
                    BarButton(symbol: "trash", title: "Delete", key: "D") { navigator.pendingDelete = note.id }
                }
                .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background, ignoresSafeAreaEdges: .top)
        .modifier(LocateSource(note: note, player: media.player, isPresented: $isLocating))
    }

    /// The note's video or recording has moved, so there's nothing to play.
    private var isMissing: Bool { note.kind == .video && media.player.isUnavailable }

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
                    .shadow(color: Palette.shadow, radius: 10, y: 3)
                    .onTapGesture(count: 2) { navigator.go(.media(note.id, item: 0)) }
            } else {
                EmptyState(symbol: "photo", title: "No pictures yet")
            }
        } else {
            VideoHero(note: note, player: media.player) { isLocating = true }
        }
    }
}

/// The file picker that finds a note's moved video or recording, and plays
/// it from its new place.
struct LocateSource: ViewModifier {
    @Environment(ProcessingCenter.self) private var center
    let note: Note
    let player: PlayerModel
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.fileImporter(isPresented: $isPresented, allowedContentTypes: [.audiovisualContent]) { result in
            guard case .success(let url) = result else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            note.sourceBookmark = try? Note.bookmark(for: url)
            note.sourceName = url.lastPathComponent
            center.save()
            player.reload(note)
        }
    }
}

/// A note's video sized to fit, or a bar for audio. A moved file shows
/// `MissingMediaState` in its place, from the view around this one.
struct VideoHero: View {
    let note: Note
    let player: PlayerModel
    var locate: () -> Void

    var body: some View {
        Group {
            if player.isUnavailable {
                Color.clear
            } else if let avPlayer = player.player {
                if player.hasVideo {
                    PlayerView(player: avPlayer)
                        .aspectRatio(player.aspectRatio ?? 16 / 9, contentMode: .fit)
                        .background(Palette.media)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        // A hairline, so black video still has an edge on a black page.
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                        .shadow(color: Palette.shadow, radius: 12, y: 4)
                } else {
                    PlayerView(player: avPlayer)
                        .frame(height: 56)
                        .frame(maxWidth: 520)
                        .background(Palette.media)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                }
            } else {
                Palette.media
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                    .overlay {
                        LogoLoader(.loading)
                            .frame(width: 30, height: 30)
                            .foregroundStyle(Palette.onDark.opacity(0.85))
                    }
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
                .fill(Palette.fill)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(Palette.textSecondary)
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
