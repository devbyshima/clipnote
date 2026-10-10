import SwiftUI

// Every empty state has the same frame: a faint grid filling the pane, its
// cells marked with times (for a video) or days (for notes), a headline in
// the middle with one word in handwriting and the grid cleared under it,
// and moving cards set into the cells around it.

/// What the grid's cells are marked with.
enum GridMarks {
    /// Times through a video, `every` seconds a cell: "0:00", "0:30", …
    case times(every: Int)
    /// Days of the month, starting two weeks before this one, today in bold.
    case days

    func label(column: Int, row: Int, now: Date = .now, calendar: Calendar = .current) -> (text: String, isBold: Bool) {
        let index = row * GridLayout.columns + column
        switch self {
        case .times(let every):
            let seconds = index * every
            return (String(format: "%d:%02d", seconds / 60, seconds % 60), false)
        case .days:
            let today = calendar.startOfDay(for: now)
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
            let first = calendar.date(byAdding: .day, value: -14, to: weekStart) ?? weekStart
            let date = calendar.date(byAdding: .day, value: index, to: first) ?? first
            return ("\(calendar.component(.day, from: date))", calendar.isDate(date, inSameDayAs: today))
        }
    }
}

/// The grid's cells: 7 across and 5 down, read like lines of text, centered
/// and sized to the pane.
struct GridLayout {
    static let columns = 7
    static let rows = 5

    let size: CGSize
    let cell: CGSize
    let origin: CGPoint
    /// Where the headline is, once it's laid out, for the pieces to keep clear of.
    var headline: CGRect?

    init(size: CGSize) {
        self.size = size
        // All five rows fit the height, so cards in the top and bottom rows show whole.
        cell = CGSize(width: min(max(size.width / 5.4, 112), 180), height: min(max(size.height / 5, 104), 150))
        origin = CGPoint(
            x: (size.width - cell.width * CGFloat(Self.columns)) / 2,
            y: (size.height - cell.height * CGFloat(Self.rows)) / 2
        )
    }

    func with(headline: CGRect?) -> GridLayout {
        var layout = self
        layout.headline = headline
        return layout
    }

    /// Where a card sits in a cell: under the cell's mark, inset from the edges.
    func cardFrame(column: Int, row: Int) -> CGRect {
        CGRect(
            x: origin.x + CGFloat(column) * cell.width + 8,
            y: origin.y + CGFloat(row) * cell.height + 26,
            width: min(cell.width - 16, 158), height: 44
        )
    }

    /// A point as a fraction of the pane, for anchoring scale effects.
    func unit(_ point: CGPoint) -> UnitPoint {
        UnitPoint(x: size.width > 0 ? point.x / size.width : 0.5, y: size.height > 0 ? point.y / size.height : 0.5)
    }

    /// The cells around the headline that cards go in, clockwise from the
    /// upper left, leaving the bottom row free for short windows.
    static let ring = [(1, 1), (3, 0), (5, 1), (5, 3), (1, 3)]

    /// How far pieces stay from the pane's edges.
    static let margin: CGFloat = 10

    /// Where each piece goes: at its own cell's card corner if it fits there
    /// whole, inside the pane and clear of the headline and the pieces
    /// placed before it; else in the nearest cell, up to two away, where it
    /// does; else nowhere, and it's left out. So a narrow or short pane
    /// shows fewer pieces rather than cut-off ones. Nearer cells are tried
    /// first, up to three away.
    func place(_ pieces: [GridPiece]) -> [CGPoint?] {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: Self.margin, dy: Self.margin)
        // The headline's bounds already hold 20 points of room each side.
        let keepClear = headline.map { $0.insetBy(dx: 4, dy: -8) }
        var taken: [CGRect] = []
        var used: Set<Int> = []
        return pieces.map { piece in
            let candidates = (0..<Self.rows).flatMap { row in (0..<Self.columns).map { (column: $0, row: row) } }
                .map { cell in (cell: cell, distance: abs(cell.column - piece.cell.column) + abs(cell.row - piece.cell.row)) }
                .filter { $0.distance <= 3 && !used.contains($0.cell.row * Self.columns + $0.cell.column) }
                // Nearest first; at equal distance, stay in the same row, then move inward.
                .sorted {
                    ($0.distance, abs($0.cell.row - piece.cell.row), abs($0.cell.column - 3))
                        < ($1.distance, abs($1.cell.row - piece.cell.row), abs($1.cell.column - 3))
                }
            for candidate in candidates {
                let corner = cardFrame(column: candidate.cell.column, row: candidate.cell.row).origin
                let rect = CGRect(
                    x: corner.x - piece.outset.leading, y: corner.y - piece.outset.top,
                    width: piece.size.width + piece.outset.leading + piece.outset.trailing,
                    height: piece.size.height + piece.outset.top + piece.outset.bottom
                )
                guard bounds.contains(rect),
                      keepClear.map({ !$0.intersects(rect) }) ?? true,
                      !taken.contains(where: { $0.insetBy(dx: -8, dy: -8).intersects(rect) })
                else { continue }
                taken.append(rect)
                used.insert(candidate.cell.row * Self.columns + candidate.cell.column)
                return corner
            }
            return nil
        }
    }
}

