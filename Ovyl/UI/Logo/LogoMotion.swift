import SwiftUI

// The logo, alive. Its three strokes come apart into simple shapes, act
// out what Ovyl is doing, and spring back into the mark. Each motion has
// one purpose and is used for nothing else: the strokes flow along while
// media opens, sway while a note waits its turn, circle like a wheel while
// the speech model gets ready, bounce as sound levels while the audio is
// heard, stand up as levels and lie down as lines of text while speech is
// transcribed, follow a scanner while the screen is read, write lines and
// fold them into a page while the note is written, hop like typing dots
// while the assistant thinks, and tumble into a heap when something fails.
//
// Every move is a spring, and a new move adds its spring on top of the ones
// still running instead of starting over, so a piece never stops dead or
// jerks: it carries its speed into the next move. Beats can follow each
// other before the last has settled, which is what keeps it flowing.

/// What the logo acts out, one purpose each.
enum LogoMotion: String, CaseIterable, Hashable {
    /// A video, recording or pictures opening.
    case loading
    /// A note queued behind another.
    case waiting
    /// The speech model getting ready.
    case preparing
    /// The audio being read and listened to for music.
    case listening
    /// Speech becoming text.
    case transcribing
    /// Text on screen, or in pictures, being read.
    case reading
    /// The note being written.
    case writing
    /// The assistant working on an answer.
    case thinking
    /// Something that couldn't be done.
    case failed

    /// The motion for a note's stage line: "Waiting" in the queue,
    /// "Opening …" as it starts, then the pipeline's steps by their exact
    /// wording; with steps side by side, the first. Nil for a line no
    /// motion stands for.
    init?(stage: String) {
        if stage == "Waiting" {
            self = .waiting
            return
        }
        if stage.hasPrefix("Opening ") {
            self = .loading
            return
        }
        switch ProgressBoard.Step.first(in: stage) {
        case .preparing: self = .loading
        case .extractingAudio, .listening: self = .listening
        case .loadingModel: self = .preparing
        case .transcribing: self = .transcribing
        case .readingScreen: self = .reading
        case .formatting: self = .writing
        case nil: return nil
        }
    }

    /// The motion for a note being made: waiting in the queue, or its stage.
    init(note: Note) {
        self = note.status == .queued ? .waiting : LogoMotion(stage: note.stage) ?? .loading
    }

    var label: String {
        switch self {
        case .loading: "Opening"
        case .waiting: "Waiting"
        case .preparing: "Getting the speech model ready"
        case .listening: "Listening"
        case .transcribing: "Transcribing"
        case .reading: "Reading the screen"
        case .writing: "Writing"
        case .thinking: "Thinking"
        case .failed: "Something went wrong"
        }
    }

    var script: LogoScript {
        switch self {
        case .loading: LogoScript.loading
        case .waiting: LogoScript.waiting
        case .preparing: LogoScript.preparing
        case .listening: LogoScript.listening
        case .transcribing: LogoScript.transcribing
        case .reading: LogoScript.reading
        case .writing: LogoScript.writing
        case .thinking: LogoScript.thinking
        case .failed: LogoScript.failed
        }
    }
}

/// A damped spring set off from rest.
enum LogoSpring {
    /// How far it has gone toward a target 1 away, `t` seconds in; past 1
    /// as it overshoots. Starts at 0 with no speed.
    static func step(_ t: Double, response: Double, damping: Double) -> Double {
        guard t > 0 else { return 0 }
        let omega = 2 * .pi / response
        let zeta = min(damping, 0.999)
        let damped = omega * (1 - zeta * zeta).squareRoot()
        return 1 - exp(-zeta * omega * t) * (cos(damped * t) + zeta * omega / damped * sin(damped * t))
    }

    /// Where it is `t` seconds after being flicked at speed 1 from where it
    /// rests: out and back.
    static func flick(_ t: Double, response: Double, damping: Double) -> Double {
        guard t > 0 else { return 0 }
        let omega = 2 * .pi / response
        let zeta = min(damping, 0.999)
        let damped = omega * (1 - zeta * zeta).squareRoot()
        return exp(-zeta * omega * t) * sin(damped * t) / damped
    }
}

