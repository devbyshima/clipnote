import AppKit
import SwiftUI

// Ovyl's look: light grays with white controls, a dotted canvas behind media,
// blue for what's active, and the system font. Each color has a dark variant.

extension NSColor {
    /// A color with a light and a dark value, each as sRGB 0–255 and alpha.
    private static func dynamic(
        _ light: (CGFloat, CGFloat, CGFloat, CGFloat),
        _ dark: (CGFloat, CGFloat, CGFloat, CGFloat)
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: c.3)
        }
    }

    /// The left sidebar.
    static var ovylSidebar: NSColor { dynamic((236, 236, 236, 1), (32, 32, 33, 1)) }
    /// The middle pane and the window behind everything.
    static var ovylBG: NSColor { dynamic((245, 245, 245, 1), (24, 24, 25, 1)) }
    /// The dotted canvas media sits on, and the inspector.
    static var ovylCanvas: NSColor { dynamic((248, 248, 248, 1), (20, 20, 21, 1)) }
    /// White controls: toolbar pills, the floating bars.
    static var ovylSurface: NSColor { dynamic((255, 255, 255, 1), (46, 46, 48, 1)) }
    static var ovylSecondary: NSColor { dynamic((134, 134, 139, 1), (152, 152, 157, 1)) }
    /// What's active: the reader button, links, timestamps.
    static var ovylAccent: NSColor { dynamic((47, 123, 246, 1), (70, 145, 255, 1)) }
    /// A selected row in a list.
    static var ovylSelection: NSColor { dynamic((203, 222, 249, 1), (47, 123, 246, 0.32)) }
    /// Selected and hovered rows, count badges, key chips.
    static var ovylFill: NSColor { dynamic((0, 0, 0, 0.065), (255, 255, 255, 0.09)) }
    static var ovylBorder: NSColor { dynamic((0, 0, 0, 0.08), (255, 255, 255, 0.1)) }
    /// Markdown syntax, list markers and other quiet marks.
    static var ovylFaint: NSColor { dynamic((0, 0, 0, 0.3), (255, 255, 255, 0.32)) }
    /// Behind inline code and code blocks.
    static var ovylCodeBG: NSColor { dynamic((0, 0, 0, 0.055), (255, 255, 255, 0.07)) }
    /// Behind ==highlighted== text.
    static var ovylHighlight: NSColor { dynamic((255, 214, 10, 0.4), (255, 214, 10, 0.32)) }
    /// The canvas dots.
    static var ovylDot: NSColor { dynamic((0, 0, 0, 0.12), (255, 255, 255, 0.1)) }
}

extension Color {
    static let ovylSidebar = Color(nsColor: .ovylSidebar)
    static let ovylBG = Color(nsColor: .ovylBG)
    static let ovylCanvas = Color(nsColor: .ovylCanvas)
    static let ovylSurface = Color(nsColor: .ovylSurface)
    static let ovylSecondary = Color(nsColor: .ovylSecondary)
    static let ovylAccent = Color(nsColor: .ovylAccent)
    static let ovylSelection = Color(nsColor: .ovylSelection)
    static let ovylFill = Color(nsColor: .ovylFill)
    static let ovylBorder = Color(nsColor: .ovylBorder)
    static let ovylFaint = Color(nsColor: .ovylFaint)
    static let ovylCodeBG = Color(nsColor: .ovylCodeBG)
    static let ovylHighlight = Color(nsColor: .ovylHighlight)
    static let ovylDot = Color(nsColor: .ovylDot)
}

extension Font {
    /// The system font, or New York when `serif`.
    static func ovyl(_ size: CGFloat, _ weight: Font.Weight = .regular, serif: Bool = false) -> Font {
        .system(size: size, weight: weight, design: serif ? .serif : .default)
    }
}

extension NSFont {
    /// The system font, or New York when `serif`.
    static func ovyl(_ size: CGFloat, weight: NSFont.Weight = .regular, serif: Bool = false) -> NSFont {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        guard serif, let descriptor = font.fontDescriptor.withDesign(.serif) else { return font }
        return NSFont(descriptor: descriptor, size: size) ?? font
    }
}

// MARK: - Controls

/// A white capsule of toolbar buttons.
struct PillGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) { content }
            .padding(.horizontal, 3)
            .frame(height: 30)
            .background(Capsule(style: .continuous).fill(Color.ovylSurface))
            .overlay(Capsule(style: .continuous).strokeBorder(Color.ovylBorder, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.05), radius: 1.5, y: 0.5)
    }
}

/// An icon button for a `PillGroup`. Active, it's filled blue.
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
                .foregroundStyle(isActive ? Color.white : Color.primary.opacity(0.72))
                .frame(width: 30, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isActive ? Color.ovylAccent : (isHovered && isEnabled ? Color.ovylFill : .clear))
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
                .foregroundStyle(Color.primary.opacity(0.72))
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

/// A count in a small gray capsule, beside a title.
struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11.5, weight: .medium).monospacedDigit())
            .foregroundStyle(Color.ovylSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(Color.ovylFill))
    }
}

/// The key that triggers an action, shown beside it.
struct KeyChip: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.ovylSecondary)
            .frame(minWidth: 20, minHeight: 18)
            .padding(.horizontal, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.ovylFill))
    }
}

/// A white capsule that floats over content, near the bottom of a pane.
struct FloatingBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 2) { content }
            .padding(4)
            .background(Capsule(style: .continuous).fill(Color.ovylSurface))
            .overlay(Capsule(style: .continuous).strokeBorder(Color.ovylBorder, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
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
            .foregroundStyle(Color.primary.opacity(0.85))
            .padding(.leading, 12)
            .padding(.trailing, key == nil ? 12 : 6)
            .padding(.vertical, 5)
            .background(Capsule(style: .continuous).fill(isHovered ? Color.ovylFill : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovered = $0 }
    }
}

/// Dots on a light gray canvas, behind media.
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
            context.fill(dots, with: .color(.ovylDot))
        }
        .background(Color.ovylCanvas)
    }
}

/// A quiet message in the middle of an empty pane.
struct EmptyState: View {
    let symbol: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Color.ovylSecondary.opacity(0.7))
                .padding(.bottom, 4)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            if let message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ovylSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A blue capsule button for the main action in an empty or failed pane.
struct FilledButton: View {
    let title: String
    var symbol: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .bold)) }
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.ovylAccent, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }
}

/// A gray capsule button for secondary actions.
struct PlainCapsuleButton: View {
    let title: String
    var symbol: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
                Text(title).font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.ovylFill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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
