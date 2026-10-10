import SwiftUI

/// The color flower: a dark disc ringed in a glow of its own colors, holding
/// twelve rich earth tones (sun-baked reds and oranges, mustard, the app's
/// green, teals, denim, plum, brown and the app's graphite) around six light
/// ones and an off-white center. The petal under
/// the pointer, and only that one, swells with a white rim and throws its
/// color out past the ring; moving on, it settles back as the next one
/// swells. The flower rises out of the button that opens it as a dot, swells
/// past its size and settles while the petals unfold from the middle;
/// closing, it folds back down into the button.
struct FlowerPicker: View, Animatable {
    /// 0 folded into the button, 1 open; a spring takes it a little past 1.
    var progress: Double
    /// How far below the flower's center the button is, to grow from and
    /// fold back into.
    let origin: CGFloat
    var onPick: (String) -> Void

    /// The petal under the pointer.
    @State private var hovered: Int?

    /// `hovered` starts with the pointer over that petal, for previews and tests.
    init(progress: Double, origin: CGFloat, hovered: Int? = nil, onPick: @escaping (String) -> Void) {
        self.progress = progress
        self.origin = origin
        self.onPick = onPick
        _hovered = State(initialValue: hovered)
    }

    /// The pointer at a point in the flower's square, for previews and tests.
    init(progress: Double, origin: CGFloat, pointer: CGPoint?, onPick: @escaping (String) -> Void) {
        self.init(progress: progress, origin: origin, onPick: onPick)
        _hovered = State(initialValue: pointer.flatMap { Self.petal(at: $0, hovered: nil, bloom: 1)?.id })
    }

    typealias Petal = (id: Int, hex: String, offset: CGSize, size: CGFloat)

    /// The petal on top under a point, as drawn: the swollen one while the
    /// point is still inside it, else the last drawn there (the center over
    /// the pastels, the pastels over the outer ring).
    static func petal(at point: CGPoint, hovered: Int?, bloom: CGFloat) -> Petal? {
        func contains(_ petal: Petal, grown: Bool) -> Bool {
            let center = CGPoint(x: size / 2 + petal.offset.width * bloom, y: size / 2 + petal.offset.height * bloom)
            let radius = petal.size / 2 * (grown ? grow(petal.id) : 1)
            return hypot(point.x - center.x, point.y - center.y) <= radius
        }
        if let hovered, let petal = petals.first(where: { $0.id == hovered }), contains(petal, grown: true) {
            return petal
        }
        return petals.last { contains($0, grown: false) }
    }

    /// How big a petal grows under the pointer.
    private static func grow(_ id: Int) -> CGFloat { id == 18 ? 1.72 : 1.52 }

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    /// How it opens and closes.
    static let opening = Animation.spring(response: 0.42, dampingFraction: 0.66)
    static let closing = Animation.easeIn(duration: 0.2)

    private var isOpen: Bool { progress > 0.5 }

    /// The disc's size, from a dot to full and a touch beyond.
    private var scale: CGFloat { 0.05 + 0.95 * CGFloat(progress) }

    /// The petals stay folded while the disc is small, then open out.
    private var bloom: CGFloat {
        let p = (progress - 0.2) / 0.8
        return 0.12 + 0.88 * CGFloat(max(0, p))
    }

    static let size: CGFloat = 140

    /// Clockwise from the top: brick, terracotta, burnt orange, mustard, the
    /// app's green, fern, teal, deep turquoise, denim, plum, walnut and the
    /// app's graphite.
    static let outer = [
        "#A63D2F", "#E2725B", "#E8833A", "#D4A017", Palette.Hex.accent, "#5E9E4F",
        "#2A9D8F", "#1F6F78", "#3D5A80", "#8E4162", "#7A4E2D", "#212121",
    ]
    /// Clockwise from the top: saffron, apricot, sand, lime, seafoam, dusty rose.
    static let inner = ["#F2C14E", "#F4A988", "#E8C9A0", "#C9DE8A", "#9DD3C8", "#D9A5B3"]
    /// The app's off-white page.
    static let center = "#F1F2EC"

    private static let outerRadius: CGFloat = 47
    private static let innerRadius: CGFloat = 25
    private static let petal: CGFloat = 30
    private static let middle: CGFloat = 31

    /// Petals as (index, hex, offset from the center, diameter); outer
    /// first, so the inner ring and the center sit on top.
    private static let petals: [(id: Int, hex: String, offset: CGSize, size: CGFloat)] = {
        var list: [(Int, String, CGSize, CGFloat)] = []
        for (index, hex) in outer.enumerated() {
            list.append((index, hex, offset(angle: Double(index) * 30, radius: outerRadius), petal))
        }
        for (index, hex) in inner.enumerated() {
            list.append((12 + index, hex, offset(angle: Double(index) * 60, radius: innerRadius), petal))
        }
        list.append((18, center, .zero, middle))
        return list
    }()

    private static func offset(angle: Double, radius: CGFloat) -> CGSize {
        let radians = angle * .pi / 180
        return CGSize(width: radius * CGFloat(sin(radians)), height: -radius * CGFloat(cos(radians)))
    }