/// One step of a motion: the pose the pieces spring into, and how.
struct Beat {
    var pose: [LogoPiece]
    /// The spring's response, in seconds, and its damping.
    var response = 0.42
    var damping = 0.74
    /// How long after one piece the next sets off.
    var stagger = 0.05
    /// The last piece sets off first.
    var reversed = false
    /// The order the pieces set off in, when it isn't by piece: each
    /// piece's place in line.
    var order: [Int]?
    /// Bows each piece's path upward by this share of the distance.
    var lift: CGFloat = 0
    /// How long until the next beat sets off; often before this one settles.
    var duration = 0.6

    func delay(_ piece: Int) -> Double {
        let place = order?[piece] ?? (reversed ? LogoScript.pieces - 1 - piece : piece)
        return stagger * Double(place)
    }

    func motion(_ t: Double) -> Double {
        LogoSpring.step(t, response: response, damping: damping)
    }

    /// Shapes change on a calmer spring than they move, so they settle
    /// without warping.
    func form(_ t: Double) -> Double {
        LogoSpring.step(t, response: response, damping: min(0.96, damping + 0.16))
    }

    /// How long after it sets off until every piece is still to within a
    /// ten-millionth of the way, the last piece's delay included.
    var settle: Double {
        let omega = 2 * .pi / response
        return 16 / (min(damping, 0.999) * omega) + (0..<LogoScript.pieces).map(delay).max()!
    }
}

/// Where another motion left the pieces, and how fast they were going.
struct LogoHandoff {
    var pose: [LogoPiece]
    var rate: [LogoPiece]
}

/// A motion in three parts: the mark, held a moment; an intro that turns
/// it into the loader's form; and the loader's loop, which repeats for as
/// long as it's shown and never goes back to the mark. Taking over from
/// another motion skips the mark and goes straight from where the pieces
/// are into this one's form.
struct LogoScript {
    static let pieces = 5
    let mark: Beat
    let intro: [Beat]
    let loop: [Beat]
    private let loopStarts: [Double]
    let loopLap: Double
    /// The longest any move takes to settle, past which it's folded in.
    private let settle: Double
    private let fresh: Line
    private let continuing: Line

    /// The beats before the loop, and when each sets off.
    private struct Line {
        let beats: [Beat]
        let starts: [Double]
        let length: Double

        init(_ beats: [Beat]) {
            self.beats = beats
            var starts: [Double] = []
            var total = 0.0
            for beat in beats {
                starts.append(total)
                total += beat.duration
            }
            self.starts = starts
            length = total
        }
    }

    init(mark: Beat, intro: [Beat] = [], loop: [Beat]) {
        func padded(_ beat: Beat) -> Beat {
            var beat = beat
            while beat.pose.count < Self.pieces { beat.pose.append(.hidden) }
            return beat
        }
        self.mark = padded(mark)
        self.intro = intro.map(padded)
        self.loop = loop.map(padded)
        let line = Line(self.loop)
        loopStarts = line.starts
        loopLap = line.length
        fresh = Line([self.mark] + self.intro)
        continuing = Line(self.intro)
        settle = ([self.mark] + self.intro + self.loop).map(\.settle).max() ?? 1
    }

    /// How long until the loop starts, shown from the mark.
    var introLength: Double { fresh.length }

    private func event(_ index: Int, on line: Line) -> (beat: Beat, at: Double) {
        if index < line.beats.count { return (line.beats[index], line.starts[index]) }
        let step = index - line.beats.count
        let position = step % loop.count
        return (loop[position], line.length + Double(step / loop.count) * loopLap + loopStarts[position])
    }

    private func current(at time: Double, on line: Line) -> Int {
        if time < line.length { return line.starts.lastIndex { $0 <= time } ?? 0 }
        let local = time - line.length
        let laps = (local / loopLap).rounded(.down)
        let position = loopStarts.lastIndex { $0 <= local - laps * loopLap } ?? 0
        return line.beats.count + Int(laps) * loop.count + position
    }

