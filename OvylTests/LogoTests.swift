import AppKit
import SwiftUI
import Testing
@testable import Ovyl

/// The logo's motions: what each stage plays, that every loop starts from
/// the mark, and that no piece jumps from one frame to the next.
struct LogoTests {
    @Test func stagesPickTheirMotion() {
        #expect(LogoMotion(stage: "Waiting") == .waiting)
        #expect(LogoMotion(stage: "Opening video") == .loading)
        #expect(LogoMotion(stage: "Opening audio") == .loading)
        #expect(LogoMotion(stage: "Opening pictures") == .loading)
        #expect(LogoMotion(stage: "Reading audio") == .listening)
        #expect(LogoMotion(stage: "Listening for music") == .listening)
        #expect(LogoMotion(stage: "Loading the speech model") == .preparing)
        #expect(LogoMotion(stage: "Getting the speech model ready (first time only, about a minute)") == .preparing)
        #expect(LogoMotion(stage: "Transcribing speech") == .transcribing)
        #expect(LogoMotion(stage: "Transcribing speech · Reading on-screen text") == .transcribing)
        #expect(LogoMotion(stage: "Reading on-screen text") == .reading)
        #expect(LogoMotion(stage: "Reading the pictures") == .reading)
        #expect(LogoMotion(stage: "Writing the note") == .writing)
        // A line no motion stands for, such as one between steps, gets none.
        #expect(LogoMotion(stage: "Working") == nil)
        #expect(LogoMotion(stage: "") == nil)
    }

    @Test func theMarkHasThreeUprightStrokes() {
        #expect(LogoPiece.logo.count == 3)
        for piece in LogoPiece.logo {
            #expect(piece.outline.points.count == LogoOutline.count)
            #expect(piece.extent.height > piece.extent.width * 3)
            // Each leans right, like the logo.
            #expect(piece.angle > 0.5 && piece.angle < 0.8)
        }
        #expect(LogoPiece.logo.map(\.extent.height) == LogoPiece.logo.map(\.extent.height).sorted(by: >))
    }

    @Test(arguments: LogoMotion.allCases)
    func startsAsTheMark(_ motion: LogoMotion) {
        let first = motion.script.pose(at: 0)
        for (piece, mark) in zip(first, LogoPiece.logo) {
            #expect(piece == mark)
        }
        #expect(first.dropFirst(3).allSatisfy { $0.scale == 0 })
    }

    /// Two laps sampled finely: a piece that leapt between samples would
    /// mean a beat started before the last had settled.
    @Test(arguments: LogoMotion.allCases)
    func movesWithoutJumps(_ motion: LogoMotion) {
        let script = motion.script
        let step = 1.0 / 240
        var previous = script.pose(at: 0)
        var time = step
        var leap: CGFloat = 0
        while time < script.introLength + script.loopLap * 2 {
            let pose = script.pose(at: time)
            for (a, b) in zip(previous, pose) where a.scale > 0.05 || b.scale > 0.05 {
                leap = max(leap, hypot(a.center.x - b.center.x, a.center.y - b.center.y), abs(a.scale - b.scale) * 10)
            }
            previous = pose
            time += step
        }
        #expect(leap < 1.6, "\(motion) leaps \(leap) points in a 240th of a second")
    }