    /// The outer petals' colors round the wheel, from the top.
    private static let ring = AngularGradient(
        stops: (outer + [outer[0]]).enumerated().map { index, hex in
            .init(color: Color(hex: hex), location: Double(index) / Double(outer.count))
        },
        center: .center,
        startAngle: .degrees(-90),
        endAngle: .degrees(270)
    )

    var body: some View {
        let size = Self.size
        ZStack {
            // The ring's glow, wide and soft under a tighter one, and the
            // hovered petal's color thrown past it.
            Circle()
                .stroke(Self.ring, lineWidth: 10)
                .frame(width: size, height: size)
                .blur(radius: 16)
                .opacity(0.55)
            Circle()
                .stroke(Self.ring, lineWidth: 5)
                .frame(width: size - 2, height: size - 2)
                .blur(radius: 5)
                .opacity(0.9)
            if let hovered, let petal = Self.petals.first(where: { $0.id == hovered }) {
                let reach: CGFloat = hovered < 12 ? 1.32 : hovered < 18 ? 1.6 : 0
                Circle()
                    .fill(Color(hex: petal.hex))
                    .frame(width: 70, height: 70)
                    .offset(x: petal.offset.width * reach, y: petal.offset.height * reach)
                    .blur(radius: 20)
                    .opacity(hovered < 18 ? 0.95 : 0.45)
                    .transition(.opacity)
            }

            Circle().fill(Palette.darkPanelWell)
                .frame(width: size, height: size)

            // The petals again, dim and soft, as the light they cast inside.
            petals(interactive: false)
                .blur(radius: 9)
                .opacity(0.32)
                .frame(width: size, height: size)
                .clipShape(Circle())

            petals(interactive: true)

            Circle()
                .stroke(Self.ring, lineWidth: 1.7)
                .frame(width: size - 3, height: size - 3)
                .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        // One tracking area for the whole flower: the petals overlap, so
        // which one is under the pointer is worked out here, top one first.
        .contentShape(Circle())
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location):
                let next = Self.petal(at: location, hovered: hovered, bloom: bloom)?.id
                if next != hovered { hovered = next }
            case .ended:
                hovered = nil
            }
        }
        .onTapGesture(coordinateSpace: .local) { location in
            if let petal = Self.petal(at: location, hovered: hovered, bloom: bloom) { onPick(petal.hex) }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: hovered)
        .scaleEffect(scale)
        .offset(y: origin * (1 - min(1, CGFloat(progress))))
        .opacity(min(1, progress * 5))
        .allowsHitTesting(isOpen)
    }

    private func petals(interactive: Bool) -> some View {
        ZStack {
            ForEach(Self.petals, id: \.id) { petal in
                let isHovered = interactive && hovered == petal.id
                Circle()
                    .fill(Color(hex: petal.hex))
                    .overlay(Circle().strokeBorder(.white.opacity(isHovered ? 1 : 0), lineWidth: 2))
                    .frame(width: petal.size, height: petal.size)
                    // A soft dark edge where petals overlap, deeper as one lifts.
                    .shadow(color: .black.opacity(isHovered ? 0.45 : 0.28), radius: isHovered ? 7 : 2, y: isHovered ? 3 : 0.5)
                    .scaleEffect(isHovered ? Self.grow(petal.id) : 1)
                    .offset(x: petal.offset.width * bloom, y: petal.offset.height * bloom)
                    .zIndex(isHovered ? 1 : 0)
            }
        }
        .blur(radius: 5 * max(0, 1 - bloom))
        .allowsHitTesting(false)
    }
}

/// A dark pill of three buttons for a folder: rename, color and delete.
/// The color button opens the flower above itself.
struct FolderActionsBar: View {
    let pickerOpen: Bool
    var isPinned = false
    var rename: () -> Void
    var color: () -> Void
    var pin: () -> Void = {}
    var delete: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            BarIcon(symbol: "pencil", help: "Rename", action: rename)
            BarIcon(symbol: "drop", help: "Color", dimmed: pickerOpen, action: color)
            BarIcon(symbol: isPinned ? "pin.slash" : "pin", help: isPinned ? "Unpin from Sidebar" : "Pin to Sidebar", action: pin)
            BarIcon(symbol: "trash", help: "Delete Folder", action: delete)
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(Palette.darkPanel))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.1), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        .environment(\.colorScheme, .dark)
    }

    /// The width the pill takes, and where its color button sits from its
    /// center: second of four.
    static let width: CGFloat = 4 * 48 + 3 * 2 + 10
    static let colorOffset: CGFloat = -25
    static let height: CGFloat = 46
}

/// A thin icon in the pill; brighter, on a soft tile, under the pointer.
private struct BarIcon: View {
    let symbol: String
    let help: String
    var dimmed = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(Color.white.opacity(dimmed ? 0.32 : isHovered ? 0.95 : 0.62))
                .frame(width: 48, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(isHovered && !dimmed ? 0.08 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help(help)
    }
}
