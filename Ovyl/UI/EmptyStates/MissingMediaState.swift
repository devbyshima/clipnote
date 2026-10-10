import SwiftUI

/// A note's video or recording that was moved or deleted. On its
/// timeline's grid, the gap where the file was is a dashed outline with
/// "it was here" in hand, a ghost of the file inside: a frame for a video,
/// a silent waveform for a recording. A magnifier looks in a few folders
/// around it, and each gets a "not here". The headline asks to be shown
/// where it went, with the one gold action to find it.
struct MissingMediaState: View {
    let isAudio: Bool
    let fileName: String
    var locate: () -> Void

    private var places: [String] {
        isAudio ? ["Voice Memos", "Downloads", "Desktop"] : ["Movies", "Downloads", "Desktop"]
    }

    private static func tour(_ count: Int) -> Tour {
        Tour(count: max(count, 1), hold: 1.6, glide: 0.8, back: 2.0)
    }

    private static let lens: CGFloat = 54
    private static let gap = CGSize(width: 156, height: 56)
    private static let chip = CGSize(width: 132, height: 36)

    var body: some View {
        EmptyCanvas(marks: .times(every: 30), still: 2.4) { grid, t, _ in
            let wasHere = Remark.size(["it was here"])
            let notHere = Remark.size(["not here"])
            // The gap and its remark, then the folders the glass checks,
            // each where they fit whole.
            let placed = grid.place(
                [GridPiece((1, 1), size: CGSize(width: max(Self.gap.width, wasHere.width), height: Self.gap.height + 10 + wasHere.height))]
                    + [(3, 0), (5, 1), (5, 3)].map {
                        GridPiece($0, size: CGSize(width: max(Self.chip.width, notHere.width), height: Self.chip.height + 8 + notHere.height), outset: EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 10))
                    }
            )
            let folders = placed.dropFirst().enumerated().compactMap { index, corner in
                corner.map { (name: places[index], corner: $0) }
            }
            let tour = Self.tour(folders.count)
            let local = Ease.loop(t, lap: tour.lap, offset: 1.4)
            let kept = tour.kept(at: local)
            let stops = folders.map { CGPoint(x: $0.corner.x + 26, y: $0.corner.y + Self.chip.height / 2) }
            let glass = stops.isEmpty ? .zero : tour.position(at: local, stops: stops, middle: grid.size.height / 2)

            ZStack(alignment: .topLeading) {
                if let corner = placed[0] {
                    VStack(alignment: .leading, spacing: 10) {
                        gap(t: t)
                        Remark("it was here", time: t, start: 0.9)
                    }
                    .offset(x: corner.x, y: corner.y)
                }

                ForEach(Array(folders.enumerated()), id: \.offset) { index, folder in
                    let checked = Ease.out(Ease.progress(local, from: tour.arrival(index) + tour.hold - 0.3, over: 0.4)) * kept
                    VStack(alignment: .leading, spacing: 8) {
                        FolderChip(name: folder.name)
                            .opacity(1 - 0.45 * checked)
                        Remark("not here", time: local, start: tour.arrival(index) + tour.hold - 0.45)
                            .opacity(kept)
                    }
                    .offset(x: folder.corner.x, y: folder.corner.y)
                }

                Magnifier(diameter: Self.lens)
                    .position(glass)
                    .opacity(folders.isEmpty ? 0 : Ease.out(Ease.progress(t, from: 1.2, over: 0.5)))
            }
            .frame(width: grid.size.width, height: grid.size.height, alignment: .topLeading)
            .opacity(Ease.out(Ease.progress(t, from: 0.2, over: 0.6)))
        } headline: { t in
            EmptyHeadline(
                first: isAudio ? "This recording moved." : "This video moved.",
                lead: "Show Ovyl where it ",
                written: "went",
                message: "\(fileName) was moved or deleted. The note is safe; find the file and it plays again.",
                action: ("Locate…", locate),
                actionHelp: isAudio ? "Find the recording" : "Find the video",
                t: t
            )
        }
    }

    /// Where the file was: a dashed outline that breathes, around a ghost
    /// of it.
    private func gap(t: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return HStack(spacing: 10) {
            if isAudio {
                Waveform(time: 0, level: 0)
                    .frame(width: 70, height: 22)
            } else {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(SceneColor.inset)
                    .frame(width: 46, height: 30)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(SceneColor.label)
                    }
            }
            Text(fileName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(SceneColor.label)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .frame(width: Self.gap.width, height: Self.gap.height, alignment: .leading)
        .opacity(0.55)
        .background(Dashed(shape: shape, fill: SceneColor.highlightSoft))
        .opacity(0.75 + 0.25 * (0.5 + 0.5 * cos(t * 2.2)))
    }
}

/// A folder on the Mac, as a small paper card.
private struct FolderChip: View {
    let name: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 13))
                .foregroundStyle(SceneColor.ink)
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CardColor.title)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(width: 132, height: 36, alignment: .leading)
        .paperCard(cornerRadius: 10)
    }
}
