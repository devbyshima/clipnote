import SwiftUI

/// Ovyl's mark: three slanted strokes, tallest first, standing on one line.
/// Drawn from the logo's own curves, in its 48-point square.
enum OvylLogo {
    static let box: CGFloat = 48

    /// The strokes as in the logo's SVG, largest first.
    private static let svg = [
        "M33.95,0.97C30.53,0.97 24.25,5.11 16.6,13.43C6.69,24.12 0.91,35.51 0.91,40.76C0.91,43.08 1.92,44.19 3.65,44.19C4.72,44.19 5.79,43.83 6.87,43.28C10.94,41.31 16.07,36.75 21.75,30.34C28.64,22.55 33.51,14.95 35.76,8.62C36.37,6.89 36.69,5.39 36.69,4.21C36.69,1.95 35.75,0.88 33.84,0.97L33.95,0.97Z",
        "M41.4,15.17C40.31,15.17 38.8,15.87 37.13,17.16C34.29,19.39 31.08,23.05 27.6,27.84C23.25,33.85 20.96,38.81 20.96,41.61C20.96,43.41 21.75,44.3 22.97,44.3C24.4,44.3 26.51,43.17 28.77,41.22C32.08,38.3 35.67,34.09 38.78,28.93C41.88,23.93 43.39,19.99 43.39,17.79C43.39,16.08 42.64,15.17 41.4,15.17Z",
        "M45.93,27.78C45.08,27.78 43.68,28.51 42.27,29.81C40.67,31.29 38.88,33.51 37.09,36.13C35.15,38.94 34.19,41.41 34.19,42.78C34.19,43.84 34.65,44.36 35.37,44.36C36.51,44.36 38.26,43.18 40.29,41.04C42.13,39.1 43.83,36.81 45.22,34.42C46.48,32.2 47.09,30.32 47.09,29.32C47.09,28.29 46.66,27.78 45.93,27.78Z",
    ]

    /// Each stroke's outline as a closed run of points, in the logo's square.
    static let polygons: [[CGPoint]] = svg.map(flatten)

    static let strokes: [Path] = polygons.map { points in
        Path { path in path.addLines(points); path.closeSubpath() }
    }

    /// Fits the logo's square into `rect`, centered.
    static func fit(in rect: CGRect) -> CGAffineTransform {
        let side = min(rect.width, rect.height)
        let scale = side / box
        return CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2).scaledBy(x: scale, y: scale)
    }

    /// The SVG's moves, lines and curves as points, each curve in small steps.
    private static func flatten(_ data: String) -> [CGPoint] {
        var numbers: [CGFloat] = []
        var commands: [(Character, [CGFloat])] = []
        var current: Character?
        var token = ""
        func flushNumber() {
            if let value = Double(token) { numbers.append(CGFloat(value)) }
            token = ""
        }
        for character in data {
            if character.isLetter {
                flushNumber()
                if let current { commands.append((current, numbers)) }
                current = character
                numbers = []
            } else if character == "," || character == " " {
                flushNumber()
            } else {
                token.append(character)
            }
        }
        flushNumber()
        if let current { commands.append((current, numbers)) }

        var points: [CGPoint] = []
        var pen = CGPoint.zero
        for (command, values) in commands {
            switch command {
            case "M", "L":
                pen = CGPoint(x: values[0], y: values[1])
                if points.last != pen { points.append(pen) }
            case "C":
                for start in stride(from: 0, to: values.count - 5, by: 6) {
                    let c1 = CGPoint(x: values[start], y: values[start + 1])
                    let c2 = CGPoint(x: values[start + 2], y: values[start + 3])
                    let end = CGPoint(x: values[start + 4], y: values[start + 5])
                    for step in 1...16 {
                        let t = CGFloat(step) / 16
                        let u = 1 - t
                        points.append(CGPoint(
                            x: u * u * u * pen.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * end.x,
                            y: u * u * u * pen.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * end.y
                        ))
                    }
                    pen = end
                }
            default:
                break
            }
        }
        if let first = points.first, let last = points.last, hypot(first.x - last.x, first.y - last.y) < 0.01 {
            points.removeLast()
        }
        return points
    }
}

/// One of the logo's strokes, fitted to the frame like the whole mark.
struct OvylStroke: Shape {
    let index: Int

    func path(in rect: CGRect) -> Path {
        OvylLogo.strokes[index].applying(OvylLogo.fit(in: rect))
    }
}

/// The mark, still: ink strokes in the foreground style, and the small one
/// in `accent` when given, as on the app icon.
struct OvylMark: View {
    var accent: Color?

    var body: some View {
        ZStack {
            OvylStroke(index: 0)
            OvylStroke(index: 1)
            if let accent {
                OvylStroke(index: 2).fill(accent)
            } else {
                OvylStroke(index: 2)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Ovyl")
    }
}
