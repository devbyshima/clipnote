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

/// The empty states' colors, light and dark: a faint grid, paper cards,
/// marker-yellow handwriting, and blue for what Ovyl is reading.
enum SceneColor {
    private static func dynamic(_ light: (CGFloat, CGFloat, CGFloat, CGFloat), _ dark: (CGFloat, CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: c.3)
        })
    }

    static let line = dynamic((0, 0, 0, 0.065), (255, 255, 255, 0.055))
    static let number = dynamic((0, 0, 0, 0.3), (255, 255, 255, 0.28))
    static let card = dynamic((255, 255, 255, 1), (40, 40, 42, 1))
    static let cardEdge = dynamic((0, 0, 0, 0.07), (255, 255, 255, 0.06))
    static let cardShadow = dynamic((0, 0, 0, 0.06), (0, 0, 0, 0.35))
    static let ink = dynamic((190, 140, 10, 1), (235, 200, 80, 1))
    static let inset = dynamic((0, 0, 0, 0.045), (255, 255, 255, 0.045))
    static let sketch = dynamic((0, 0, 0, 0.2), (255, 255, 255, 0.2))
    static let highlight = dynamic((180, 210, 244, 0.6), (120, 170, 255, 0.16))
    static let highlightSoft = dynamic((196, 221, 248, 0.32), (120, 170, 255, 0.08))
    static let highlightEdge = dynamic((52, 126, 232, 0.95), (150, 190, 255, 0.75))
    static let label = dynamic((0, 0, 0, 0.38), (255, 255, 255, 0.4))
    static let pointer = dynamic((28, 28, 30, 1), (242, 242, 244, 1))
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
            Text(name).foregroundStyle(active ? SceneColor.highlightEdge : SceneColor.label)
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
        // Handwriting reaches past its own box (tall loops, long tails), so
        // the writing mask gets room around it.
        let room = size * 0.35
        Text(text)
            .font(Font(font))
            .foregroundStyle(SceneColor.ink)
            .fixedSize()
            .padding(room)
            .mask(alignment: .leading) {
                // A soft edge sweeping across reads as a pen moving.
                let edge = 0.14
                let p = progress * (1 + edge)
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: max(0, min(1, p - edge))),
                        .init(color: .clear, location: max(0.0001, min(1, p))),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .opacity(progress > 0 ? 1 : 0)
            }
            .padding(-room)
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
