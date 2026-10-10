import AppKit
import SwiftUI

// Ovyl's look: Gold & Graphite (see Palette), a dotted canvas behind media,
// and two typefaces: the system font, and Caveat for handwriting; a note can
// also be read in New York.

extension Font {
    /// The system font, or New York when `serif`, for notes.
    static func ovyl(_ size: CGFloat, _ weight: Font.Weight = .regular, serif: Bool = false) -> Font {
        .system(size: size, weight: weight, design: serif ? .serif : .default)
    }
}

enum OvylFonts {
    /// Registers the bundled Caveat, the handwriting. Call once at launch.
    static func register() {
        guard let url = Bundle.main.url(forResource: "Caveat", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

extension NSFont {
    /// The system font, or New York when `serif`, for notes.
    static func ovyl(_ size: CGFloat, weight: NSFont.Weight = .regular, serif: Bool = false) -> NSFont {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        guard serif, let descriptor = font.fontDescriptor.withDesign(.serif) else { return font }
        return NSFont(descriptor: descriptor, size: size) ?? font
    }

    /// Caveat, the handwriting, at a weight from 400 to 700.
    static func caveat(_ size: CGFloat, wght: CGFloat = 460) -> NSFont {
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: "Caveat",
            .variation: [NSNumber(value: 0x7767_6874): NSNumber(value: Double(wght))],
        ])
        return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size)
    }
}

// MARK: - Controls

/// A capsule of toolbar buttons on a surface.
struct PillGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) { content }
            .padding(.horizontal, 3)
            .frame(height: 30)
            .background(Capsule(style: .continuous).fill(Palette.surface))
            .overlay(Capsule(style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
            .shadow(color: Palette.shadow, radius: 1.5, y: 0.5)
    }
}

/// An icon button for a `PillGroup`. Active, it's filled gold.
struct PillButton: View {
    let symbol: String
    let help: String
    var isActive = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? Palette.onAccent : Palette.textPrimary.opacity(0.72))
                .frame(width: 30, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isActive ? Palette.accent : (isHovered && isEnabled ? Palette.fill : .clear))
                )
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovered = $0 }
        .help(help)
    }
}

/// A menu that looks like a `PillButton`.
struct PillMenu<Items: View>: View {
    var symbol = "ellipsis"
    let help: String
    @ViewBuilder var items: Items

    var body: some View {
        Menu {
            items
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.textPrimary.opacity(0.72))
                .frame(width: 30, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(help)
    }
}

/// The key that triggers an action, shown beside it.
struct KeyChip: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette.textSecondary)
            .frame(minWidth: 20, minHeight: 18)
            .padding(.horizontal, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Palette.fill))
    }
}

/// A capsule on a surface that floats over content, near the bottom of a pane.
struct FloatingBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 2) { content }
            .padding(4)
            .background(Capsule(style: .continuous).fill(Palette.surface))
            .overlay(Capsule(style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
            .shadow(color: Palette.shadow, radius: 12, y: 4)
    }
}

/// An icon, a label and a key, for a `FloatingBar`.
struct BarButton: View {
    let symbol: String
    let title: String
    var key: String?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 12.5, weight: .medium))
                Text(title)
                    .font(.system(size: 13))
                if let key { KeyChip(key: key).padding(.leading, 3) }
            }
            .foregroundStyle(Palette.textPrimary.opacity(0.85))
            .padding(.leading, 12)
            .padding(.trailing, key == nil ? 12 : 6)
            .padding(.vertical, 5)
            .background(Capsule(style: .continuous).fill(isHovered ? Palette.fill : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovered = $0 }
    }
}

/// Dots on the background, behind media.
struct DotGrid: View {
    var spacing: CGFloat = 18

    var body: some View {
        Canvas { context, size in
            var dots = Path()
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    dots.addEllipse(in: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6))
                    x += spacing
                }
                y += spacing
            }
            context.fill(dots, with: .color(Palette.border))
        }
        .background(Palette.background)
    }
}