    /// Speed carries from one beat into the next, from the intro into the
    /// loop and round it: over the intro and a lap and more, the largest change in velocity between
    /// neighbouring samples halves when the samples are twice as close. A
    /// beat that restarted a piece from rest would leave a jump in speed
    /// that stays the same size.
    @Test(arguments: LogoMotion.allCases)
    func speedNeverJumps(_ motion: LogoMotion) {
        let script = motion.script
        func kink(_ dt: Double) -> Double {
            var worst = 0.0
            var time = 0.05
            var a = script.pose(at: time - dt), b = script.pose(at: time)
            while time < script.introLength + script.loopLap * 1.3 {
                let c = script.pose(at: time + dt)
                for index in a.indices where b[index].scale > 0.05 {
                    for (p, q, r) in [(a[index], b[index], c[index])] {
                        let jumps = [
                            Double(r.center.x - 2 * q.center.x + p.center.x),
                            Double(r.center.y - 2 * q.center.y + p.center.y),
                            (r.angle - 2 * q.angle + p.angle) * 10,
                            Double(r.scale - 2 * q.scale + p.scale) * 20,
                        ]
                        worst = max(worst, jumps.map(abs).max()! / dt)
                    }
                }
                a = b
                b = c
                time += dt
            }
            return worst
        }
        let coarse = kink(1.0 / 600), fine = kink(1.0 / 1200)
        #expect(fine < coarse * 0.6, "\(motion): \(coarse) then \(fine)")
    }

    /// Handing over from mid-motion carries on at the same speed, straight
    /// into the new loader rather than back through the mark.
    @Test func switchingCarriesOn() {
        let handoff = LogoMotion.transcribing.script.handoff(at: 2.1, from: nil)
        let next = LogoMotion.writing.script
        let start = next.pose(at: 0, from: handoff)
        #expect(zip(start, handoff.pose).allSatisfy { $0 == $1 })
        let step = 1.0 / 4000
        let soon = next.pose(at: step, from: handoff)
        for index in 0..<3 {
            let speed = CGPoint(x: (soon[index].center.x - start[index].center.x) / step, y: (soon[index].center.y - start[index].center.y) / step)
            let was = handoff.rate[index].center
            #expect(hypot(speed.x - was.x, speed.y - was.y) < 5, "piece \(index) went \(speed), was \(was)")
        }
        var time = 0.0
        while time < 4 {
            #expect(!Self.isTheMark(next.pose(at: time, from: handoff)), "back to the mark at \(time)")
            time += 0.05
        }
    }

    /// Once a loader has taken its form it keeps it, looping, and never
    /// turns back into the mark, however long it runs.
    @Test(arguments: LogoMotion.allCases.filter { ![.loading, .waiting].contains($0) })
    func staysALoader(_ motion: LogoMotion) {
        let script = motion.script
        var time = script.introLength + 0.6
        while time < script.introLength + script.loopLap * 4 {
            #expect(!Self.isTheMark(script.pose(at: time)), "\(motion) is the mark again at \(time)")
            time += 0.05
        }
    }

    /// Whether the pieces stand as the mark: each stroke where the logo has it.
    private static func isTheMark(_ pieces: [LogoPiece]) -> Bool {
        zip(pieces, LogoPiece.logo).allSatisfy { piece, mark in
            hypot(piece.center.x - mark.center.x, piece.center.y - mark.center.y) < 1.5
                && abs(piece.angle - mark.angle) < 0.1
                && abs(piece.extent.height * piece.scale - mark.extent.height) < 3
        }
    }

    /// Every motion, from the mark through two laps of its loop, at ten
    /// frames a second, for checking by eye.
    /// Frames land in the test host's temporary folder under ovyl-logo.
    @MainActor
    @Test func renderMotions() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ovyl-logo")
        try? FileManager.default.removeItem(at: folder)
        for motion in LogoMotion.allCases {
            let script = motion.script
            let place = folder.appending(path: motion.rawValue)
            try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
            for index in 0..<Int((script.introLength + script.loopLap * 2) * 10) {
                let frame = LogoFrame(pieces: script.frame(at: Double(index) / 10))
                    .foregroundStyle(Color.black)
                    .frame(width: 120, height: 120)
                    .padding(20)
                    .background(Color.white)
                let renderer = ImageRenderer(content: frame)
                let image = try #require(renderer.cgImage)
                let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                try data.write(to: place.appending(path: String(format: "%03d.png", index)))
            }
        }
        print("LOGO \(folder.path)")
    }
}
