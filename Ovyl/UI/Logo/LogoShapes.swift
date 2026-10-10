import SwiftUI

// The pieces the logo comes apart into. Every piece is an outline of the
// same number of points, so any two can be blended: a stroke of the logo
// can round into a dot, stretch into a bar or lie down as a line of text.

/// A closed outline as a fixed number of points spaced evenly along it,
/// clockwise from its top, around its own middle and standing upright.
struct LogoOutline: Equatable {
    static let count = 120
    var points: [CGPoint]

    /// Respaces a closed run of points around the origin. Starts where a
    /// line straight up from the middle meets it.
    init(polygon: [CGPoint]) {
        var polygon = polygon
        var area: CGFloat = 0
        for index in polygon.indices {
            let a = polygon[index], b = polygon[(index + 1) % polygon.count]
            area += a.x * b.y - b.x * a.y
        }
        // Clockwise on screen, where y runs down.
        if area < 0 { polygon.reverse() }

        // Where the outline crosses straight above the middle.
        var start = 0
        var top = CGPoint(x: 0, y: polygon.map(\.y).min() ?? 0)
        for index in polygon.indices {
            let a = polygon[index], b = polygon[(index + 1) % polygon.count]
            if a.x <= 0, b.x > 0 || (a.x < 0 && b.x >= 0) {
                let t = a.x == b.x ? 0 : -a.x / (b.x - a.x)
                let y = a.y + (b.y - a.y) * t
                if y < 0 {
                    start = (index + 1) % polygon.count
                    top = CGPoint(x: 0, y: y)
                    break
                }
            }
        }
        var ring = [top] + polygon[start...] + polygon[..<start] + [top]
        ring = ring.enumerated().filter { $0.offset == 0 || $0.element != ring[$0.offset - 1] }.map(\.element)

        var lengths: [CGFloat] = [0]
        for index in 1..<ring.count {
            lengths.append(lengths[index - 1] + hypot(ring[index].x - ring[index - 1].x, ring[index].y - ring[index - 1].y))
        }
        let total = lengths.last ?? 1
        var points: [CGPoint] = []
        points.reserveCapacity(Self.count)
        var segment = 1
        for step in 0..<Self.count {
            let distance = total * CGFloat(step) / CGFloat(Self.count)
            while segment < ring.count - 1, lengths[segment] < distance { segment += 1 }
            let span = lengths[segment] - lengths[segment - 1]
            let t = span > 0 ? (distance - lengths[segment - 1]) / span : 0
            let a = ring[segment - 1], b = ring[segment]
            points.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
        self.points = points
    }

    /// A rounded rectangle, `radius` held to what fits.
    static func rect(_ width: CGFloat, _ height: CGFloat, radius: CGFloat) -> LogoOutline {
        let r = min(radius, width / 2, height / 2)
        let w = width / 2 - r, h = height / 2 - r
        var polygon: [CGPoint] = []
        // Corners clockwise from the top right, each as a quarter turn.
        let corners: [(CGPoint, Double)] = [(CGPoint(x: w, y: -h), -90), (CGPoint(x: w, y: h), 0), (CGPoint(x: -w, y: h), 90), (CGPoint(x: -w, y: -h), 180)]
        for (center, from) in corners {
            for step in 0...16 {
                let angle = (from + 90 * Double(step) / 16) * .pi / 180
                polygon.append(CGPoint(x: center.x + r * CGFloat(cos(angle)), y: center.y + r * CGFloat(sin(angle))))
            }
        }
        return LogoOutline(polygon: polygon)
    }

    static func capsule(_ width: CGFloat, _ height: CGFloat) -> LogoOutline {
        rect(width, height, radius: min(width, height) / 2)
    }

    static func circle(_ diameter: CGFloat) -> LogoOutline {
        capsule(diameter, diameter)
    }

    /// A triangle on its base with softened corners.
    static func triangle(_ width: CGFloat, _ height: CGFloat) -> LogoOutline {
        let r = min(width, height) * 0.14
        let tips = [CGPoint(x: 0, y: -height * 0.58), CGPoint(x: width / 2, y: height * 0.42), CGPoint(x: -width / 2, y: height * 0.42)]
        var polygon: [CGPoint] = []
        for index in tips.indices {
            let tip = tips[index], previous = tips[(index + 2) % 3], next = tips[(index + 1) % 3]
            func toward(_ point: CGPoint) -> CGPoint {
                let length = hypot(point.x - tip.x, point.y - tip.y)
                return CGPoint(x: tip.x + (point.x - tip.x) / length * r * 1.6, y: tip.y + (point.y - tip.y) / length * r * 1.6)
            }
            let a = toward(previous), b = toward(next)
            for step in 0...8 {
                let t = CGFloat(step) / 8, u = 1 - t
                polygon.append(CGPoint(x: u * u * a.x + 2 * u * t * tip.x + t * t * b.x, y: u * u * a.y + 2 * u * t * tip.y + t * t * b.y))
            }
        }
        return LogoOutline(polygon: polygon)
    }
}

/// One piece of the mark: an upright outline, turned by `angle` (clockwise,
/// in radians) and set at `center` in the logo's 48-point square. At
/// `scale` 0 it has shrunk to nothing. `stretch` pulls it out along the way
/// it's moving and thins it across, as fast things look; `squash` presses
/// it flat along the way it's being pushed or braked, as a ball does
/// before it jumps and when it lands. Their lengths are how much.
/// `elasticity` is how much it gives that way: none for shapes that grow in
/// place, like a bar from the ground or a line from the margin, which
/// would otherwise stretch past where they stand.
struct LogoPiece: Equatable {
    var outline: LogoOutline
    var center: CGPoint
    var angle: Double = 0
    var scale: CGFloat = 1
    var elasticity: CGFloat = 1
    var stretch = CGVector.zero
    var squash = CGVector.zero

