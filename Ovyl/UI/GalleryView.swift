import SwiftUI

/// The middle pane for a note's frames (or pictures): a grid that keeps each
/// image's shape, rows filling the width.
struct GalleryView: View {
    @Environment(Navigator.self) private var navigator
    let note: Note
    let media: NoteMedia
    @AppStorage("galleryLarge") private var large = false

    private var items: [GalleryItem] { media.items(for: note) }
    private var isPictures: Bool { note.kind == .pictures }

    var body: some View {
        VStack(spacing: 0) {
            PaneToolbar {
                HStack(spacing: 7) {
                    Image(systemName: isPictures ? "photo.on.rectangle" : "film")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.ovylAccent)
                    Text(isPictures ? "Pictures" : "Frames")
                        .font(.system(size: 14, weight: .medium))
                    CountBadge(count: items.count)
                }
            } trailing: {
                RightPaneToggle()
            }

            if items.isEmpty {
                EmptyState(
                    symbol: isPictures ? "photo" : "film",
                    title: isPictures ? "No pictures" : "No frames",
                    message: isPictures
                        ? "The pictures couldn't be read."
                        : "Ovyl grabs a frame whenever text shows on screen, such as a slide. This video had none."
                )
            } else {
                ScrollView {
                    JustifiedLayout(rowHeight: large ? 240 : 150, spacing: 10) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            GalleryTile(item: item) { navigator.go(.media(note.id, item: index)) }
                                .layoutValue(key: AspectRatioKey.self, value: aspectRatio(of: item))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 80)
                }
                .overlay(alignment: .bottom) {
                    FloatingBar {
                        PillButton(symbol: "square.grid.3x3", help: "Smaller", isActive: !large) { large = false }
                        PillButton(symbol: "square.grid.2x2", help: "Larger", isActive: large) { large = true }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ovylBG)
    }

    private func aspectRatio(of item: GalleryItem) -> CGFloat {
        guard let size = ThumbnailCache.image(at: item.imageURL)?.size, size.height > 0 else { return 16 / 9 }
        return size.width / size.height
    }
}

struct GalleryTile: View {
    let item: GalleryItem
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Thumbnail(url: item.imageURL)
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isHovered ? Color.ovylAccent : Color.ovylBorder, lineWidth: isHovered ? 2 : 0.5)
                }
                .overlay(alignment: .bottomLeading) {
                    if isHovered {
                        Text(item.time.map(TimeFormat.clock) ?? item.title)
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .lineLimit(1)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.6), in: Capsule())
                            .padding(8)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help(item.title)
    }
}

/// Width over height of a gallery item, for `JustifiedLayout`.
struct AspectRatioKey: LayoutValueKey {
    static let defaultValue: CGFloat = 16 / 9
}

/// Lays items out in rows that fill the width, each row as tall as it needs
/// to be for its items to keep their shape. The last row isn't stretched.
struct JustifiedLayout: Layout {
    var rowHeight: CGFloat
    var spacing: CGFloat

    struct Row {
        var indices: Range<Int>
        var height: CGFloat
    }

    func rows(for ratios: [CGFloat], width: CGFloat) -> [Row] {
        guard width > 0 else { return [] }
        var rows: [Row] = []
        var start = 0
        var sum: CGFloat = 0
        for (index, ratio) in ratios.enumerated() {
            sum += ratio
            let count = CGFloat(index - start + 1)
            let natural = sum * rowHeight + spacing * (count - 1)
            if natural >= width {
                let height = (width - spacing * (count - 1)) / sum
                rows.append(Row(indices: start..<(index + 1), height: height))
                start = index + 1
                sum = 0
            }
        }
        if start < ratios.count {
            rows.append(Row(indices: start..<ratios.count, height: rowHeight))
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 800
        let rows = rows(for: subviews.map { $0[AspectRatioKey.self] }, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ratios = subviews.map { $0[AspectRatioKey.self] }
        var y = bounds.minY
        for row in rows(for: ratios, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let width = ratios[index] * row.height
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: width, height: row.height))
                x += width + spacing
            }
            y += row.height + spacing
        }
    }
}
