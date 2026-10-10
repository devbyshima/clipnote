import AppKit
import SwiftUI

/// Gold & Graphite: graphite surfaces with gold as the one accent, taken from
/// the app icon. Each color follows the system light or dark appearance.
/// Every color in the app comes from here; folders keep the colors people
/// pick for them.
enum Palette {
    /// The AppKit colors behind the SwiftUI ones, for text attributes and
    /// text views; made on each use, as an NSColor can't be shared across
    /// threads.
    enum NS {
        static var background: NSColor { NSColor(light: 0xF6F6F6, dark: 0x060606) }
        static var surface: NSColor { NSColor(light: 0xFFFFFF, dark: 0x121212) }
        static var surfaceSunken: NSColor { NSColor(light: 0xEFEDE7, dark: 0x1E1E1E) }
        static var border: NSColor { NSColor(light: 0xE4E1D8, dark: 0x2A2A2A) }
        static var textPrimary: NSColor { NSColor(light: 0x121212, dark: 0xF6F6F6) }
        static var textSecondary: NSColor { NSColor(light: 0x66625A, dark: 0x9C978C) }
        static var accent: NSColor { NSColor(light: 0xF6C757, dark: 0xF6C757) }
        static var accentPressed: NSColor { NSColor(light: 0xF5B849, dark: 0xF7D885) }
        static var onAccent: NSColor { NSColor(light: 0x121212, dark: 0x060606) }
        static var accentText: NSColor { NSColor(light: 0x9A5517, dark: 0xF6C757) }
        static var accentSoft: NSColor { NSColor(light: 0xFCF4D8, dark: 0x31291A) }
        static var ember: NSColor { NSColor(light: 0xE68225, dark: 0xE68225) }
        static var shimmerLime: NSColor { NSColor(light: 0xE8FBB2, dark: 0xE8FBB2) }
        static var shimmerMint: NSColor { NSColor(light: 0xB7EFE1, dark: 0xB7EFE1) }
        static var shimmerIce: NSColor { NSColor(light: 0xB3F0F6, dark: 0xB3F0F6) }

        // Status colors, apart from gold, each at least 4.5:1 on a surface.
        static var success: NSColor { NSColor(light: 0x1A7F45, dark: 0x4CC38A) }
        static var warning: NSColor { NSColor(light: 0xB9420A, dark: 0xFF8F5A) }
        static var danger: NSColor { NSColor(light: 0xC62828, dark: 0xFF6B6B) }

        // Roles made from the colors above.
        /// Markdown syntax, list markers and other quiet marks.
        static var faint: NSColor { NSColor(light: 0x66625A, dark: 0x9C978C, alpha: (0.6, 0.65)) }
        /// Behind ==highlighted== text: gold, with the text still dark or
        /// light on it.
        static var highlight: NSColor { NSColor(light: 0xF6C757, dark: 0xF6C757, alpha: (0.5, 0.3)) }
    }

    /// Gold and ember as "#RRGGBB", for artwork that shades a color by
    /// mixing it, like the folder in the folder's empty state.
    enum Hex {
        static let accent = "#F6C757"
        static let ember = "#E68225"
    }

    static let background = Color(nsColor: NS.background)
    static let surface = Color(nsColor: NS.surface)
    static let surfaceSunken = Color(nsColor: NS.surfaceSunken)
    static let border = Color(nsColor: NS.border)
    static let textPrimary = Color(nsColor: NS.textPrimary)
    static let textSecondary = Color(nsColor: NS.textSecondary)
    static let accent = Color(nsColor: NS.accent)
    static let accentPressed = Color(nsColor: NS.accentPressed)
    static let onAccent = Color(nsColor: NS.onAccent)
    static let accentText = Color(nsColor: NS.accentText)
    static let accentSoft = Color(nsColor: NS.accentSoft)
    static let ember = Color(nsColor: NS.ember)
    static let shimmerLime = Color(nsColor: NS.shimmerLime)
    static let shimmerMint = Color(nsColor: NS.shimmerMint)
    static let shimmerIce = Color(nsColor: NS.shimmerIce)

    static let success = Color(nsColor: NS.success)
    static let warning = Color(nsColor: NS.warning)
    static let danger = Color(nsColor: NS.danger)

    static let faint = Color(nsColor: NS.faint)
    static let highlight = Color(nsColor: NS.highlight)
    /// A wash of ink over any surface: hovered and selected rows, count
    /// badges, key chips, the gray of a secondary control.
    static let fill = Color(nsColor: NSColor(light: 0x121212, dark: 0xF6F6F6, alpha: (0.06, 0.08)))
    /// Shadows under cards and floating bars, deeper in dark mode.
    static let shadow = Color(nsColor: NSColor(light: 0x121212, dark: 0x000000, alpha: (0.07, 0.5)))
    /// Behind video and pictures, and the dark scrim over them, in both modes.
    static let media = Color(nsColor: NSColor(light: 0x060606, dark: 0x060606))
    /// Text and marks on a color someone picked, such as a folder's: dark
    /// on light colors, light on dark ones, in both modes.
    static let onLight = Color(nsColor: NSColor(light: 0x121212, dark: 0x121212))
    static let onDark = Color(nsColor: NSColor(light: 0xF6F6F6, dark: 0xF6F6F6))

    /// Lime into gold into ember, for progress bars and highlights.
    static let goldGradient = LinearGradient(
        stops: [
            .init(color: shimmerLime, location: 0),
            .init(color: accent, location: 0.35),
            .init(color: ember, location: 1),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Gold ring with an iridescent edge, for the app mark and progress rings.
    static let shimmerRing = AngularGradient(
        stops: [
            .init(color: accent, location: 0),
            .init(color: ember, location: 0.30),
            .init(color: accent, location: 0.50),
            .init(color: shimmerLime, location: 0.64),
            .init(color: shimmerIce, location: 0.76),
            .init(color: shimmerMint, location: 0.84),
            .init(color: accent, location: 0.96),
        ],
        center: .center,
        startAngle: .degrees(120),
        endAngle: .degrees(480)
    )
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

/// The main action: gold, with a dark label, in both modes.
struct GoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.onAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(configuration.isPressed ? Palette.accentPressed : Palette.accent, in: Capsule())
            .contentShape(Capsule())
    }
}

/// A secondary action: outlined, no fill.
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(configuration.isPressed ? Palette.surfaceSunken : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.border))
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == GoldButtonStyle {
    static var gold: GoldButtonStyle { GoldButtonStyle() }
}

extension ButtonStyle where Self == OutlineButtonStyle {
    static var outline: OutlineButtonStyle { OutlineButtonStyle() }
}

// MARK: - Signature pieces

/// Progress as a gold bar, lime into gold into ember, on a sunken track.
struct GoldProgressBar: View {
    let value: Double
    var height: CGFloat = 6

    var body: some View {
        Capsule()
            .fill(Palette.surfaceSunken)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Palette.goldGradient)
                        .frame(width: max(height, proxy.size.width * min(max(value, 0), 1)))
                        .opacity(value > 0 ? 1 : 0)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Progress")
            .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
    }
}
