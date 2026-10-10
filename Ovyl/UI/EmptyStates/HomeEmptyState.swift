import AppKit
import SwiftUI

/// Home before the first note. Behind the headline, a faint timeline of a
/// video, 30 seconds a cell, where small cards tell what Ovyl does with one:
/// a video drops in, speech becomes timed lines, a slide's title is read off
/// the screen, a song is struck out, and the note is done. Each card gets a
/// handwritten remark that writes itself and is underlined.
struct HomeEmptyState: View {
    var onNew: () -> Void

    var body: some View {
        EmptyCanvas(marks: .times(every: 30), still: 6.2) { grid, t, _ in
            ZStack(alignment: .topLeading) {
                ForEach(Array(Self.moments.enumerated()), id: \.offset) { index, moment in
                    StoryMoment(moment: moment, frame: grid.cardFrame(column: moment.column, row: moment.row), time: Self.local(t, index: index))
                }
            }
        } headline: { t in
            EmptyHeadline(
                first: "Drop in a video.",
                lead: "Keep what was ",
                written: "said",
                message: "Ovyl writes down what's said and shown.\nEverything stays on this Mac.",
                action: ("New note", onNew),
                t: t
            )
        }
    }

    // MARK: Moments

    enum Kind {
        case drop, listen, read, skip, note
    }

    struct Moment {
        let kind: Kind
        let column: Int
        let row: Int
        let remark: [String]
    }

    /// The story, in order, placed around the headline on the 7 × 5 timeline.
    /// The bottom row's remark is one line so it fits short windows.
    static let moments = [
        Moment(kind: .drop, column: 3, row: 0, remark: ["just drop it in"]),
        Moment(kind: .listen, column: 1, row: 1, remark: ["every word,", "with its time"]),
        Moment(kind: .read, column: 5, row: 2, remark: ["and the words", "on screen"]),
        Moment(kind: .skip, column: 4, row: 4, remark: ["songs left out ♪"]),
        Moment(kind: .note, column: 1, row: 3, remark: ["your note, ready"]),
    ]

    /// Seconds between one moment and the next, and for the whole story.
    static let spacing = 3.4
    static var lap: Double { spacing * Double(moments.count) }

    /// Moment `index`'s own clock: 0 when it starts to appear.
    static func local(_ t: Double, index: Int) -> Double {
        let time = (t - 0.9 - Double(index) * spacing).truncatingRemainder(dividingBy: lap)
        return time < 0 ? time + lap : time
    }
}

/// One moment of the story: its card fades in (the video drops in), plays
/// out, the remark writes itself line by line and is underlined, and
/// everything fades away.
struct StoryMoment: View {
    let moment: HomeEmptyState.Moment
    let frame: CGRect
    let time: Double

    private static let fadeIn = 0.7
    private static let leave = 7.2
    private static let fadeOut = 0.8

    var body: some View {
        let arrive = Ease.out(Ease.progress(time, from: 0, over: Self.fadeIn))
        let leaving = Ease.progress(time, from: Self.leave, over: Self.fadeOut)
        let dropping = moment.kind == .drop
        VStack(alignment: .leading, spacing: 10) {
            if moment.kind == .note {
                // The note itself: a page, like the notes on Home.
                FinishedNotePage(time: time)
            } else {
                card
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .frame(width: frame.width, alignment: .leading)
                    .paperCard()
                    .offset(y: dropping ? -30 * (1 - Ease.spring(Ease.progress(time, from: 0, over: 0.9))) : 0)
            }

            Remark(moment.remark, time: time, start: writeStart)
        }
        .opacity(arrive * (1 - Ease.inOut(leaving)))
        .blur(radius: 4 * (1 - arrive) + 3 * leaving)
        .offset(x: frame.minX, y: frame.minY + (dropping ? 0 : 6 * (1 - arrive)))
    }

    @ViewBuilder private var card: some View {
        switch moment.kind {
        case .drop: VideoCard(time: time)
        case .listen: TranscriptCard(time: time)
        case .read: SlideCard(time: time)
        case .skip: SongCard(time: time)
        case .note: EmptyView()
        }
    }

    /// When the remark starts: once the card has shown what it's about.
    private var writeStart: Double {
        switch moment.kind {
        case .drop: 1.2
        case .listen: 2.3
        case .read: 2.3
        case .skip: 1.8
        case .note: 2.3
        }
    }
}

// MARK: - Cards

/// A video that has just been dropped in, with its progress filling as
/// Ovyl works through it.
struct VideoCard: View {
    let time: Double

    var body: some View {
        let progress = Ease.inOut(Ease.progress(time, from: 0.9, over: 5.6))
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                ZStack {
                    StockPhoto.lecture
                        .resizable()
                        .scaledToFill()
                        .frame(width: 46, height: 30)
                        .overlay(Color.black.opacity(0.22))
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.95))
                        .shadow(color: .black.opacity(0.35), radius: 2)
                }
                .frame(width: 46, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("lecture.mov")
                        .font(.system(size: 12.5, weight: .medium))
                    Text("17:30")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ovylSecondary)
                        .monospacedDigit()
                }
                .lineLimit(1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(Color.ovylAccent)
                        .frame(width: max(3, geo.size.width * progress))
                        .opacity(progress > 0 ? 1 : 0)
                }
            }
            .frame(height: 3)
        }
    }
}

/// Speech becoming text: a waveform that a sweep turns into two lines,
/// each with the time it was said.
struct TranscriptCard: View {
    let time: Double

    private static let lines = [("4:02", "On to the budget"), ("4:06", "Priya owns it now")]