    /// The pieces `time` seconds in: the last pose long settled, plus every
    /// move since, each as far along its own spring as it has got. Shown
    /// fresh, it starts from the mark standing still; taking over, from
    /// `handoff`, carrying its speed.
    func pose(at time: Double, from handoff: LogoHandoff? = nil) -> [LogoPiece] {
        let time = max(0, time)
        let line = handoff == nil ? fresh : continuing
        let start = handoff?.pose ?? mark.pose
        let now = current(at: time, on: line)
        // Back to the newest move that has long settled; everything before
        // it has too, so the pose starts from where it ended.
        var first = now
        while first > 0, time - event(first, on: line).at <= settle { first -= 1 }
        var pieces: [LogoPiece]
        if time - event(first, on: line).at > settle {
            pieces = event(first, on: line).beat.pose
            first += 1
        } else {
            pieces = start
        }
        if first <= now {
            for index in first...now {
                let (beat, at) = event(index, on: line)
                let before = index == 0 ? start : event(index - 1, on: line).beat.pose
                for piece in pieces.indices {
                    let t = time - at - beat.delay(piece)
                    guard t > 0 else { continue }
                    let form = before[piece].outline == beat.pose[piece].outline ? 0 : beat.form(t)
                    pieces[piece].move(from: before[piece], to: beat.pose[piece], motion: beat.motion(t), form: form, lift: beat.lift)
                }
            }
        }
        if let handoff, time < 3 {
            let flick = LogoSpring.flick(time, response: 0.5, damping: 0.8)
            for piece in pieces.indices {
                pieces[piece].add(handoff.rate[piece], times: flick)
            }
        }
        return pieces
    }

    /// The pose to draw: each piece pulled out along the way it's moving,
    /// up to a fifth longer the faster it goes, and pressed flat along the
    /// way it's pushed, up to a sixth, so it squashes as a spring sets it
    /// off and again as it brakes past its mark.
    func frame(at time: Double, from handoff: LogoHandoff? = nil) -> [LogoPiece] {
        let h = 1.0 / 240
        var pieces = pose(at: time, from: handoff)
        let before = pose(at: time - h, from: handoff)
        let earlier = pose(at: time - 2 * h, from: handoff)
        for index in pieces.indices {
            let give = max(0, min(1, pieces[index].elasticity))
            guard give > 0.01 else { continue }
            let now = pieces[index].center, then = before[index].center, first = earlier[index].center
            let vx = (now.x - then.x) / h, vy = (now.y - then.y) / h
            let speed = hypot(vx, vy)
            if speed > 1 {
                let amount = 0.2 * tanh(speed * 0.0016 / 0.2) * give
                pieces[index].stretch = CGVector(dx: vx / speed * amount, dy: vy / speed * amount)
            }
            let ax = (now.x - 2 * then.x + first.x) / (h * h), ay = (now.y - 2 * then.y + first.y) / (h * h)
            let push = hypot(ax, ay)
            if push > 50 {
                let amount = 0.16 * tanh(push * 0.000028 / 0.16) * give
                pieces[index].squash = CGVector(dx: ax / push * amount, dy: ay / push * amount)
            }
        }
        return pieces
    }

    /// Where the pieces are and how fast they're going, `time` in, for
    /// another motion to carry on from.
    func handoff(at time: Double, from earlier: LogoHandoff?) -> LogoHandoff {
        let interval = 1.0 / 240
        let now = pose(at: time, from: earlier)
        let before = pose(at: time - interval, from: earlier)
        return LogoHandoff(pose: now, rate: zip(now, before).map { $0.rate(since: $1, over: interval) })
    }
}

// MARK: - Poses

extension LogoPiece {
    static let large = logo[0], medium = logo[1], small = logo[2]

    /// Shrunk to nothing where the small stroke stands.
    static let hidden = LogoPiece(outline: .circle(small.extent.width), center: small.center, scale: 0)

    /// The ground the logo's strokes stand on.
    static let ground: CGFloat = 44.3

    /// Shrunk to nothing at `point`.
    static func gone(at point: CGPoint) -> LogoPiece {
        LogoPiece(outline: .circle(6), center: point, scale: 0)
    }

    /// Standing on the ground, centered on `x`, leaning by `lean`.
    static func bar(_ x: CGFloat, height: CGFloat, width: CGFloat = 8.5, lean: Double = 0) -> LogoPiece {
        LogoPiece(outline: .capsule(width, height), center: CGPoint(x: x, y: ground - height / 2), angle: lean, elasticity: 0)
    }

    /// Lying down from `left`, centered on `y`: a stroke tipped over to the
    /// right, so it turns rather than squashes.
    static func line(_ y: CGFloat, length: CGFloat, left: CGFloat = 8, thickness: CGFloat = 6.5) -> LogoPiece {
        LogoPiece(outline: .capsule(thickness, length), center: CGPoint(x: left + length / 2, y: y), angle: .pi / 2, elasticity: 0)
    }

