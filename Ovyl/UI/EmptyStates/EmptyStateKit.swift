import AppKit
import SwiftUI

// The pieces every empty state is made from: a clock that drives the motion,
// easing curves, the colors, paper cards, yellow handwriting, the dashed
// blue of something Ovyl is reading, small counts, and a pointer.

// MARK: - Clock

extension EnvironmentValues {
    /// A fixed time for the empty states' motion, for rendering frames in
    /// tests. Nil lets the clock run.
    @Entry var motionTime: Double? = nil
}

/// Gives `content` the seconds since it appeared, every frame. A fixed time
/// from the environment stops the clock; with Reduce Motion, `still` is used.
struct MotionClock<Content: View>: View {
    var still: Double
    let content: (Double) -> Content
    @Environment(\.motionTime) private var fixed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now

    init(still: Double, @ViewBuilder content: @escaping (Double) -> Content) {
        self.still = still
        self.content = content
    }

    var body: some View {
        if let fixed {
            content(fixed)
        } else if reduceMotion {
            content(still)
        } else {
            TimelineView(.animation) { context in
                content(context.date.timeIntervalSince(start))
            }
        }
    }
}

/// Curves for time-driven motion, each taking and giving 0...1.
enum Ease {
    static func clamp(_ t: Double) -> Double { min(max(t, 0), 1) }

    /// How far `t` is through the span that starts at `start`.
    static func progress(_ t: Double, from start: Double, over duration: Double) -> Double {
        clamp((t - start) / duration)
    }

    static func inOut(_ t: Double) -> Double {
        let t = clamp(t)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    static func out(_ t: Double) -> Double { 1 - pow(1 - clamp(t), 3) }

    static func `in`(_ t: Double) -> Double { pow(clamp(t), 3) }

    /// Settles past 1 and back, like a soft spring.
    static func spring(_ t: Double) -> Double {
        let t = clamp(t)
        return 1 - exp(-6.5 * t) * cos(9 * t)
    }

    /// Fades in over `fade` from `start`, holds, and fades out by `end`.
    static func window(_ t: Double, start: Double, end: Double, fade: Double) -> Double {
        min(out(progress(t, from: start, over: fade)), 1 - inOut(progress(t, from: end - fade, over: fade)))
    }

    /// `t` wrapped into a loop of `lap` seconds that starts at `offset`.
    static func loop(_ t: Double, lap: Double, offset: Double = 0) -> Double {
        let time = (t - offset).truncatingRemainder(dividingBy: lap)
        return time < 0 ? time + lap : time
    }
}

// MARK: - Colors

/// The empty states' colors, from the palette: a faint grid, paper cards,
/// green handwriting, and a green wash with a deeper green dashed edge for
/// what Ovyl is reading.
enum SceneColor {
    static let line = Palette.fill
    static let number = Palette.textSecondary.opacity(0.75)
    static let card = Palette.surface
    static let cardEdge = Palette.border
    static let cardShadow = Palette.shadow
    static let ink = Palette.accentText
    static let inset = Palette.fill
    static let sketch = Palette.textSecondary.opacity(0.45)
    static let highlight = Palette.accent.opacity(0.24)
    static let highlightSoft = Palette.accent.opacity(0.1)
    /// The dashed edge: decoration only, never text.
    static let highlightEdge = Palette.accentDeep
    /// Text that names what's being read.
    static let highlightText = Palette.accentText
    static let label = Palette.textSecondary
    static let pointer = Palette.textPrimary
}

// MARK: - Materials

extension View {
    /// A card in the notes' own look: white shading to a soft gray, a
    /// hairline edge and a soft shadow, with generous corners.
    func paperCard(cornerRadius: CGFloat = 16, lift: CGFloat = 1) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LinearGradient(colors: [CardColor.top, CardColor.bottom], startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(CardColor.edge, lineWidth: 1))
        .shadow(color: CardColor.shadow, radius: 9 * lift, y: 4 * lift)
    }
}

/// What Ovyl is reading: a pale blue fill inside a fine dashed blue line.
struct Dashed<S: Shape>: View {
    let shape: S
    var fill: Color = SceneColor.highlight