/// Something to set on the grid: the cell it would like, how much room it
/// takes from that cell's card corner (its remark included), and how far
/// it reaches past that, such as a label above it.
struct GridPiece {
    let cell: (column: Int, row: Int)
    let size: CGSize
    var outset = EdgeInsets()

    init(_ cell: (Int, Int), size: CGSize, outset: EdgeInsets = EdgeInsets()) {
        self.cell = (column: cell.0, row: cell.1)
        self.size = size
        self.outset = outset
    }
}

/// The faint grid: hairlines and a mark in each cell's corner, fading out
/// toward the edges and around the headline. A mark is drawn only where it
/// shows whole: inside the pane and clear of the headline.
struct GridBackdrop: View {
    let layout: GridLayout
    let marks: GridMarks
    let hole: CGRect

    var body: some View {
        Canvas { context, size in
            var lines = Path()
            for column in 0...GridLayout.columns {
                let x = layout.origin.x + CGFloat(column) * layout.cell.width
                lines.move(to: CGPoint(x: x, y: layout.origin.y))
                lines.addLine(to: CGPoint(x: x, y: layout.origin.y + CGFloat(GridLayout.rows) * layout.cell.height))
            }
            for row in 0...GridLayout.rows {
                let y = layout.origin.y + CGFloat(row) * layout.cell.height
                lines.move(to: CGPoint(x: layout.origin.x, y: y))
                lines.addLine(to: CGPoint(x: layout.origin.x + CGFloat(GridLayout.columns) * layout.cell.width, y: y))
            }
            context.stroke(lines, with: .color(SceneColor.line), lineWidth: 1)

            for row in 0..<GridLayout.rows {
                for column in 0..<GridLayout.columns {
                    let mark = marks.label(column: column, row: row)
                    let label = Text(mark.text)
                        .font(.system(size: 10.5, weight: mark.isBold ? .bold : .medium).monospacedDigit())
                        .foregroundStyle(mark.isBold ? Palette.textPrimary.opacity(0.75) : SceneColor.number)
                    let point = CGPoint(x: layout.origin.x + CGFloat(column) * layout.cell.width + 9, y: layout.origin.y + CGFloat(row) * layout.cell.height + 8)
                    let resolved = context.resolve(label)
                    let rect = CGRect(origin: point, size: resolved.measure(in: CGSize(width: 200, height: 40)))
                    let pane = CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4)
                    // The headline's clearing reaches 35 by 25 points past it, and blurs.
                    let clearing = hole.width > 0 ? hole.insetBy(dx: -48, dy: -38) : .null
                    guard pane.contains(rect), !clearing.intersects(rect) else { continue }
                    context.draw(resolved, at: point, anchor: .topLeading)
                }
            }
        }
        .mask {
            ZStack {
                EllipticalGradient(
                    stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.5), .init(color: .clear, location: 1)],
                    center: .center, startRadiusFraction: 0, endRadiusFraction: 0.55
                )
                if hole.width > 0 {
                    RoundedRectangle(cornerRadius: 40)
                        .frame(width: hole.width + 70, height: hole.height + 50)
                        .position(x: hole.midX, y: hole.midY)
                        .blur(radius: 26)
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()
        }
        .allowsHitTesting(false)
    }
}

/// An empty state: the grid filling the pane, a headline in the middle, and
/// pieces placed on the grid above both. Pieces get the grid, the time, and
/// where the headline's `sceneTarget` sits, if it marks one.
struct EmptyCanvas<Pieces: View, Headline: View>: View {
    let marks: GridMarks
    var still: Double
    @ViewBuilder let pieces: (GridLayout, Double, CGRect?) -> Pieces
    @ViewBuilder let headline: (Double) -> Headline

    /// Large panes show the whole scene larger, up to half again, so it
    /// fills a big display instead of sitting small in the middle.
    static func scale(for size: CGSize) -> CGFloat {
        min(1.5, max(1, min(size.width / 1100, size.height / 780)))
    }

    var body: some View {
        GeometryReader { outer in
            let scale = Self.scale(for: outer.size)
            scene(CGSize(width: outer.size.width / scale, height: outer.size.height / scale))
                .scaleEffect(scale)
                .frame(width: outer.size.width, height: outer.size.height)
        }
    }