    /// A dot, turned by `angle` so it can stretch into a line without
    /// swinging round.
    static func dot(_ x: CGFloat, _ y: CGFloat, size: CGFloat = 8.5, angle: Double = 0) -> LogoPiece {
        LogoPiece(outline: .circle(size), center: CGPoint(x: x, y: y), angle: angle)
    }

    /// The logo with its strokes shifted along: the stroke at `slot` 0 is
    /// the largest, 3 waits to come in on the right, 4 has left.
    static func conveyor(_ slot: Int) -> LogoPiece {
        switch slot {
        case 0: large
        case 1: medium
        case 2: small
        case 3: gone(at: CGPoint(x: small.center.x + 7, y: small.center.y + 5))
        // Out past its own foot, so it clears the place for the next.
        default: gone(at: CGPoint(x: 6, y: 40))
        }
    }
}

extension LogoScript {
    static let logo = [LogoPiece.large, .medium, .small]

    /// The mark, held a moment before it becomes a loader.
    private static func mark(_ duration: Double = 0.6) -> Beat {
        Beat(pose: logo, response: 0.5, damping: 0.7, stagger: 0.07, duration: duration)
    }

    /// Text lines, top to bottom, around the logo's middle.
    private static let rows: [CGFloat] = [12.6, 22.6, 32.6]

    /// Three sound levels, left to right, leaning by `lean`.
    private static func bars(_ heights: [CGFloat], lean: Double = 0) -> [LogoPiece] {
        [.bar(12, height: heights[0], lean: lean), .bar(24, height: heights[1], lean: lean), .bar(36, height: heights[2], lean: lean)]
    }

    /// Levels that rise and fall like speech, never quite repeating within a loop.
    private static let levels: [[CGFloat]] = [
        [16, 34, 24], [30, 14, 36], [20, 28, 12], [34, 18, 26], [14, 30, 20], [26, 22, 32],
        [18, 36, 14], [32, 16, 28], [22, 26, 34], [12, 32, 18],
    ]

    /// Media opening: the strokes flow left one place at a time, hopping a
    /// little: the largest shrinks away, the others grow into the place
    /// ahead, and a new one grows in on the right. Each move sets off
    /// before the last has settled, so the mark is always whole and never
    /// still.
    static let loading = LogoScript(
        mark: mark(0.4),
        loop: [1, 2, 3, 4, 5].map { shift in
            Beat(
                pose: (0..<5).map { piece in LogoPiece.conveyor(((piece - shift) % 5 + 5) % 5) },
                response: 0.62,
                damping: 0.8,
                stagger: 0.08,
                // The leaving stroke first, the newcomer last.
                order: (0..<5).map { piece in ((piece - shift + 1) % 5 + 5) % 5 },
                lift: 0.12,
                duration: 0.8
            )
        }
    )

    /// A note waiting its turn: the mark sways gently, one stroke after
    /// another, as if shifting its weight in a line.
    static let waiting: LogoScript = {
        func lean(_ by: Double) -> [LogoPiece] { logo.map { var piece = $0; piece.angle += by; return piece } }
        return LogoScript(mark: mark(0.8), loop: [
            Beat(pose: lean(0.16), response: 1.0, damping: 0.62, stagger: 0.16, duration: 1.4),
            Beat(pose: lean(-0.09), response: 1.0, damping: 0.62, stagger: 0.16, duration: 1.3),
            Beat(pose: lean(0.04), response: 1.0, damping: 0.62, stagger: 0.16, duration: 1.2),
        ])
    }()

    /// The speech model getting ready: the strokes pull into dots that
    /// circle the middle like a wheel turning over, for as long as it takes.
    static let preparing: LogoScript = {
        func wheel(_ turn: Double) -> [LogoPiece] {
            [9.0, 7.5, 6.0].enumerated().map { index, size in
                let angle = (turn + Double(index) / 3) * 2 * .pi
                return LogoPiece.dot(24 + 11 * CGFloat(sin(angle)), 23 - 11 * CGFloat(cos(angle)), size: size)
            }
        }
        // Eighths of a turn, each set off before the last arrives, so the
        // dots run round smoothly instead of corner to corner.
        return LogoScript(
            mark: mark(),
            intro: [Beat(pose: wheel(0), response: 0.5, damping: 0.8, stagger: 0.06, duration: 0.5)],
            loop: (1...8).map { step in
                Beat(pose: wheel(Double(step) / 8), response: 0.4, damping: 0.92, stagger: 0, duration: 0.22)
            }
        )
    }()