    var body: some View {
        let sweep = Ease.inOut(Ease.progress(time, from: 0.9, over: 1.3))
        ZStack(alignment: .leading) {
            Waveform(time: time)
                .frame(height: 26)
                .mask(Sweep(progress: sweep, reversed: true))
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Self.lines, id: \.0) { stamp, text in
                    HStack(spacing: 7) {
                        Text(stamp)
                            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(Color.ovylSecondary)
                        Text(text)
                            .font(.system(size: 11.5))
                    }
                    .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .mask(Sweep(progress: sweep))
        }
        .frame(height: 34)
    }
}

/// Text read off the screen: a slide whose title gets a dashed box, and
/// the title, now text, sliding out beside it.
struct SlideCard: View {
    let time: Double

    var body: some View {
        let box = Ease.inOut(Ease.progress(time, from: 0.8, over: 0.6))
        let read = Ease.out(Ease.progress(time, from: 1.45, over: 0.7))
        HStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5))
                VStack(alignment: .leading, spacing: 4) {
                    Capsule()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 28, height: 4.5)
                        .padding(3)
                        .background(RoundedRectangle(cornerRadius: 2.5).fill(SceneColor.highlight.opacity(box)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2.5)
                                .trim(from: 0, to: box)
                                .stroke(SceneColor.highlightEdge, style: StrokeStyle(lineWidth: 1, dash: [2.4, 1.8]))
                        )
                    ForEach([30.0, 38, 24], id: \.self) { width in
                        Capsule()
                            .fill(Color.primary.opacity(0.2))
                            .frame(width: width, height: 2.5)
                            .padding(.leading, 3)
                    }
                }
                .padding(4)
            }
            .frame(width: 58, height: 40)

            VStack(alignment: .leading, spacing: 1) {
                Text("Q3 goals")
                    .font(.system(size: 12.5, weight: .medium))
                    .mask(Sweep(progress: read))
                    .offset(x: -8 * (1 - read))
                Text("slide · 9:34")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ovylSecondary)
                    .opacity(read)
            }
            .lineLimit(1)
        }
    }
}

/// Music in the video: a song that's struck through in marker and dims,
/// its waveform falling quiet.
struct SongCard: View {
    let time: Double

    var body: some View {
        let strike = Ease.inOut(Ease.progress(time, from: 1.0, over: 0.5))
        let dim = Ease.out(Ease.progress(time, from: 1.35, over: 0.5))
        HStack(spacing: 9) {
            ZStack {
                Circle().fill(Color.pink.gradient)
                Image(systemName: "music.note")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 15, height: 15)
            VStack(alignment: .leading, spacing: 1) {
                Text("Song")
                    .font(.system(size: 12.5, weight: .medium))
                Text("at 16:02")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ovylSecondary)
                    .monospacedDigit()
            }
            .lineLimit(1)
            Spacer(minLength: 6)
            Waveform(time: time, level: 1 - dim)
                .frame(width: 34, height: 18)
        }
        .opacity(1 - 0.5 * dim)
        .overlay {
            GeometryReader { geo in
                let y = geo.size.height / 2
                Path { path in
                    path.move(to: CGPoint(x: -3, y: y + 1))
                    path.addCurve(
                        to: CGPoint(x: geo.size.width + 3, y: y - 1),
                        control1: CGPoint(x: geo.size.width * 0.35, y: y - 2),
                        control2: CGPoint(x: geo.size.width * 0.65, y: y + 2.5)
                    )
                }
                .trim(from: 0, to: strike)
                .stroke(SceneColor.ink, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
        }
    }
}

/// The finished note: a page whose points write themselves in, with a
/// check once it's done.
struct FinishedNotePage: View {
    let time: Double

    var body: some View {
        let done = Ease.spring(Ease.progress(time, from: 1.9, over: 0.6))
        NotePage(
            title: "Lecture 4",
            text: "Exam: chapters 3 to 5\n- Office hours on Friday\n- Redo the second chart\n\nThe first chart is fine as it is.",
            day: "TODAY",
            width: 96,
            written: Ease.inOut(Ease.progress(time, from: 0.4, over: 1.4))
        )
        .overlay(alignment: .topTrailing) {
            ZStack {
                Circle().fill(Color.green.gradient)
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 15, height: 15)
            .scaleEffect(max(0, done))
            .opacity(min(1, done * 2))
            .offset(x: 5, y: -5)
        }
    }
}

/// Bars of sound that move with time; `level` quiets them to dots.
struct Waveform: View {
    let time: Double
    var level: Double = 1

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 5
            let count = Int(size.width / step)
            for index in 0..<count {
                let i = Double(index)
                let envelope = 0.35 + 0.65 * abs(sin(i * 0.37 + 0.6))
                let wobble = 0.5 + 0.5 * sin(time * 7 + i * 0.9)
                let height = max(2.4, size.height * envelope * (0.35 + 0.65 * wobble) * level)
                let rect = CGRect(x: CGFloat(index) * step, y: (size.height - height) / 2, width: 2.2, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1.1), with: .color(Color.ovylSecondary))
            }
        }
    }
}

/// Stock photos shipped with the app, for the video thumbnails in the empty
/// states. The lecture is by Vitaly Gariev on Unsplash (Unsplash License).
enum StockPhoto {
    @MainActor static let lecture: Image = {
        guard let url = Bundle.main.url(forResource: "lecture", withExtension: "jpg"), let image = NSImage(contentsOf: url) else {
            return Image(systemName: "play.rectangle")
        }
        return Image(nsImage: image)
    }()
}
