import SwiftUI

/// Search found nothing. The headline writes the search out by hand; around
/// it, notes sit in the days they were made, and a magnifying glass stops
/// on each in turn, enlarging it. Each comes up empty, gets a handwritten
/// remark and fades back.
struct SearchEmptyState: View {
    let query: String

    private struct Entry {
        let symbol: String
        let tint: Color
        let title: String
        let detail: String
        let remark: String
    }

    private static let entries = [
        Entry(symbol: "waveform", tint: .purple, title: "Team sync", detail: "18:42 · 4 slides", remark: "not here"),
        Entry(symbol: "checkmark", tint: .green, title: "Lecture 4", detail: "52:10 · 12 slides", remark: "nope"),
        Entry(symbol: "play.fill", tint: .orange, title: "Pasta, three ways", detail: "8:05", remark: "no match"),
        Entry(symbol: "sparkles", tint: .pink, title: "Product demo", detail: "31:27 · 6 slides", remark: "not this one"),
        Entry(symbol: "photo", tint: .teal, title: "Whiteboard", detail: "3 pictures", remark: "nothing"),
    ]

    private static let tour = Tour(count: entries.count, hold: 1.5, glide: 0.75, back: 1.9)
    private static let lens: CGFloat = 70
    private static let zoom: CGFloat = 1.45

    /// The search as the headline writes it: quoted and kept short.
    private var written: String {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let short = trimmed.count > 16 ? String(trimmed.prefix(15)) + "…" : trimmed
        return "“\(short)”"
    }

    var body: some View {
        EmptyCanvas(marks: .days, still: 1.4) { grid, t, _ in
            let frames = GridLayout.ring.map { grid.cardFrame(column: $0.0, row: $0.1) }
            let local = Ease.loop(t, lap: Self.tour.lap, offset: 0.7)
            let stops = frames.map { CGPoint(x: $0.minX + 42, y: $0.minY + 22) }
            let glass = Self.tour.position(at: local, stops: stops, middle: grid.size.height / 2)
            let kept = Self.tour.kept(at: local)

            ZStack(alignment: .topLeading) {
                notes(frames, size: grid.size, local: local, kept: kept, remarks: true)

                // What the glass shows: the same notes, larger, tinted blue.
                ZStack(alignment: .topLeading) {
                    notes(frames, size: grid.size, local: local, kept: 0, remarks: false)
                        .scaleEffect(Self.zoom, anchor: grid.unit(glass))
                    Circle()
                        .fill(SceneColor.highlightSoft)
                        .frame(width: Self.lens, height: Self.lens)
                        .position(glass)
                }
                .frame(width: grid.size.width, height: grid.size.height, alignment: .topLeading)
                .mask {
                    Circle()
                        .frame(width: Self.lens, height: Self.lens)
                        .position(glass)
                }

                Magnifier(diameter: Self.lens)
                    .position(glass)
            }
            .frame(width: grid.size.width, height: grid.size.height, alignment: .topLeading)
            .opacity(Ease.out(Ease.progress(t, from: 0.2, over: 0.6)))
        } headline: { t in
            EmptyHeadline(
                first: "No notes match",
                written: written,
                trail: "",
                message: "Try fewer or different words.",
                t: t
            )
        }
    }

    /// The notes in their cells. Each dims once the glass has checked it and
    /// gets its remark, until the round starts over.
    private func notes(_ frames: [CGRect], size: CGSize, local: Double, kept: Double, remarks: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(Self.entries.enumerated()), id: \.offset) { index, entry in
                let frame = frames[index]
                let checked = Ease.out(Ease.progress(local, from: Self.tour.arrival(index) + Self.tour.hold - 0.3, over: 0.4)) * kept
                VStack(alignment: .leading, spacing: 10) {
                    NoteChip(symbol: entry.symbol, tint: entry.tint, title: entry.title, detail: entry.detail)
                        .frame(width: frame.width)
                        .paperCard()
                        .opacity(1 - 0.45 * checked)
                    if remarks {
                        Remark(entry.remark, time: local, start: Self.tour.arrival(index) + Self.tour.hold - 0.45)
                            .opacity(kept)
                    }
                }
                .offset(x: frame.minX, y: frame.minY)
            }
        }
        // The whole pane, so the glass's zoom is anchored where it is.
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// A magnifying glass: a paper rim around a fine dashed blue ring, with a
/// paper handle.
struct Magnifier: View {
    let diameter: CGFloat

    var body: some View {
        let radius = diameter / 2
        let handle = CGSize(width: 30, height: 10)
        let reach = radius + handle.width / 2 + 2
        ZStack {
            Capsule()
                .fill(SceneColor.card)
                .overlay(Capsule().strokeBorder(SceneColor.cardEdge, lineWidth: 0.5))
                .shadow(color: SceneColor.cardShadow, radius: 6, y: 3)
                .frame(width: handle.width, height: handle.height)
                .rotationEffect(.degrees(45))
                .offset(x: reach * 0.7071, y: reach * 0.7071)
            Circle()
                .strokeBorder(SceneColor.card, lineWidth: 5)
                .overlay(Circle().strokeBorder(SceneColor.cardEdge, lineWidth: 0.5))
                .shadow(color: SceneColor.cardShadow, radius: 8, y: 3)
                .frame(width: diameter + 10, height: diameter + 10)
            Circle()
                .stroke(SceneColor.highlightEdge, style: StrokeStyle(lineWidth: 1, dash: [2.6, 2.2]))
                .frame(width: diameter, height: diameter)
        }
        .frame(width: diameter + 10, height: diameter + 10)
    }
}
