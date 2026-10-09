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

    init(size: CGSize) {
        self.size = size
        // All five rows fit the height, so cards in the top and bottom rows show whole.
        cell = CGSize(width: min(max(size.width / 5.4, 112), 180), height: min(max(size.height / 5, 104), 150))
        origin = CGPoint(
            x: (size.width - cell.width * CGFloat(Self.columns)) / 2,
            y: (size.height - cell.height * CGFloat(Self.rows)) / 2
        )
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
}

/// The faint grid: hairlines and a mark in each cell's corner, fading out
/// toward the edges and around the headline.
struct GridBackdrop: View {
    let layout: GridLayout
    let marks: GridMarks
    let hole: CGRect

    var body: some View {
        Canvas { context, _ in
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
                        .font(.system(size: 10.5, weight: mark.isBold ? .bold : .medium, design: .monospaced))
                        .foregroundStyle(mark.isBold ? Color.primary.opacity(0.75) : SceneColor.number)
                    let point = CGPoint(x: layout.origin.x + CGFloat(column) * layout.cell.width + 9, y: layout.origin.y + CGFloat(row) * layout.cell.height + 8)
                    context.draw(label, at: point, anchor: .topLeading)
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

    var body: some View {
        GeometryReader { geo in
            let layout = GridLayout(size: geo.size)
            MotionClock(still: still) { t in
                headline(t)
                    .anchorPreference(key: HeadlineBounds.self, value: .bounds) { $0 }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .overlayPreferenceValue(SceneTarget.self) { target in
                        GeometryReader { proxy in
                            pieces(layout, t, target.map { proxy[$0] })
                        }
                    }
            }
            .backgroundPreferenceValue(HeadlineBounds.self) { anchor in
                GeometryReader { proxy in
                    GridBackdrop(layout: layout, marks: marks, hole: anchor.map { proxy[$0] } ?? .zero)
                }
            }
        }
    }
}

private struct HeadlineBounds: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// A spot in the headline that the pieces move toward, such as a folder.
struct SceneTarget: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

extension View {
    /// Marks this view as where an empty state's pieces head for.
    func sceneTarget() -> some View {
        anchorPreference(key: SceneTarget.self, value: .bounds) { $0 }
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
            Text(first)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.62))
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if !lead.isEmpty {
                    Text(lead).font(.system(size: 30, weight: .semibold))
                }
                Handwriting(text: written, size: writtenSize, progress: Ease.progress(t, from: 0.55, over: min(1.2, 0.3 + Double(written.count) * 0.09)))
                if !trail.isEmpty {
                    Text(trail).font(.system(size: 30, weight: .semibold))
                }
            }
            .padding(.top, 2)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Color.ovylSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 360)
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
}

extension EmptyHeadline where Art == EmptyView {
    init(first: String, lead: String = "", written: String, trail: String = ".", message: String, action: (title: String, run: () -> Void)? = nil, t: Double) {
        self.init(first: first, lead: lead, written: written, trail: trail, message: message, action: action, t: t) { EmptyView() }
    }
}

/// The wide button under a headline: white on dark, black on light.
struct WideButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Color.ovylBG)
                .frame(width: 300, height: 38)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(isHovered ? 0.82 : 0.92)))
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
