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

/// A loop of beats. The first is always the logo, so a motion starts from
/// the mark, and any motion can hand over to another through it.
struct LogoScript {
    static let pieces = 5
    let beats: [Beat]
    private let starts: [Double]
    /// Which pieces change shape in each beat, from the one before.
    private let reshapes: [[Bool]]
    let lap: Double

    /// Every loop but the conveyor ends by pulling each piece into a dot
    /// where it is, then gathering the dots where the strokes stand, the
    /// last piece first so none runs into another; the strokes then grow
    /// out of them, as the reference's shapes grow out of dots. Swinging
    /// the long stroke in from anywhere else would sweep it across the
    /// others.
    init(_ beats: [Beat], gathers: Bool = true) {
        var beats = beats.map { beat in
            var beat = beat
            while beat.pose.count < Self.pieces { beat.pose.append(.hidden) }
            return beat
        }
        if gathers, let last = beats.last {
            let sizes: [CGFloat] = [11, 8, 5.8, 5.8, 5.8]
            let dots = last.pose.enumerated().map { index, piece in
                LogoPiece(outline: .circle(sizes[index]), center: piece.center, angle: piece.angle, scale: piece.scale)
            }
            beats.append(Beat(pose: dots, response: 0.3, damping: 0.8, stagger: 0.03, reversed: true, duration: 0.18))
            beats.append(Beat(pose: LogoPiece.gathered + [.hidden, .hidden], response: 0.42, damping: 0.78, stagger: 0.07, reversed: true, duration: 0.44))
        }
        self.beats = beats
        reshapes = beats.indices.map { index in
            let before = beats[(index + beats.count - 1) % beats.count].pose
            return zip(before, beats[index].pose).map { $0.outline != $1.outline }
        }
        var starts: [Double] = []
        var total = 0.0
        for beat in self.beats {
            starts.append(total)
            total += beat.duration
        }
        self.starts = starts
        lap = total
    }

