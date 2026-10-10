import SwiftUI

/// Search found nothing. The headline writes the search out by hand; around
/// it, notes sit in the days they were made, and a magnifying glass stops
/// on each in turn, enlarging it. Each comes up empty, gets a handwritten
/// remark and fades back.
struct SearchEmptyState: View {
    let query: String

    private struct Entry {
        let title: String
        let text: String
        let day: String
        let remark: String
    }

    private static let entries = [
        Entry(title: "Team Sync", text: "Budget: Priya owns it from now on.\nLaunch moves to March 14.\n\nNext sync on Friday.", day: "TODAY", remark: "not here"),
        Entry(title: "Lecture 4", text: "Chapters 3 to 5 are on the exam.\nOffice hours move to Friday.\n\nRedo the second chart.", day: "YESTERDAY", remark: "nope"),
        Entry(title: "Pasta, Three Ways", text: "Garlic, chili and olive oil.\nSave a cup of the pasta water.\n\nMore garlic next time.", day: "MON, 6 OCT", remark: "no match"),
        Entry(title: "Product Demo", text: "The best part is at 12:40.\nShip the mobile beta first.\n\nQuestions about pricing.", day: "FRI, 3 OCT", remark: "not this one"),
        Entry(title: "Whiteboard", text: "Sprint goals\nFix the login timeout.\nDark mode to beta testers.\n\nDemo on Thursday at 3.", day: "WED, 1 OCT", remark: "nothing"),
    ]

    private static let page: CGFloat = 92

    /// The glass's round over however many notes fit the pane.
    private static func tour(_ count: Int) -> Tour {
        Tour(count: max(count, 1), hold: 1.5, glide: 0.75, back: 1.9)
    }
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
            // Each note with its remark beside it, where they fit whole.
            let placed = grid.place(Self.entries.enumerated().map { index, entry in
                // The glass reaches a little above the page, and past its side.
                GridPiece(
                    GridLayout.ring[index],
                    size: CGSize(width: Self.page + 4 + Remark.size([entry.remark]).width, height: Self.page * 1.2 + 4),
                    outset: EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0)
                )
            })
            let shown = placed.enumerated().compactMap { index, corner in corner.map { (entry: Self.entries[index], corner: $0) } }
            let tour = Self.tour(shown.count)
            let local = Ease.loop(t, lap: tour.lap, offset: 0.7)
            let stops = shown.map { CGPoint(x: $0.corner.x + Self.page / 2, y: $0.corner.y + 30) }
            let glass = stops.isEmpty ? .zero : tour.position(at: local, stops: stops, middle: grid.size.height / 2)
            let kept = tour.kept(at: local)

            ZStack(alignment: .topLeading) {
                notes(shown, tour: tour, size: grid.size, local: local, kept: kept, remarks: true)

                // What the glass shows: the same notes, larger, in gold.
                ZStack(alignment: .topLeading) {
                    notes(shown, tour: tour, size: grid.size, local: local, kept: 0, remarks: false)
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
            .opacity(shown.isEmpty ? 0 : 1)
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
    private func notes(_ shown: [(entry: Entry, corner: CGPoint)], tour: Tour, size: CGSize, local: Double, kept: Double, remarks: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, item in
                let entry = item.entry
                let checked = Ease.out(Ease.progress(local, from: tour.arrival(index) + tour.hold - 0.3, over: 0.4)) * kept
                // The remark beside the page, at its foot, so it stays in the cell.
                HStack(alignment: .bottom, spacing: 4) {
                    NotePage(title: entry.title, text: entry.text, day: entry.day, width: Self.page)
                        .opacity(1 - 0.45 * checked)
                    if remarks {
                        Remark(entry.remark, time: local, start: tour.arrival(index) + tour.hold - 0.45)
                            .opacity(kept)
                            .padding(.bottom, 2)
                    }
                }
                .offset(x: item.corner.x, y: item.corner.y)
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