    /// The audio being heard: the strokes stand up as sound levels and keep
    /// bouncing for as long as it lasts.
    static let listening = LogoScript(
        mark: mark(),
        intro: [Beat(pose: bars([30, 20, 12]), response: 0.46, damping: 0.74, stagger: 0.06, duration: 0.4)],
        loop: levels.map { Beat(pose: bars($0), response: 0.3, damping: 0.55, stagger: 0.035, duration: 0.2) }
    )

    /// Speech becoming text: the strokes stand up as sound levels and
    /// bounce, lean back, tip over into lines of text, and stand back up to
    /// listen again.
    static let transcribing = LogoScript(
        mark: mark(),
        intro: [Beat(pose: bars([30, 20, 12]), response: 0.46, damping: 0.74, stagger: 0.06, duration: 0.4)],
        loop: levels.prefix(7).map { Beat(pose: bars($0), response: 0.3, damping: 0.55, stagger: 0.035, duration: 0.2) }
            + [
                Beat(pose: bars([26, 22, 16], lean: -0.2), response: 0.26, damping: 0.7, stagger: 0.03, duration: 0.2),
                // One after another, like dominoes, each clear of the next.
                Beat(pose: [.line(rows[0], length: 33), .line(rows[1], length: 33), .line(rows[2], length: 19)], response: 0.52, damping: 0.72, stagger: 0.15, lift: 0.15, duration: 1.7),
                // Back up again, the last line first.
                Beat(pose: bars([28, 22, 16]), response: 0.5, damping: 0.72, stagger: 0.12, reversed: true, lift: 0.1, duration: 0.6),
            ]
    )

    /// Text on screen being read: a scanner sweeps across and lines of text
    /// grow behind it, then it sweeps back and they're read again.
    static let reading: LogoScript = {
        let scanner = LogoOutline.capsule(5, 40)
        let lines: [LogoPiece] = [.line(rows[0], length: 28, left: 9.75), .line(rows[1], length: 22, left: 9.75), .line(rows[2], length: 26, left: 9.75)]
        let dots = rows.map { LogoPiece.dot(13, $0, size: 6.5, angle: .pi / 2) }
        let left = LogoPiece(outline: scanner, center: CGPoint(x: 6, y: 22.6))
        let right = LogoPiece(outline: scanner, center: CGPoint(x: 42, y: 22.6))
        var start = mark()
        start.pose += [.gone(at: CGPoint(x: 6, y: 22.6))]
        return LogoScript(
            mark: start,
            intro: [Beat(pose: dots + [left], response: 0.46, damping: 0.76, stagger: 0.05, duration: 0.5)],
            loop: [
                // The scanner leads; each line follows a moment behind it.
                Beat(pose: lines + [right], response: 1.0, damping: 0.92, stagger: 0.07, order: [1, 2, 3, 0, 4], duration: 1.3),
                Beat(pose: lines + [right], duration: 0.6),
                // Back across, the lines drawing in behind it, to read again.
                Beat(pose: dots + [left], response: 1.0, damping: 0.92, stagger: 0.07, order: [1, 2, 3, 0, 4], duration: 1.4),
            ]
        )
    }()

    /// The note being written: lines written one after another, folded into
    /// a page, and the page opened back out to write again.
    static let writing: LogoScript = {
        let dots = rows.map { LogoPiece.dot(11, $0, size: 6.5, angle: .pi / 2) }
        return LogoScript(
            mark: mark(),
            intro: [Beat(pose: dots, response: 0.44, damping: 0.76, stagger: 0.05, duration: 0.45)],
            loop: [
                Beat(pose: [.line(rows[0], length: 32), .line(rows[1], length: 27), .line(rows[2], length: 17)], response: 0.62, damping: 0.88, stagger: 0.32, duration: 1.7),
                Beat(
                    pose: Array(repeating: LogoPiece(outline: .rect(33, 27, radius: 4.5), center: CGPoint(x: 24, y: 23), angle: .pi / 2, elasticity: 0), count: 3),
                    response: 0.5, damping: 0.72, stagger: 0.03, reversed: true, duration: 1.2
                ),
                Beat(pose: dots, response: 0.46, damping: 0.78, stagger: 0.06, duration: 0.6),
            ]
        )
    }()

