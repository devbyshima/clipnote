import AppKit
import SwiftUI

/// Beam's palette: a pale sage page (dark graphite in dark mode), near-white
/// cards, black and white text, and Beam green as the one accent. Pure black
/// is kept for the pages that show a video or recording. Each color follows the system light or dark
/// appearance. Every color in the app comes from here; folders keep the
/// colors people pick for them.
enum Palette {
    /// The AppKit colors behind the SwiftUI ones, for text attributes and
    /// text views; made on each use, as an NSColor can't be shared across
    /// threads.
    enum NS {
        static var background: NSColor { NSColor(light: 0xF1F2EC, dark: 0x161616) }
        static var surface: NSColor { NSColor(light: 0xFBFCF8, dark: 0x212121) }
        /// Behind a note's video or recording: the page, pure black in dark mode.
        static var mediaPage: NSColor { NSColor(light: 0xF1F2EC, dark: 0x000000) }
        /// Text wells, code and progress tracks: a wash of ink, as Beam's
        /// fields and chips are.
        static var surfaceSunken: NSColor { NSColor(light: 0x000101, dark: 0xFEFFFF, alpha: (0.06, 0.06)) }
        static var border: NSColor { NSColor(light: 0x000101, dark: 0xFEFFFF, alpha: (0.08, 0.08)) }
        static var textPrimary: NSColor { NSColor(light: 0x000101, dark: 0xFEFFFF) }
        static var textSecondary: NSColor { NSColor(light: 0x747571, dark: 0xAAACA7) }
        static var accent: NSColor { NSColor(light: 0xB0C246, dark: 0xB0C246) }
        static var accentPressed: NSColor { NSColor(light: 0xB0C246, dark: 0xB0C246, alpha: (0.9, 0.9)) }
        static var onAccent: NSColor { NSColor(light: 0x000000, dark: 0x000000) }
        static var accentText: NSColor { NSColor(light: 0xB0C246, dark: 0xB0C246) }
        /// Behind what's selected, as Beam's selected rows and chips.
        static var accentSoft: NSColor { NSColor(light: 0xB0C246, dark: 0xB0C246, alpha: (0.16, 0.16)) }
        /// Beam green in shadow, for artwork that shades the accent, like the
        /// folder in the folder's empty state.
        static var accentDeep: NSColor { NSColor(light: 0x7E8C2A, dark: 0x7E8C2A) }

        // Status colors, as Beam's: green for done, the system's orange and red.
        static var success: NSColor { NSColor(light: 0xB0C246, dark: 0xB0C246) }
        static var warning: NSColor { .systemOrange }
        static var danger: NSColor { .systemRed }

        // Roles made from the colors above.
        /// Markdown syntax, list markers and other quiet marks.
        static var faint: NSColor { NSColor(light: 0x747571, dark: 0xAAACA7, alpha: (0.6, 0.65)) }
        /// Behind ==highlighted== text: green, with the text still dark or
        /// light on it.
        static var highlight: NSColor { NSColor(light: 0xB0C246, dark: 0xB0C246, alpha: (0.45, 0.35)) }
    }

    /// The accent and its shade as "#RRGGBB", for artwork that shades a
    /// color by mixing it, like the folder in the folder's empty state.
    enum Hex {
        static let accent = "#B0C246"
        static let accentDeep = "#7E8C2A"
    }

    static let background = Color(nsColor: NS.background)
    static let surface = Color(nsColor: NS.surface)
    static let mediaPage = Color(nsColor: NS.mediaPage)
    static let surfaceSunken = Color(nsColor: NS.surfaceSunken)
    static let border = Color(nsColor: NS.border)
    static let textPrimary = Color(nsColor: NS.textPrimary)
    static let textSecondary = Color(nsColor: NS.textSecondary)
    static let accent = Color(nsColor: NS.accent)
    static let accentPressed = Color(nsColor: NS.accentPressed)
    static let onAccent = Color(nsColor: NS.onAccent)
    static let accentText = Color(nsColor: NS.accentText)
    static let accentSoft = Color(nsColor: NS.accentSoft)
    static let accentDeep = Color(nsColor: NS.accentDeep)

    static let success = Color(nsColor: NS.success)
    static let warning = Color(nsColor: NS.warning)
    static let danger = Color(nsColor: NS.danger)

