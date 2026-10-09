import SwiftUI

/// A video with no text on screen. Around the headline, frames of the video
/// sit at their times on the grid, and a dashed blue reader visits each in
/// turn: a line scans down it, a box looks for words and closes on nothing,
/// and a handwritten remark says what was there instead.
struct FramesEmptyState: View {
    var isPictures = false

    private struct Shot {
        let scene: Int
        let remark: String
    }

    private static let shots = [
        Shot(scene: 0, remark: "just hills"),
        Shot(scene: 1, remark: "a face, no words"),
        Shot(scene: 2, remark: "two people talking"),
        Shot(scene: 3, remark: "a cup of tea"),
        Shot(scene: 1, remark: "still nothing"),
    ]

    private static let tour = Tour(count: shots.count, hold: 1.7, glide: 0.7, back: 1.9)

    var body: some View {
        EmptyCanvas(marks: .times(every: 12), still: 1.6) { grid, t, _ in
            let frames = GridLayout.ring.map { cell in
                let frame = grid.cardFrame(column: cell.0, row: cell.1)
                return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: ((frame.width - 10) * 0.46).rounded() + 10)
            }
            let local = Ease.loop(t, lap: Self.tour.lap, offset: 0.7)
            let kept = Self.tour.kept(at: local)
            let center = Self.tour.position(at: local, stops: frames.map { CGPoint(x: $0.midX, y: $0.midY) }, middle: grid.size.height / 2)
            let size = frames[0].size

            ZStack(alignment: .topLeading) {
                ForEach(Array(Self.shots.enumerated()), id: \.offset) { index, shot in
                    let frame = frames[index]
                    let checked = Ease.out(Ease.progress(local, from: Self.tour.arrival(index) + Self.tour.hold - 0.3, over: 0.4)) * kept
                    VStack(alignment: .leading, spacing: 10) {
                        Canvas { context, canvas in
                            let rect = CGRect(origin: .zero, size: canvas)
                            context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(SceneColor.inset))
                            FrameSketch.draw(shot.scene, in: rect, context: context)
                        }
                        .frame(width: frame.width - 10, height: frame.height - 10)
                        .padding(5)
                        .paperCard()
                        .opacity(1 - 0.4 * checked)
                        Remark(shot.remark, time: local, start: Self.tour.arrival(index) + Self.tour.hold - 0.4)
                            .opacity(kept)
                    }
                    .offset(x: frame.minX, y: frame.minY)
                }

                reader(local: local, size: size)
                    .position(center)
            }
            .frame(width: grid.size.width, height: grid.size.height, alignment: .topLeading)
            .opacity(Ease.out(Ease.progress(t, from: 0.2, over: 0.6)))
        } headline: { t in
            if isPictures {
                EmptyHeadline(
                    first: "No pictures in this note.",
                    lead: "Nothing could be ",
                    written: "read",
                    message: "Ovyl couldn't open the pictures for this note.",
                    t: t
                )
            } else {
                EmptyHeadline(
                    first: "No frames in this video.",
                    lead: "Nothing on screen to ",
                    written: "read",
                    message: "Ovyl keeps a frame whenever text shows up, like a slide. This video had none.",
                    t: t
                )
            }
        }
    }

    /// The reader over the frame it's on: a dashed blue window, a line that
    /// scans down while it holds, a box where words would be that closes on
    /// nothing, and the count of what it found above.
    private func reader(local: Double, size: CGSize) -> some View {
        let index = (0..<Self.shots.count).last { local >= Self.tour.arrival($0) } ?? 0
        let start = Self.tour.arrival(index)
        let holding = local < start + Self.tour.hold ? Self.tour.holding(index, at: local) : 0
        let scan = Ease.inOut(Ease.progress(local, from: start + 0.15, over: 0.7))
        let search = Ease.progress(local, from: start + 0.8, over: Self.tour.hold - 0.9)
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let box = CGSize(width: size.width + 10, height: size.height + 10)
        return ZStack(alignment: .topLeading) {
            shape.fill(SceneColor.highlightSoft)

            // The scan line and the glow it leaves behind.
            let y = 5 + (box.height - 10) * scan
            LinearGradient(colors: [SceneColor.highlight.opacity(0), SceneColor.highlight], startPoint: .top, endPoint: .bottom)
                .frame(width: box.width, height: 18)
                .offset(y: y - 18)
                .opacity(scan > 0 && scan < 1 ? holding : 0)
            Rectangle()
                .fill(SceneColor.highlightEdge)
                .frame(width: box.width, height: 1)
                .offset(y: y)
                .opacity(scan > 0 && scan < 1 ? holding : 0)

            // Where words would be: the box searches, then shrinks away empty.
            Dashed(shape: RoundedRectangle(cornerRadius: 2), fill: SceneColor.highlight.opacity(0.5))
                .frame(width: box.width * (0.6 - 0.3 * search), height: 10 * (1 - 0.6 * search))
                .position(x: box.width / 2, y: box.height * 0.32)
                .opacity(Ease.window(search, start: 0, end: 1, fade: 0.25) * holding)
        }
        .frame(width: box.width, height: box.height)
        .clipShape(shape)
        .overlay(shape.stroke(SceneColor.highlightEdge, style: StrokeStyle(lineWidth: 1, dash: [2.6, 2])))
        .overlay(alignment: .top) {
            MonoLabel(name: "text found", count: "(0)")
                .fixedSize()
                .offset(y: -16)
                .opacity(holding)
        }
    }
}

