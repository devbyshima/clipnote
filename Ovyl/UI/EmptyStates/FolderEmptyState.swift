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
            // The note and its remark beside it, where they fit whole; with no
            // room for them the folder waits on its own.
            let corner = grid.place([
                GridPiece((Self.cell.column, Self.cell.row), size: CGSize(width: 92 + 4 + Remark.size(["drag it in"]).width, height: 92 * 1.2 + 4))
            ])[0]
            let home = CGRect(origin: corner ?? .zero, size: CGSize(width: 92, height: 44))
            let page = NotePage(title: "Team Sync", text: "Budget: Priya owns it from now on.\nLaunch moves to March 14.\n\nNext sync on Friday.", day: "TODAY", width: 92)
            // Without room on the grid, the note waits small beside the folder.
            let beside = target.map { CGPoint(x: min(($0.maxX + grid.size.width) / 2, grid.size.width - 30), y: $0.midY) }
            let base: CGFloat = corner == nil ? 0.5 : 1
            let start = corner == nil ? (beside ?? .zero) : CGPoint(x: home.minX + page.width / 2, y: home.minY + page.height / 2)
            let spot = target.map { CGPoint(x: $0.midX, y: $0.minY + 26) } ?? start
            let carry = round.carry
            let arc = CGFloat(sin(carry * .pi)) * 60
            let center = CGPoint(
                x: start.x + (spot.x - start.x) * carry,
                y: start.y + (spot.y - start.y) * carry - arc + 6 * round.sink
            )
            let scale = base * (1 + 0.04 * round.grab) * (1 - 0.5 * carry) * (1 - 0.3 * round.sink)
            let grip = CGPoint(x: center.x + page.width * 0.3 * scale, y: center.y - page.height * 0.12 * scale)

            ZStack(alignment: .topLeading) {
                Remark("drag it in", time: round.local, start: 0.2)
                    .opacity(corner == nil ? 0 : round.kept)
                    .offset(x: home.minX + page.width + 4, y: home.minY + page.height - 26)

                NotePage(title: page.title, text: page.text, day: page.day, width: page.width, lift: 1 + 1.5 * round.grab * (1 - carry))
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

/// The folder in the cards' own look: a colored back with its tab, a white
/// sheet standing in it once a note is in, and the front with the name and
/// count, which tips forward to take the note. Ovyl's own folder: gold
/// deepening toward ember, a shimmer along the front's top edge, and a
/// warm glow; dashed in ember while a note is dragged over it.
struct FolderGlyph: View {
    let target: Double
    let open: Double
    let filled: Double
    let count: Int
    let tick: Double

    private static let size = CGSize(width: 170, height: 102)
    private let tint = HexColor(Palette.Hex.accent)
    private let ember = HexColor(Palette.Hex.ember)
    /// The back sits deeper than the front, so the two read apart on a
    /// light page as well as a dark one.
    private var back: HexColor { tint.blended(with: ember, 0.3) }
    private var backFoot: HexColor { tint.blended(with: ember, 0.5) }

    var body: some View {
        let w = Self.size.width
        let h = Self.size.height
        let front = (h * FolderArtwork.front).rounded()
        let radius = (h * 0.15).rounded()
        ZStack(alignment: .topLeading) {
            FolderBackShape(tabWidth: w * 0.445, tabDrop: h * 0.096, radius: radius)
                .fill(LinearGradient(colors: [back.color, backFoot.color], startPoint: .top, endPoint: .bottom))
                .overlay(FolderBackShape(tabWidth: w * 0.445, tabDrop: h * 0.096, radius: radius).stroke(Palette.ember.opacity(0.45), lineWidth: 1))
                .frame(width: w, height: front + radius)

            PaperSheets(count: 1, width: w, height: h, isRaised: filled > 0.5)
                .offset(y: h * 0.12 * (1 - filled))
                .opacity(filled)

            LinearGradient(colors: [backFoot.color.opacity(0), backFoot.color], startPoint: .top, endPoint: .bottom)
                .frame(width: w, height: h * 0.13)
                .offset(y: front - h * 0.13)

            ZStack(alignment: .topLeading) {
                UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [tint.color, tint.blended(with: ember, 0.6).color], startPoint: .top, endPoint: .bottom))
                    .overlay(
                        UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
                            .strokeBorder(Palette.ember.opacity(0.45), lineWidth: 1)
                    )
                // The shimmer along the front's top edge, as on the icons.
                LinearGradient(
                    stops: [
                        .init(color: Palette.accent.opacity(0), location: 0),
                        .init(color: Palette.shimmerLime, location: 0.3),
                        .init(color: Palette.shimmerIce, location: 0.55),
                        .init(color: Palette.shimmerMint, location: 0.75),
                        .init(color: Palette.accent.opacity(0), location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 1.5)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Notes")
                            .font(.system(size: 16, weight: .bold))
                        Text("\(count)")
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .tracking(1)
                            .opacity(0.85)
                            .scaleEffect(1 + 0.3 * tick, anchor: .leading)
                    }
                    Spacer(minLength: 4)
                    MoreDots(color: Palette.onAccent, scale: 0.6)
                        .frame(height: 16)
                }
                .foregroundStyle(Palette.onAccent)
                .padding(.horizontal, 14)
                .padding(.top, 9)
            }
            .frame(width: w, height: h - front)
            .rotation3DEffect(.degrees(-24 * open), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
            .offset(y: front)
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .overlay(
            RoundedRectangle(cornerRadius: radius + 4, style: .continuous)
                .stroke(SceneColor.highlightEdge, style: StrokeStyle(lineWidth: 1.2, dash: [2.6, 2]))
                .padding(-6)
                .opacity(target)
        )
        .shadow(color: Palette.ember.opacity(0.35), radius: 14, y: 8)
        .scaleEffect(1 + 0.03 * target)
    }
}