    var body: some View {
        shape
            .fill(fill)
            .overlay(shape.stroke(SceneColor.highlightEdge, style: StrokeStyle(lineWidth: 1, dash: [2.6, 2])))
    }
}

/// A small caption, such as "notes (0)".
struct MonoLabel: View {
    let name: String
    var count: String = "(0)"
    var active = true

    var body: some View {
        HStack(spacing: 5) {
            Text(name).foregroundStyle(active ? SceneColor.highlightText : SceneColor.label)
            Text(count).foregroundStyle(SceneColor.label)
        }
        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
    }
}

/// A note as a portrait page: the Home note card itself, laid out at full
/// size and scaled down, with a title, the start of its text fading out,
/// and the day and dots along the foot. `written` writes the text in from
/// the top, for a note being made.
struct NotePage: View {
    let title: String
    let text: String
    let day: String
    var width: CGFloat = 92
    var written: Double = 1
    var lift: CGFloat = 1

    /// The full card it's drawn from, 5 wide by 6 tall like Home's.
    static let base = CGSize(width: 300, height: 360)

    var height: CGFloat { width * Self.base.height / Self.base.width }

    var body: some View {
        let scale = width / Self.base.width
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(CardColor.title)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(text)
                .font(.system(size: 13))
                .lineSpacing(6.5)
                .foregroundStyle(CardColor.body)
                .padding(.top, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .mask(
                    LinearGradient(
                        stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.4), .init(color: .clear, location: 1)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .mask(
                    // The text writes in from the top.
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: max(0, min(1, written * 1.1 - 0.1))),
                            .init(color: .clear, location: max(0.0001, min(1, written * 1.1))),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            HStack(spacing: 0) {
                Text(day)
                    .font(.system(size: 14.5, weight: .semibold))
                    .tracking(1.7)
                    .foregroundStyle(CardColor.meta)
                    .lineLimit(1)
                Spacer(minLength: 6)
                MoreDots(color: CardColor.meta)
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 25)
        .padding(.top, 29)
        .padding(.bottom, 21)
        .frame(width: Self.base.width, height: Self.base.height, alignment: .topLeading)
        .background(shape.fill(LinearGradient(colors: [CardColor.top, CardColor.bottom], startPoint: .top, endPoint: .bottom)))
        .overlay(shape.strokeBorder(CardColor.edge, lineWidth: 1 / scale))
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: width, height: height, alignment: .topLeading)
        .shadow(color: CardColor.shadow, radius: 8 * lift, y: 4 * lift)
    }
}

/// The arrow pointer: dark with a light edge, light on dark in dark mode.
struct Pointer: View {
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 13
            let path = Path { p in
                p.move(to: CGPoint(x: 1 * s, y: 1 * s))
                p.addLine(to: CGPoint(x: 1 * s, y: 16 * s))
                p.addLine(to: CGPoint(x: 4.8 * s, y: 12.4 * s))
                p.addLine(to: CGPoint(x: 7.4 * s, y: 18.2 * s))
                p.addLine(to: CGPoint(x: 9.6 * s, y: 17.2 * s))
                p.addLine(to: CGPoint(x: 7.1 * s, y: 11.5 * s))
                p.addLine(to: CGPoint(x: 12 * s, y: 11.5 * s))
                p.closeSubpath()
            }
            path.fill(SceneColor.pointer)
                .overlay(path.stroke(SceneColor.card, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round)))
                .shadow(color: SceneColor.cardShadow, radius: 2, y: 1.5)
        }
        .frame(width: 13, height: 19)
    }
}

// MARK: - Writing

/// Text in Caveat that appears left to right as if being written, with an
/// optional hand-drawn underline that draws itself after.
struct Handwriting: View {
    let text: String
    let size: CGFloat
    let progress: Double
    var underline: Double?

    /// Caveat, a little heavier than regular, as a marker would write.
    private var font: NSFont { .caveat(size, wght: 620) }