    /// The assistant working on an answer: dots that hop one after another,
    /// then rest, again and again.
    static let thinking: LogoScript = {
        func dots(_ y: CGFloat) -> [LogoPiece] { [.dot(12, y), .dot(24, y), .dot(36, y)] }
        return LogoScript(
            mark: mark(0.4),
            intro: [Beat(pose: dots(24), response: 0.42, damping: 0.76, stagger: 0.05, duration: 0.45)],
            loop: [
                Beat(pose: dots(15), response: 0.34, damping: 0.62, stagger: 0.12, duration: 0.22),
                Beat(pose: dots(24), response: 0.34, damping: 0.62, stagger: 0.12, duration: 0.75),
            ]
        )
    }()

    /// Something that couldn't be done: the strokes wobble, pull into balls
    /// and tumble into a heap, where they stay, the ball now and then
    /// trying a hop.
    static let failed: LogoScript = {
        let block = LogoOutline.rect(13, 13, radius: 3), ball = LogoOutline.circle(11), cone = LogoOutline.triangle(12, 10.5)
        func heap(ball height: CGFloat) -> [LogoPiece] {
            [
                LogoPiece(outline: block, center: CGPoint(x: 13, y: LogoPiece.ground - 6.5), angle: .pi + 0.1),
                LogoPiece(outline: ball, center: CGPoint(x: 26.5, y: LogoPiece.ground - height), angle: .pi),
                LogoPiece(outline: cone, center: CGPoint(x: 38.5, y: LogoPiece.ground - 6.1), angle: -2 * .pi / 3),
            ]
        }
        let balls = [11.0, 8.0, 5.8].enumerated().map { index, size in
            LogoPiece(outline: .circle(size), center: LogoPiece.logo[index].center, angle: LogoPiece.logo[index].angle)
        }
        return LogoScript(
            mark: mark(1.0),
            intro: [
                Beat(pose: logo.map { var piece = $0; piece.angle -= 0.16; return piece }, response: 0.22, damping: 0.4, stagger: 0.03, duration: 0.24),
                Beat(pose: balls, response: 0.3, damping: 0.8, stagger: 0.03, duration: 0.16),
                Beat(pose: heap(ball: 5.5), response: 0.6, damping: 0.5, stagger: 0.11, lift: 0.6, duration: 1.6),
            ],
            loop: [
                Beat(pose: heap(ball: 16), response: 0.3, damping: 0.8, duration: 0.2),
                Beat(pose: heap(ball: 5.5), response: 0.36, damping: 0.42, duration: 2.4),
            ]
        )
    }()
}

// MARK: - Views

/// The pieces drawn in the foreground style, the logo's square fitted to
/// the frame. Drawn off the main thread, so a busy app doesn't stutter it.
struct LogoFrame: View {
    let pieces: [LogoPiece]

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let fit = OvylLogo.fit(in: CGRect(origin: .zero, size: size))
            for piece in pieces where piece.scale > 0.02 {
                context.fill(piece.path.applying(fit), with: .foreground)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The logo acting out `motion`: the mark turns into the loader and stays
/// one, looping, until it's taken away. Switching motion carries the pieces
/// on from where they are, at the speed they're going, straight into the
/// new loader. With Reduce Motion the mark stays whole and
/// breathes.
struct LogoLoader: View {
    var motion: LogoMotion

    @Environment(\.motionTime) private var fixed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playing: LogoMotion
    @State private var start = Date.now
    @State private var handoff: LogoHandoff?

    init(_ motion: LogoMotion) {
        self.motion = motion
        _playing = State(initialValue: motion)
        // Starts near the end of the mark's hold, so a short wait still
        // sees it move.
        _start = State(initialValue: Date.now.addingTimeInterval(-max(0, motion.script.mark.duration - 0.3)))
    }

    var body: some View {
        Group {
            if let fixed {
                LogoFrame(pieces: motion.script.frame(at: fixed))
            } else if reduceMotion {
                TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                    let t = context.date.timeIntervalSince(start)
                    OvylMark().opacity(motion == .failed ? 0.6 : 0.55 + 0.45 * (0.5 + 0.5 * cos(t * 2.6)))
                }
            } else {
                TimelineView(.animation) { context in
                    LogoFrame(pieces: playing.script.frame(at: context.date.timeIntervalSince(start), from: handoff))
                }
            }
        }
        .onChange(of: motion) { _, next in
            let now = Date.now
            handoff = playing.script.handoff(at: now.timeIntervalSince(start), from: handoff)
            playing = next
            start = now
        }
        .accessibilityElement()
        .accessibilityLabel(motion.label)
    }
}