    static let faint = Color(nsColor: NS.faint)
    static let highlight = Color(nsColor: NS.highlight)
    /// A wash of ink over any surface: selected rows, count badges, key
    /// chips, the gray of a secondary control.
    static let fill = Color(nsColor: NSColor(light: 0x000101, dark: 0xFEFFFF, alpha: (0.06, 0.06)))
    /// Under the pointer, a step fainter than `fill`.
    static let hover = Color(nsColor: NSColor(light: 0x000101, dark: 0xFEFFFF, alpha: (0.05, 0.05)))
    /// The edge of what has keyboard focus or is a drop target.
    static let accentEdge = Color(nsColor: NSColor(light: 0xB0C246, dark: 0xB0C246, alpha: (0.55, 0.55)))
    /// Shadows under cards and floating bars, deeper in dark mode.
    static let shadow = Color(nsColor: NSColor(light: 0x000101, dark: 0x000000, alpha: (0.07, 0.5)))
    /// The shadow under a card that's picked up and carried.
    static let liftShadow = Color(nsColor: NSColor(light: 0x000101, dark: 0x000000, alpha: (0.2, 0.6)))
    /// Behind video and pictures, and the dark scrim over them, in both modes.
    static let media = Color(nsColor: NSColor(light: 0x000000, dark: 0x000000))
    /// Text and marks on a color someone picked, such as a folder's: dark
    /// on light colors, light on dark ones, in both modes.
    static let onLight = Color(nsColor: NSColor(light: 0x000101, dark: 0x000101))
    static let onDark = Color(nsColor: NSColor(light: 0xFEFFFF, dark: 0xFEFFFF))
    /// The always-dark panels that float over the page, like the folder
    /// actions and the color flower.
    static let darkPanel = Color(nsColor: NSColor(light: 0x1A1A1A, dark: 0x1A1A1A))
    static let darkPanelWell = Color(nsColor: NSColor(light: 0x000000, dark: 0x000000))
}

extension NSColor {
    /// A color with a light and a dark value, each as 0xRRGGBB, with an
    /// opacity for each.
    convenience init(light: UInt32, dark: UInt32, alpha: (CGFloat, CGFloat) = (1, 1)) {
        self.init(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: isDark ? alpha.1 : alpha.0
            )
        }
    }
}

// MARK: - Button styles

/// The main action, as Beam's: a capsule (or `shape`) filled with Beam green
/// as a soft gradient, a black label, and a glow in the button's own color.
/// It dims and gives a little when pressed, and grays out when disabled.
struct ProminentButtonStyle<S: Shape>: ButtonStyle {
    var tint: Color = Palette.accent
    var foreground: Color = Palette.onAccent
    var shape: S

    func makeBody(configuration: Configuration) -> some View {
        ProminentBody(configuration: configuration, tint: tint, foreground: foreground, shape: shape)
    }

    private struct ProminentBody: View {
        let configuration: Configuration
        let tint: Color
        let foreground: Color
        let shape: S
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(isEnabled ? AnyShapeStyle(foreground) : AnyShapeStyle(Palette.textSecondary))
                .background((isEnabled ? tint : Color.gray.opacity(0.35)).gradient, in: shape)
                .shadow(color: isEnabled ? tint.opacity(0.35) : .clear, radius: 7, y: 3)
                .contentShape(shape)
                .opacity(configuration.isPressed ? 0.9 : 1)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.snappy(duration: 0.16), value: configuration.isPressed)
        }
    }
}

/// A secondary action, as Beam's: a capsule washed with ink, with a hairline
/// edge, that dims when pressed.
struct PlainCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule(style: .continuous).fill(Palette.textPrimary.opacity(0.06)))
            .overlay(Capsule(style: .continuous).strokeBorder(Palette.textPrimary.opacity(0.10), lineWidth: 0.5))
            .contentShape(Capsule(style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == ProminentButtonStyle<Capsule> {
    static var prominent: ProminentButtonStyle<Capsule> { ProminentButtonStyle(shape: Capsule()) }
}

extension ButtonStyle where Self == ProminentButtonStyle<Circle> {
    static var prominentCircle: ProminentButtonStyle<Circle> { ProminentButtonStyle(shape: Circle()) }
}

extension ButtonStyle where Self == PlainCapsuleButtonStyle {
    static var plainCapsule: PlainCapsuleButtonStyle { PlainCapsuleButtonStyle() }
}

// MARK: - Signature pieces

/// Progress as a Beam green bar on a sunken track.
struct AccentProgressBar: View {
    let value: Double
    var height: CGFloat = 6

    var body: some View {
        Capsule()
            .fill(Palette.surfaceSunken)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Palette.accent)
                        .frame(width: max(height, proxy.size.width * min(max(value, 0), 1)))
                        .opacity(value > 0 ? 1 : 0)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Progress")
            .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
    }
}