    var body: some View {
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        // Handwriting reaches past its own box (tall loops, a last letter's
        // tail), and on screen a text is cut off at its box. So the text
        // only takes the word's place in the line, and the ink is drawn on
        // a canvas with room around it.
        let room = size * 0.35
        Text(text)
            .font(Font(font))
            .fixedSize()
            .hidden()
            .overlay {
                Canvas { context, canvas in
                    guard progress > 0 else { return }
                    let ink = context.resolve(Text(text).font(Font(font)).foregroundStyle(SceneColor.ink))
                    let origin = CGPoint(x: room, y: room)
                    guard progress < 1 else {
                        context.draw(ink, at: origin, anchor: .topLeading)
                        return
                    }
                    context.drawLayer { layer in
                        layer.draw(ink, at: origin, anchor: .topLeading)
                        // A soft edge sweeping across reads as a pen moving.
                        let edge = 0.14
                        let p = progress * (1 + edge)
                        layer.blendMode = .destinationIn
                        layer.fill(
                            Path(CGRect(origin: .zero, size: canvas)),
                            with: .linearGradient(
                                Gradient(stops: [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: max(0, min(1, p - edge))),
                                    .init(color: .clear, location: max(0.0001, min(1, p))),
                                ]),
                                startPoint: .zero, endPoint: CGPoint(x: canvas.width, y: 0)
                            )
                        )
                    }
                }
                .padding(-room)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                if let underline, underline > 0 {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 2))
                        path.addCurve(to: CGPoint(x: width * 0.55, y: 1), control1: CGPoint(x: width * 0.2, y: 3.4), control2: CGPoint(x: width * 0.35, y: 0))
                        path.addCurve(to: CGPoint(x: width + 2, y: 2.4), control1: CGPoint(x: width * 0.75, y: 2), control2: CGPoint(x: width * 0.9, y: 3.2))
                    }
                    .trim(from: 0, to: underline)
                    .stroke(SceneColor.ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: width + 2, height: 4)
                    .offset(y: 2)
                }
            }
    }
}

/// A short handwritten remark that writes itself from `start` at a steady
/// pace, line by line, and is underlined once written.
struct Remark: View {
    let lines: [String]
    let time: Double
    let start: Double

    static let perCharacter = 0.055

    init(_ lines: [String], time: Double, start: Double) {
        self.lines = lines
        self.time = time
        self.start = start
    }

    init(_ text: String, time: Double, start: Double) {
        self.init([text], time: time, start: start)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: -2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Handwriting(
                    text: line, size: 17,
                    progress: Ease.progress(time, from: lineStart(index), over: Double(line.count) * Self.perCharacter),
                    underline: index == lines.count - 1 ? Ease.inOut(Ease.progress(time, from: lineStart(lines.count) + 0.1, over: 0.5)) : nil
                )
            }
        }
        .padding(.leading, 4)
    }

    /// The room the remark takes once written: its widest line and its lines'
    /// height, with the room the writing reaches past its box.
    static func size(_ lines: [String]) -> CGSize {
        let font = NSFont.caveat(17, wght: 620)
        let width = lines.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return CGSize(width: (width + 4 + 10).rounded(.up), height: CGFloat(lines.count) * 21 + 6)
    }

    /// When line `index` starts; past the last line, when writing ends.
    private func lineStart(_ index: Int) -> Double {
        var start = self.start
        for line in lines.prefix(index) { start += Double(line.count) * Self.perCharacter + 0.15 }
        return start
    }
}

/// A left-to-right reveal with a soft edge, for masks. Reversed, it hides
/// instead, so two layers can trade places along the same edge.
struct Sweep: View {
    let progress: Double
    var reversed = false

    var body: some View {
        let edge = 0.12
        let p = progress * (1 + edge)
        let a = max(0, min(1, p - edge))
        let b = max(0.0001, min(1, p))
        LinearGradient(
            stops: reversed
                ? [.init(color: .clear, location: a), .init(color: .black, location: b)]
                : [.init(color: .black, location: a), .init(color: .clear, location: b)],
            startPoint: .leading, endPoint: .trailing
        )
    }
}