    /// The pieces `time` seconds in: the pose a lap back, which has long
    /// settled, plus every move since, each as far along its own spring as
    /// it has got. The first lap starts from `handoff`, carrying its speed,
    /// or else from the logo standing still.
    func pose(at time: Double, from handoff: LogoHandoff? = nil) -> [LogoPiece] {
        let time = max(0, time)
        let count = beats.count
        let laps = (time / lap).rounded(.down)
        let index = starts.lastIndex { $0 <= time - laps * lap } ?? 0
        let current = Int(laps) * count + index
        let first = max(0, current - count + 1)
        let start = handoff?.pose ?? beats[0].pose
        var pieces = first == 0 ? start : beats[(first - 1) % count].pose
        // Moves that have long settled, in an unbroken run from the oldest,
        // are folded into the pose they reached.
        var folding = true
        for event in first...current {
            let beat = beats[event % count]
            let at = Double(event / count) * lap + starts[event % count]
            if folding, time - at > beat.settle {
                pieces = beat.pose
                continue
            }
            folding = false
            let before = event == 0 ? start : beats[(event - 1) % count].pose
            let reshape = event == 0 && handoff != nil ? nil : reshapes[event % count]
            for piece in pieces.indices {
                let t = time - at - beat.delay(piece)
                guard t > 0 else { continue }
                let form = reshape?[piece] == false ? 0 : beat.form(t)
                pieces[piece].move(from: before[piece], to: beat.pose[piece], motion: beat.motion(t), form: form, lift: beat.lift)
            }
        }
        if let handoff, time < lap {
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

    /// Dots where the strokes stand, turned as they are, ready to stretch
    /// into them.
    static let gathered = [11.0, 8.0, 5.8].enumerated().map { index, size in
        LogoPiece(outline: .circle(size), center: logo[index].center, angle: logo[index].angle)
    }

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

    /// The strokes stretching out of the gathered dots into the mark, which
    /// holds for a moment.
    private static func mark(_ duration: Double = 1.05) -> Beat {
        Beat(pose: logo, response: 0.5, damping: 0.62, stagger: 0.07, duration: duration)
    }

    /// Text lines, top to bottom, around the logo's middle.
    private static let rows: [CGFloat] = [12.6, 22.6, 32.6]

    /// Media opening: the strokes flow left one place at a time, hopping a little: the
    /// largest shrinks away, the others grow into the place ahead, and a
    /// new one grows in on the right. Each move sets off before the last
    /// has settled, so the mark is always whole and never still.
    static let loading = LogoScript((0..<5).map { shift in
        Beat(
            pose: (0..<5).map { piece in LogoPiece.conveyor(((piece - shift) % 5 + 5) % 5) },
            response: 0.62,
            damping: 0.8,
            stagger: 0.07,
            // The leaving stroke first, the newcomer last.
            order: (0..<5).map { piece in ((piece - shift + 1) % 5 + 5) % 5 },
            lift: 0.12,
            duration: 0.62
        )
    }, gathers: false)

    /// Three sound levels, left to right, leaning by `lean`.
    private static func bars(_ heights: [CGFloat], lean: Double = 0) -> [LogoPiece] {
        [.bar(12, height: heights[0], lean: lean), .bar(24, height: heights[1], lean: lean), .bar(36, height: heights[2], lean: lean)]
    }

    /// A note waiting its turn: the mark sways gently, one stroke after
    /// another, as if shifting its weight in a line, and settles.
    static let waiting: LogoScript = {
        func lean(_ by: Double) -> [LogoPiece] { logo.map { var piece = $0; piece.angle += by; return piece } }
        return LogoScript([
            Beat(pose: logo, response: 0.9, damping: 0.62, stagger: 0.14, duration: 1.3),
            Beat(pose: lean(0.16), response: 0.95, damping: 0.6, stagger: 0.14, duration: 1.05),
            Beat(pose: lean(-0.09), response: 0.95, damping: 0.6, stagger: 0.14, duration: 0.95),
        ], gathers: false)
    }()

    /// The speech model getting ready: the strokes pull into dots that
    /// circle the middle twice, like a wheel turning over, then come back.
    static let preparing: LogoScript = {
        func wheel(_ turn: Double) -> [LogoPiece] {
            [9.0, 7.5, 6.0].enumerated().map { index, size in
                let angle = (turn + Double(index) / 3) * 2 * .pi
                return LogoPiece.dot(24 + 11 * CGFloat(sin(angle)), 23 - 11 * CGFloat(cos(angle)), size: size)
            }
        }
        // Eighths of a turn, each set off before the last arrives, so the
        // dots run round smoothly instead of corner to corner.
        let turning = (1...16).map { step in
            Beat(pose: wheel(Double(step) / 8), response: 0.34, damping: 0.92, stagger: 0, duration: 0.16)
        }
        return LogoScript(
            [mark(0.9), Beat(pose: wheel(0), response: 0.45, damping: 0.8, stagger: 0.06, duration: 0.45)]
                + turning
                + [Beat(pose: wheel(2), response: 0.4, damping: 0.85, stagger: 0, duration: 0.3)]
        )
    }()

    /// The audio being heard: the strokes stand up as sound levels and
    /// keep bouncing, before any words come of it.
    static let listening: LogoScript = {
        let levels: [[CGFloat]] = [[16, 34, 24], [30, 14, 36], [20, 28, 12], [34, 18, 26], [14, 30, 20], [26, 22, 32], [18, 36, 14], [32, 16, 28]]
        return LogoScript(
            [mark(), Beat(pose: bars([30, 20, 12]), response: 0.44, damping: 0.74, stagger: 0.06, duration: 0.34)]
                + levels.map { Beat(pose: bars($0), response: 0.26, damping: 0.52, stagger: 0.03, duration: 0.16) }
                + [Beat(pose: bars([30, 20, 12]), response: 0.36, damping: 0.7, stagger: 0.04, duration: 0.45)]
        )
    }()

    /// Speech becoming text: the strokes stand up as sound levels and
    /// bounce, lean back, then tip over into lines of text.
    static let transcribing: LogoScript = {
        let levels: [[CGFloat]] = [[16, 34, 24], [30, 14, 36], [20, 28, 12], [34, 18, 26], [14, 30, 20], [26, 22, 32]]
        return LogoScript(
            [mark(), Beat(pose: bars([30, 20, 12]), response: 0.44, damping: 0.74, stagger: 0.06, duration: 0.34)]
                + levels.map { Beat(pose: bars($0), response: 0.26, damping: 0.52, stagger: 0.03, duration: 0.16) }
                + [
                    Beat(pose: bars([26, 22, 16], lean: -0.2), response: 0.24, damping: 0.7, stagger: 0.03, duration: 0.17),
                    // One after another, like dominoes, each clear of the next.
                    Beat(pose: [.line(rows[0], length: 33), .line(rows[1], length: 33), .line(rows[2], length: 19)], response: 0.5, damping: 0.72, stagger: 0.15, lift: 0.15, duration: 1.4),
                ]
        )
    }()

    /// A scanner grows up on the left and sweeps across; the strokes, as
    /// dots, grow into lines of text behind it as it passes, and it shrinks
    /// away on the right.
    static let reading: LogoScript = {
        let scanner = LogoOutline.capsule(5, 40)
        let lines: [LogoPiece] = [.line(rows[0], length: 28, left: 9.75), .line(rows[1], length: 22, left: 9.75), .line(rows[2], length: 26, left: 9.75)]
        var start = mark()
        start.pose += [.gone(at: CGPoint(x: 6, y: 22.6))]
        return LogoScript([
            start,
            Beat(
                pose: rows.map { LogoPiece.dot(13, $0, size: 6.5, angle: .pi / 2) } + [LogoPiece(outline: scanner, center: CGPoint(x: 6, y: 22.6))],
                response: 0.44, damping: 0.76, stagger: 0.05, duration: 0.42
            ),
            // The scanner leads; each line follows a moment behind it.
            Beat(pose: lines + [LogoPiece(outline: scanner, center: CGPoint(x: 42, y: 22.6))], response: 0.95, damping: 0.92, stagger: 0.07, order: [1, 2, 3, 0, 4], duration: 1.0),
            Beat(pose: lines + [.gone(at: CGPoint(x: 42, y: 22.6))], response: 0.32, damping: 0.8, duration: 0.75),
        ])
    }()

    /// The strokes lie down as lines written one after another, the lines
    /// fold into a page, and the page splits back into the mark.
    static let writing = LogoScript([
        mark(),
        Beat(pose: rows.map { LogoPiece.dot(11, $0, size: 6.5, angle: .pi / 2) }, response: 0.42, damping: 0.76, stagger: 0.05, duration: 0.32),
        Beat(pose: [.line(rows[0], length: 32), .line(rows[1], length: 27), .line(rows[2], length: 17)], response: 0.6, damping: 0.88, stagger: 0.3, duration: 1.45),
        Beat(
            pose: Array(repeating: LogoPiece(outline: .rect(33, 27, radius: 4.5), center: CGPoint(x: 24, y: 23), angle: .pi / 2, elasticity: 0), count: 3),
            response: 0.48, damping: 0.72, stagger: 0.03, reversed: true, duration: 0.95
        ),
    ])

    /// The strokes round into dots that hop one after another, three times.
    static let thinking: LogoScript = {
        func dots(_ y: CGFloat) -> [LogoPiece] { [.dot(12, y), .dot(24, y), .dot(36, y)] }
        let hop = [
            Beat(pose: dots(15), response: 0.34, damping: 0.62, stagger: 0.11, duration: 0.2),
            Beat(pose: dots(24), response: 0.34, damping: 0.62, stagger: 0.11, duration: 0.34),
        ]
        var beats = [mark(1.0), Beat(pose: dots(24), response: 0.4, damping: 0.76, stagger: 0.05, duration: 0.4)] + hop + hop + hop
        beats[beats.count - 1].duration = 0.5
        return LogoScript(beats)
    }()

    /// The strokes wobble, pull into balls and tumble off into a heap of
    /// shapes on the ground, the ball tries a hop, and they pull themselves
    /// back up together.
    static let failed: LogoScript = {
        let block = LogoOutline.rect(13, 13, radius: 3), ball = LogoOutline.circle(11), cone = LogoOutline.triangle(12, 10.5)
        func heap(ball height: CGFloat) -> [LogoPiece] {
            [
                LogoPiece(outline: block, center: CGPoint(x: 13, y: LogoPiece.ground - 6.5), angle: .pi + 0.1),
                LogoPiece(outline: ball, center: CGPoint(x: 26.5, y: LogoPiece.ground - height), angle: .pi),
                LogoPiece(outline: cone, center: CGPoint(x: 38.5, y: LogoPiece.ground - 6.1), angle: -2 * .pi / 3),
            ]
        }
        return LogoScript([
            mark(1.3),
            Beat(pose: logo.map { var piece = $0; piece.angle -= 0.16; return piece }, response: 0.22, damping: 0.4, stagger: 0.03, duration: 0.24),
            Beat(pose: LogoPiece.gathered, response: 0.3, damping: 0.8, stagger: 0.03, duration: 0.16),
            Beat(pose: heap(ball: 5.5), response: 0.6, damping: 0.5, stagger: 0.11, lift: 0.6, duration: 1.5),
            Beat(pose: heap(ball: 16), response: 0.3, damping: 0.8, duration: 0.2),
            Beat(pose: heap(ball: 5.5), response: 0.36, damping: 0.42, duration: 0.9),
        ])
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

/// The logo acting out `motion`, looping. Switching motion carries the
/// pieces on from where they are, at the speed they're going, into the
/// mark and the new motion. With Reduce Motion the mark stays whole and
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
        _start = State(initialValue: Date.now.addingTimeInterval(-max(0, motion.script.beats[0].duration - 0.3)))
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