    private func scene(_ size: CGSize) -> some View {
        GeometryReader { geo in
            let layout = GridLayout(size: geo.size)
            MotionClock(still: still) { t in
                headline(t)
                    .transformAnchorPreference(key: CanvasMarks.self, value: .bounds) { $0.headline = $1 }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .overlayPreferenceValue(CanvasMarks.self) { anchors in
                        GeometryReader { proxy in
                            pieces(layout.with(headline: anchors.headline.map { proxy[$0] }), t, anchors.target.map { proxy[$0] })
                        }
                    }
            }
            .backgroundPreferenceValue(CanvasMarks.self) { anchors in
                GeometryReader { proxy in
                    GridBackdrop(layout: layout, marks: marks, hole: anchors.headline.map { proxy[$0] } ?? .zero)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Where the headline is, and the spot in it that the pieces move toward
/// (such as the folder), passed up to the canvas.
struct CanvasMarks: PreferenceKey {
    struct Value {
        var headline: Anchor<CGRect>?
        var target: Anchor<CGRect>?
    }

    static let defaultValue = Value()
    static func reduce(value: inout Value, nextValue: () -> Value) {
        let next = nextValue()
        value.headline = value.headline ?? next.headline
        value.target = value.target ?? next.target
    }
}

extension View {
    /// Marks this view as where an empty state's pieces head for.
    func sceneTarget() -> some View {
        transformAnchorPreference(key: CanvasMarks.self, value: .bounds) { $0.target = $1 }
    }
}

/// The headline every empty state shares: a quiet first line, a second line
/// with one word in handwriting, a short message, and an optional wide
/// button, with an optional picture above.
struct EmptyHeadline<Art: View>: View {
    let first: String
    var lead: String = ""
    let written: String
    var trail: String = "."
    let message: String
    var action: (title: String, run: () -> Void)?
    let t: Double
    @ViewBuilder var art: Art

    /// Long words (a search, say) are written smaller.
    private var writtenSize: CGFloat {
        written.count <= 8 ? 44 : max(28, 44 - CGFloat(written.count - 8) * 1.6)
    }

    var body: some View {
        let appear = Ease.out(Ease.progress(t, from: 0, over: 0.7))
        VStack(spacing: 0) {
            art
            // Smaller steps for narrow panes, so the lines are never cut off.
            ViewThatFits(in: .horizontal) {
                lines(scale: 1)
                lines(scale: 0.86)
                lines(scale: 0.74)
                lines(scale: 0.62)
            }
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 360)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            if let action {
                WideButton(title: action.title, action: action.run)
                    .padding(.top, 26)
            }
        }
        .padding(.horizontal, 20)
        .opacity(appear)
        .offset(y: 8 * (1 - appear))
    }

    private func lines(scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text(first)
                .font(.system(size: 30 * scale, weight: .semibold))
                .foregroundStyle(Palette.textPrimary.opacity(0.62))
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if !lead.isEmpty {
                    Text(lead).font(.system(size: 30 * scale, weight: .semibold))
                }
                Handwriting(text: written, size: writtenSize * scale, progress: Ease.progress(t, from: 0.55, over: min(1.2, 0.3 + Double(written.count) * 0.09)))
                if !trail.isEmpty {
                    Text(trail).font(.system(size: 30 * scale, weight: .semibold))
                }
            }
            .padding(.top, 2 * scale)
        }
        .fixedSize()
    }
}

extension EmptyHeadline where Art == EmptyView {
    init(first: String, lead: String = "", written: String, trail: String = ".", message: String, action: (title: String, run: () -> Void)? = nil, t: Double) {
        self.init(first: first, lead: lead, written: written, trail: trail, message: message, action: action, t: t) { EmptyView() }
    }
}

/// The wide button under a headline: the screen's one gold action.
struct WideButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Palette.onAccent)
                .frame(width: 300, height: 38)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(isHovered ? Palette.accentPressed : Palette.accent))
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help("New note from a video or pictures (⌘N)")
    }
}

/// A round of visits: something (a magnifying glass, a reader) holds on
/// each card in turn, glides to the next, and after the last comes back to
/// the first, arcing away from the headline, while the round is undone.
struct Tour {
    let count: Int
    let hold: Double
    let glide: Double
    let back: Double

    var lap: Double { Double(count) * hold + Double(count - 1) * glide + back }

    /// When the visit to card `index` begins.
    func arrival(_ index: Int) -> Double { Double(index) * (hold + glide) }

    /// 1 through the round, falling to 0 on the way back to the first card.
    func kept(at local: Double) -> Double {
        1 - Ease.inOut(Ease.progress(local, from: lap - back * 0.8, over: back * 0.5))
    }

    /// How visible something shown only while holding on `index` is.
    func holding(_ index: Int, at local: Double) -> Double {
        Ease.window(local, start: arrival(index), end: arrival(index) + hold, fade: 0.25)
    }

    /// Where the visitor is at `local`, given each card's stop.
    func position(at local: Double, stops: [CGPoint], middle: CGFloat) -> CGPoint {
        for index in 0..<count {
            let start = arrival(index)
            if local < start + hold { return stops[index] }
            let duration = index == count - 1 ? back : glide
            if local < start + hold + duration {
                let from = stops[index]
                let to = stops[(index + 1) % count]
                let p = Ease.inOut(Ease.progress(local, from: start + hold, over: duration))
                // Bend away from the headline: up above the middle, down below it.
                let away: CGFloat = (from.y + to.y) / 2 < middle ? -1 : 1
                let bend = CGFloat(sin(p * .pi)) * min(44, abs(to.x - from.x) * 0.12) * away
                return CGPoint(x: from.x + (to.x - from.x) * p, y: from.y + (to.y - from.y) * p + bend)
            }
        }
        return stops[0]
    }
}