/// A quiet message in the middle of an empty pane.
struct EmptyState: View {
    var symbol = ""
    /// The logo acting this out, in place of the symbol.
    var motion: LogoMotion?
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 10) {
            if let motion {
                LogoLoader(motion)
                    .frame(width: 56, height: 56)
                    .foregroundStyle(Palette.textPrimary.opacity(0.8))
                    .padding(.bottom, 4)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(Palette.textSecondary.opacity(0.7))
                    .padding(.bottom, 4)
            }
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
            if let message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The gold capsule button for the main action in an empty or failed pane.
struct FilledButton: View {
    let title: String
    var symbol: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .bold)) }
                Text(title)
            }
        }
        .buttonStyle(.gold)
        .focusEffectDisabled()
    }
}

/// An outlined capsule button for secondary actions.
struct PlainCapsuleButton: View {
    let title: String
    var symbol: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
                Text(title)
            }
        }
        .buttonStyle(.outline)
        .focusEffectDisabled()
    }
}

/// Controls at both ends and a title centered between them, kept clear of
/// whichever side is wider.
struct CenteredBar<Leading: View, Title: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var title: Title
    @ViewBuilder var trailing: Trailing
    @State private var leadingWidth: CGFloat = 0
    @State private var trailingWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) { leading }
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { leadingWidth = $0 }
            Spacer(minLength: 8)
            HStack(spacing: 8) { trailing }
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { trailingWidth = $0 }
        }
        .overlay {
            title
                .lineLimit(1)
                .padding(.horizontal, max(leadingWidth, trailingWidth) + 14)
                .allowsHitTesting(false)
        }
    }
}

/// The top row of the middle pane: back and forward, a centered title, and
/// actions. With the sidebar hidden it leaves room for the traffic lights and
/// offers a button to bring the sidebar back.
struct PaneToolbar<Title: View, Trailing: View>: View {
    @Environment(Navigator.self) private var navigator
    @AppStorage("showSidebar") private var showSidebar = true
    @ViewBuilder var title: Title
    @ViewBuilder var trailing: Trailing

    var body: some View {
        CenteredBar {
            if !showSidebar {
                PillGroup {
                    PillButton(symbol: "sidebar.left", help: "Show the sidebar (⌘.)") { showSidebar = true }
                }
            }
            PillGroup {
                PillButton(symbol: "chevron.left", help: "Back (⌘[)") { navigator.goBack() }
                    .disabled(!navigator.canGoBack)
                PillButton(symbol: "chevron.right", help: "Forward (⌘])") { navigator.goForward() }
                    .disabled(!navigator.canGoForward)
            }
        } title: {
            title
        } trailing: {
            trailing
        }
        .padding(.leading, showSidebar ? 12 : MainWindowStyler.trafficLightsWidth)
        .padding(.trailing, 12)
        .frame(height: MainWindowStyler.barHeight)
        .background(WindowDragHandle())
    }
}

// MARK: - Hex colors

/// A color written as "#RRGGBB", taken apart and mixed.
nonisolated struct HexColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(_ hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        let value = UInt32(digits, radix: 16) ?? 0x0A84FF
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// How bright it looks, from 0 to 1.
    var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

    /// Light enough that text on it should be dark.
    var isLight: Bool { luminance > 0.68 }

    /// Mixed toward white by `amount`, or toward black when negative.
    func mixed(_ amount: Double) -> HexColor {
        let target = amount >= 0 ? 1.0 : 0.0
        let t = abs(amount)
        return HexColor(red: red + (target - red) * t, green: green + (target - green) * t, blue: blue + (target - blue) * t)
    }

    /// Mixed toward `other` by `amount`.
    func blended(with other: HexColor, _ amount: Double) -> HexColor {
        HexColor(red: red + (other.red - red) * amount, green: green + (other.green - green) * amount, blue: blue + (other.blue - blue) * amount)
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
}

extension Color {
    init(hex: String) {
        self = HexColor(hex).color
    }
}
