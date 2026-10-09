import SwiftUI

/// An empty folder. The folder sits over the headline, labeled "notes (0)".
/// A note in one of the days around it gets a handwritten "drag it in"; a
/// pointer picks it up and carries it over, the folder lights up as a drop
/// target, tips open, takes the note and counts it. Then the round starts over.
struct FolderEmptyState: View {
    var onNew: () -> Void

    nonisolated private static let lap = 5.8
    private static let cell = (column: 5, row: 1)

    /// Where the round is, shared by the note in the grid and the folder in the headline.
    private struct Round {
        let local: Double

        var kept: Double { 1 - Ease.inOut(Ease.progress(local, from: FolderEmptyState.lap - 0.75, over: 0.5)) }
        var grab: Double { Ease.out(Ease.progress(local, from: 1.45, over: 0.25)) }
        var carry: Double { Ease.inOut(Ease.progress(local, from: 1.7, over: 1.05)) }
        var sink: Double { Ease.in(Ease.progress(local, from: 2.6, over: 0.3)) }
        var target: Double { Ease.window(local, start: 2.1, end: 3.2, fade: 0.3) }
        var open: Double { Ease.out(Ease.progress(local, from: 2.3, over: 0.35)) * (1 - Ease.spring(Ease.progress(local, from: 2.9, over: 0.8))) }
        var filled: Double { Ease.out(Ease.progress(local, from: 2.75, over: 0.3)) * kept }
        var count: Int { local >= 2.85 && local < FolderEmptyState.lap - 0.5 ? 1 : 0 }
        var tick: Double { sin(Ease.progress(local, from: 2.85, over: 0.35) * .pi) }
        var pointerIn: Double { Ease.out(Ease.progress(local, from: 1.0, over: 0.45)) }
        var pointerAway: Double { Ease.inOut(Ease.progress(local, from: 2.95, over: 0.7)) }
    }

    var body: some View {
        EmptyCanvas(marks: .days, still: 2.2) { grid, t, target in
            let round = Round(local: Ease.loop(t, lap: Self.lap, offset: 0.3))
            let home = grid.cardFrame(column: Self.cell.column, row: Self.cell.row)
            let start = CGPoint(x: home.midX, y: home.midY)
            let spot = target.map { CGPoint(x: $0.midX, y: $0.minY + 34) } ?? start
            let carry = round.carry
            let arc = CGFloat(sin(carry * .pi)) * 60
            let center = CGPoint(
                x: start.x + (spot.x - start.x) * carry,
                y: start.y + (spot.y - start.y) * carry - arc + 6 * round.sink
            )
            let scale = (1 + 0.04 * round.grab) * (1 - 0.58 * carry) * (1 - 0.3 * round.sink)
            let grip = CGPoint(x: center.x + home.width * 0.32 * scale, y: center.y + 4)

            ZStack(alignment: .topLeading) {
                Remark("drag it in", time: round.local, start: 0.2)
                    .opacity(round.kept)
                    .offset(x: home.minX, y: home.maxY + 10)

                NoteChip(symbol: "waveform", tint: .purple, title: "Team sync", detail: "18:42 · 4 slides")
                    .frame(width: home.width)
                    .paperCard(lift: 1 + 1.5 * round.grab * (1 - carry))
                    .scaleEffect(scale)
                    .rotationEffect(.degrees(4 * round.grab * sin(carry * .pi)))
                    .position(center)
                    .opacity((1 - round.sink) * Ease.out(Ease.progress(round.local, from: 0, over: 0.4)))

                Pointer()
                    .position(
                        x: grip.x + 70 * (1 - round.pointerIn) + 60 * round.pointerAway,
                        y: grip.y + 40 * (1 - round.pointerIn) + 30 * round.pointerAway
                    )
                    .opacity(round.pointerIn * (1 - round.pointerAway))
            }
            .frame(width: grid.size.width, height: grid.size.height, alignment: .topLeading)
            .opacity(Ease.out(Ease.progress(t, from: 0.2, over: 0.6)))
        } headline: { t in
            let round = Round(local: Ease.loop(t, lap: Self.lap, offset: 0.3))
            EmptyHeadline(
                first: "Nothing in this folder yet.",
                lead: "Drag notes ",
                written: "in",
                message: "Drop notes on the folder in the sidebar, or make a new one here.",
                action: ("New note", onNew),
                t: t
            ) {
                FolderGlyph(target: round.target, open: round.open, filled: round.filled, count: round.count, tick: round.tick)
                    .sceneTarget()
                    .padding(.bottom, 26)
            }
        }
    }
}

/// A paper folder: a back with a tab, a note peeking out when it holds one,
/// and a front that tips open and carries the count. Blue while something
/// is dragged over it.
struct FolderGlyph: View {
    let target: Double
    let open: Double
    let filled: Double
    let count: Int
    let tick: Double

    var body: some View {
        ZStack(alignment: .top) {
            FolderBack()
                .fill(SceneColor.cardBack)
                .overlay(FolderBack().stroke(SceneColor.cardEdge, lineWidth: 0.5))
                .overlay(Dashed(shape: FolderBack()).opacity(target))
                .shadow(color: SceneColor.cardShadow, radius: 8, y: 3)
                .frame(width: 150, height: 104)

            // The note inside, its top showing above the front.
            VStack(alignment: .leading, spacing: 5) {
                ForEach([0.6, 0.9, 0.75], id: \.self) { width in
                    Capsule()
                        .fill(SceneColor.sketch)
                        .frame(width: 44 * width, height: 3)
                }
            }
            .padding(9)
            .frame(width: 62, height: 60, alignment: .topLeading)
            .paperCard(cornerRadius: 6, lift: 0.5)
            .offset(y: 20 + 12 * (1 - filled))
            .opacity(filled)

            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(SceneColor.card)
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(SceneColor.cardEdge, lineWidth: 0.5))
                MonoLabel(name: "notes", count: "(\(count))", active: target > 0.5 || count > 0)
                    .scaleEffect(1 + 0.1 * tick)
            }
            .frame(width: 158, height: 70)
            .shadow(color: SceneColor.cardShadow, radius: 6, y: 2)
            .rotation3DEffect(.degrees(-28 * open), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
            .offset(y: 38)
        }
        .frame(width: 158, height: 110, alignment: .top)
    }
}

/// The back of a folder: a panel with a tab on its top left.
struct FolderBack: InsettableShape {
    static let tab = CGSize(width: 54, height: 12)
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let radius: CGFloat = 9
        let tabWidth = Self.tab.width
        let top = r.minY + Self.tab.height
        var path = Path()
        path.move(to: CGPoint(x: r.minX, y: r.maxY - radius))
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + 6))
        path.addQuadCurve(to: CGPoint(x: r.minX + 6, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        path.addLine(to: CGPoint(x: r.minX + tabWidth - 10, y: r.minY))
        path.addCurve(to: CGPoint(x: r.minX + tabWidth + 6, y: top), control1: CGPoint(x: r.minX + tabWidth - 2, y: r.minY), control2: CGPoint(x: r.minX + tabWidth - 2, y: top))
        path.addLine(to: CGPoint(x: r.maxX - radius, y: top))
        path.addQuadCurve(to: CGPoint(x: r.maxX, y: top + radius), control: CGPoint(x: r.maxX, y: top))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        path.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - radius), control: CGPoint(x: r.minX, y: r.maxY))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> FolderBack {
        FolderBack(inset: inset + amount)
    }
}