    /// The outline through the midpoints of its points, each point a curve's
    /// control, so the edge stays smooth however the points move.
    var path: Path {
        let size = max(0, scale)
        var transform = CGAffineTransform(translationX: center.x, y: center.y)
        // Both keep the area: what's gained one way is lost across it.
        for (vector, longer) in [(stretch, true), (squash, false)] {
            let amount = hypot(vector.dx, vector.dy)
            guard amount > 0.001 else { continue }
            let direction = atan2(vector.dy, vector.dx)
            let along = longer ? 1 + amount : 1 / (1 + amount)
            transform = transform
                .rotated(by: direction)
                .scaledBy(x: along, y: 1 / along)
                .rotated(by: -direction)
        }
        transform = transform.rotated(by: angle).scaledBy(x: size, y: size)
        let points = outline.points.map { $0.applying(transform) }
        return Path { path in
            guard let last = points.last else { return }
            func middle(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
            path.move(to: middle(last, points[0]))
            for index in points.indices {
                path.addQuadCurve(to: middle(points[index], points[(index + 1) % points.count]), control: points[index])
            }
            path.closeSubpath()
        }
    }

    /// Adds the way from `a` to `b`: the place, turn and size by `motion`,
    /// the outline by `form`, which may lag and overshoot less, so a shape
    /// settles without warping. A `lift` bows the path upward in an arc, as
    /// high as that share of the distance, at its height halfway.
    mutating func move(from a: LogoPiece, to b: LogoPiece, motion: Double, form: Double, lift: CGFloat = 0) {
        let m = CGFloat(motion), f = CGFloat(form)
        let dx = b.center.x - a.center.x, dy = b.center.y - a.center.y
        center.x += dx * m
        center.y += dy * m - lift * hypot(dx, dy) * 4 * m * (1 - m)
        angle += (b.angle - a.angle) * motion
        scale += (b.scale - a.scale) * m
        elasticity += (b.elasticity - a.elasticity) * f
        guard f != 0 else { return }
        for index in outline.points.indices {
            outline.points[index].x += (b.outline.points[index].x - a.outline.points[index].x) * f
            outline.points[index].y += (b.outline.points[index].y - a.outline.points[index].y) * f
        }
    }

    /// Adds `k` times `rate`, a piece's change per second.
    mutating func add(_ rate: LogoPiece, times k: Double) {
        let c = CGFloat(k)
        center.x += rate.center.x * c
        center.y += rate.center.y * c
        angle += rate.angle * k
        scale += rate.scale * c
        elasticity += rate.elasticity * c
        for index in outline.points.indices {
            outline.points[index].x += rate.outline.points[index].x * c
            outline.points[index].y += rate.outline.points[index].y * c
        }
    }

    /// How fast each part of the piece changes, from where it was `interval`
    /// seconds before.
    func rate(since earlier: LogoPiece, over interval: Double) -> LogoPiece {
        let k = CGFloat(1 / interval)
        var rate = self
        rate.center = CGPoint(x: (center.x - earlier.center.x) * k, y: (center.y - earlier.center.y) * k)
        rate.angle = (angle - earlier.angle) / interval
        rate.scale = (scale - earlier.scale) * k
        rate.elasticity = (elasticity - earlier.elasticity) * k
        rate.stretch = .zero
        rate.squash = .zero
        for index in outline.points.indices {
            rate.outline.points[index] = CGPoint(
                x: (outline.points[index].x - earlier.outline.points[index].x) * k,
                y: (outline.points[index].y - earlier.outline.points[index].y) * k
            )
        }
        return rate
    }

    /// The pieces as they stand in the logo, largest first.
    static let logo: [LogoPiece] = OvylLogo.polygons.map(LogoPiece.init(stroke:))

    /// A stroke of the logo, stood upright about its middle.
    init(stroke polygon: [CGPoint]) {
        // The middle and the long axis, from the outline's spread.
        let count = CGFloat(polygon.count)
        let mid = CGPoint(x: polygon.map(\.x).reduce(0, +) / count, y: polygon.map(\.y).reduce(0, +) / count)
        var xx: CGFloat = 0, yy: CGFloat = 0, xy: CGFloat = 0
        for point in polygon {
            let dx = point.x - mid.x, dy = point.y - mid.y
            xx += dx * dx
            yy += dy * dy
            xy += dx * dy
        }
        // The long axis, turned clockwise from straight up.
        let axis = 0.5 * atan2(2 * xy, xx - yy)
        var angle = Double(axis) + .pi / 2
        if angle > .pi / 2 { angle -= .pi }
        let upright = CGAffineTransform(rotationAngle: -angle)
        center = mid
        self.angle = angle
        outline = LogoOutline(polygon: polygon.map { CGPoint(x: $0.x - mid.x, y: $0.y - mid.y).applying(upright) })
    }

    init(outline: LogoOutline, center: CGPoint, angle: Double = 0, scale: CGFloat = 1, elasticity: CGFloat = 1) {
        self.outline = outline
        self.center = center
        self.angle = angle
        self.scale = scale
        self.elasticity = elasticity
    }

    /// How long and wide the piece is, standing upright.
    var extent: CGSize {
        let xs = outline.points.map(\.x), ys = outline.points.map(\.y)
        return CGSize(width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0))
    }
}