/// Simple pictures with no writing in them, as frames of a video: hills
/// under a sun, a person, two people talking, a cup on a table.
enum FrameSketch {
    static func draw(_ scene: Int, in rect: CGRect, context: GraphicsContext) {
        let ink = GraphicsContext.Shading.color(SceneColor.sketch)
        let soft = GraphicsContext.Shading.color(SceneColor.sketch.opacity(0.55))
        let w = rect.width
        let h = rect.height
        let unit = min(w, h)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * w, y: rect.minY + y * h) }
        func circle(_ center: CGPoint, _ diameter: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter))
        }
        switch scene {
        case 0:
            context.fill(circle(point(0.72, 0.3), unit * 0.16), with: soft)
            var hills = Path()
            hills.move(to: point(0, 1))
            hills.addLine(to: point(0.3, 0.46))
            hills.addLine(to: point(0.5, 0.74))
            hills.addLine(to: point(0.66, 0.58))
            hills.addLine(to: point(1, 1))
            hills.closeSubpath()
            context.fill(hills, with: ink)
        case 1:
            context.fill(circle(point(0.5, 0.36), unit * 0.22), with: ink)
            context.fill(Path(roundedRect: CGRect(x: rect.minX + w * 0.5 - unit * 0.26, y: rect.minY + h * 0.62, width: unit * 0.52, height: h * 0.45), cornerRadius: unit * 0.18), with: ink)
        case 2:
            for (x, size) in [(0.34, 0.2), (0.66, 0.18)] {
                context.fill(circle(point(x, 0.4), unit * size), with: ink)
                context.fill(Path(roundedRect: CGRect(x: rect.minX + w * x - unit * size, y: rect.minY + h * 0.64, width: unit * size * 2, height: h * 0.4), cornerRadius: unit * 0.14), with: soft)
            }
        default:
            context.fill(Path(CGRect(x: rect.minX, y: rect.minY + h * 0.72, width: w, height: 1.5)), with: soft)
            let cup = CGRect(x: rect.minX + w * 0.42, y: rect.minY + h * 0.4, width: unit * 0.26, height: h * 0.32)
            context.fill(Path(roundedRect: cup, cornerRadius: 2.5), with: ink)
            var handle = Path()
            handle.addArc(center: CGPoint(x: cup.maxX, y: cup.midY), radius: unit * 0.07, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            context.stroke(handle, with: ink, lineWidth: 1.6)
        }
    }
}
