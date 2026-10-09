import AppKit
import SwiftUI

/// The middle pane for a note's media: the video, or one frame or picture
/// with zoom, on the dotted canvas.
struct MediaViewer: View {
    @Environment(Navigator.self) private var navigator
    @Environment(ProcessingCenter.self) private var center
    let note: Note
    let item: Int?
    let media: NoteMedia
    @FocusState private var focused: Bool

    private var items: [GalleryItem] { media.items(for: note) }

    /// The image shown: the chosen frame or picture, or a picture note's first.
    private var shownItem: Int? {
        if let item { return items.indices.contains(item) ? item : nil }
        return note.kind == .pictures && !items.isEmpty ? 0 : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            PaneToolbar {
                VStack(spacing: 1) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .medium))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ovylSecondary)
                }
                .lineLimit(1)
            } trailing: {
                PillGroup {
                    PillMenu(help: "More") { menuItems }
                }
                RightPaneToggle()
            }

            ZStack {
                DotGrid()
                if let index = shownItem {
                    ZoomableImage(url: items[index].imageURL)
                        .id(items[index].id)
                } else {
                    VideoHero(note: note, player: media.player) {}
                        .padding(40)
                }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onKeyPress(.escape) { navigator.goBack(); return .handled }
            .onAppear { focused = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ovylCanvas)
    }

    private var title: String {
        guard let index = shownItem else { return note.sourceName }
        let item = items[index]
        if let time = item.time { return "Frame at \(TimeFormat.clock(time))" }
        return item.title
    }

    private var subtitle: String {
        guard let index = shownItem else { return note.displayTitle }
        return "\(index + 1) of \(items.count) · \(note.displayTitle)"
    }

    @ViewBuilder
    private var menuItems: some View {
        if let index = shownItem {
            let item = items[index]
            Button("Copy Image", systemImage: "doc.on.doc") {
                if let image = ThumbnailCache.image(at: item.imageURL) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([image])
                }
            }
            if let time = item.time {
                Button("Play from \(TimeFormat.clock(time))", systemImage: "play") {
                    media.play(note, at: time)
                    navigator.go(.media(note.id, item: nil))
                }
            }
            Button(note.kind == .pictures ? "Show All Pictures" : "Show All Frames", systemImage: "square.grid.2x2") { navigator.go(.gallery(note.id)) }
        } else {
            Button("Show Frames", systemImage: "square.grid.2x2") { navigator.go(.gallery(note.id)) }
        }
        Button("Show in Finder", systemImage: "folder") { note.revealSource() }
        Divider()
        Button("Back to the Note", systemImage: "doc.text") { navigator.go(.note(note.id)) }
    }
}

/// An image that fits the pane, or is zoomed from 25% to 400% and scrolls.
struct ZoomableImage: View {
    let url: URL
    /// Nil to fit the pane.
    @State private var zoom: CGFloat?

    private static let steps: [CGFloat] = [0.25, 0.33, 0.5, 0.67, 0.8, 1, 1.25, 1.5, 2, 3, 4]

    var body: some View {
        GeometryReader { geo in
            if let image = ThumbnailCache.image(at: url), image.size.width > 0, image.size.height > 0 {
                let fit = min((geo.size.width - 80) / image.size.width, (geo.size.height - 120) / image.size.height, 2)
                let scale = zoom ?? max(fit, 0.05)
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: image.size.width * scale, height: image.size.height * scale)
                        .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
                        .padding(.horizontal, 40)
                        .padding(.top, 40)
                        .padding(.bottom, 80)
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                }
                .scrollIndicators(zoom == nil ? .never : .automatic)
                .overlay(alignment: .bottom) {
                    FloatingBar {
                        PillButton(symbol: "minus", help: "Zoom out") { zoom = Self.step(from: scale, by: -1) }
                            .disabled(scale <= Self.steps.first!)
                        Text("\(Int((scale * 100).rounded()))%")
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .frame(minWidth: 48)
                        PillButton(symbol: "plus", help: "Zoom in") { zoom = Self.step(from: scale, by: 1) }
                            .disabled(scale >= Self.steps.last!)
                        PillButton(symbol: "arrow.down.right.and.arrow.up.left", help: "Fit", isActive: zoom == nil) { zoom = nil }
                    }
                    .padding(.bottom, 16)
                }
            } else {
                EmptyState(symbol: "photo", title: "Image not found")
            }
        }
    }

    private static func step(from scale: CGFloat, by direction: Int) -> CGFloat {
        if direction > 0 { return steps.first { $0 > scale + 0.001 } ?? steps.last! }
        return steps.last { $0 < scale - 0.001 } ?? steps.first!
    }
}
