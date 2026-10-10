import AppKit
import SwiftUI

/// A card or row picked up from Home or a folder. The card lifts off the page
/// and is drawn above the whole window, so it can travel over the sidebar
/// too; its place on the page stays open while the others make way for it.
/// Let go, it settles into its place, or sinks into the folder it's over.
@Observable @MainActor
final class CardDrag {
    struct Held: Equatable {
        let id: UUID
        let isFolder: Bool
    }

    /// What's held, nil when nothing is. It stays set while the card settles.
    private(set) var held: Held?
    /// The card as it looks on the page.
    private(set) var preview: AnyView?
    /// The card's size, and where the pointer took hold of it, from its top left.
    private(set) var size: CGSize = .zero
    private(set) var grab: CGSize = .zero
    /// The pointer, in the window.
    var pointer: CGPoint = .zero
    /// How far the card leans, in degrees, from how fast it moves sideways.
    var tilt: Double = 0
    /// 0 resting on the page, 1 held up.
    var lift: CGFloat = 0
    /// Once let go: where the card goes, in the window, and whether it sinks
    /// into a folder there.
    var landing: CGRect?
    var sinks = false
    /// The folder, on the page or in the sidebar, it would file into.
    var fileTarget: UUID?
    /// Whether a folder card is over the sidebar, to be pinned there.
    var pinsToSidebar = false
    /// The sidebar's folder rows, the sidebar itself, and the place a folder
    /// carried onto it would be pinned, in the window.
    @ObservationIgnored var sidebarFolders: [UUID: CGRect] = [:]
    @ObservationIgnored var sidebarFrame: CGRect = .zero
    @ObservationIgnored var sidebarPinSlot: CGRect = .zero

    /// Whether the card is following the pointer, not yet let go.
    var isFollowing: Bool { held != nil && landing == nil }

    /// Where the card is drawn, in the window.
    var frame: CGRect {
        landing ?? CGRect(x: pointer.x - grab.width, y: pointer.y - grab.height, width: size.width, height: size.height)
    }

    func pickUp(_ item: Held, frame: CGRect, at point: CGPoint, preview: AnyView) {
        held = item
        self.preview = preview
        size = frame.size
        grab = CGSize(width: point.x - frame.minX, height: point.y - frame.minY)
        pointer = point
        lift = 0
        tilt = 0
        landing = nil
        sinks = false
        fileTarget = nil
        pinsToSidebar = false
    }

    func end() {
        held = nil
        preview = nil
        landing = nil
        sinks = false
        fileTarget = nil
        pinsToSidebar = false
        tilt = 0
        lift = 0
    }
}

/// Draws the held card above everything in the window, held up off the page
/// with a deeper shadow, leaning a little into its motion.
struct CardDragLayer: View {
    @Environment(CardDrag.self) private var drag

    var body: some View {
        GeometryReader { proxy in
            if let preview = drag.preview {
                let origin = proxy.frame(in: .global).origin
                let frame = drag.frame
                let hovering = (drag.fileTarget != nil || drag.pinsToSidebar) && drag.landing == nil
                preview
                    .frame(width: drag.size.width, height: drag.size.height)
                    .shadow(color: Palette.liftShadow.opacity(Double(drag.lift)), radius: 26 * drag.lift, y: 16 * drag.lift)
                    .scaleEffect(drag.sinks ? 0.18 : (1 + 0.035 * drag.lift) * (hovering ? 0.86 : 1))
                    .rotationEffect(.degrees(drag.tilt))
                    .opacity(drag.sinks ? 0 : hovering ? 0.92 : 1)
                    .position(x: frame.midX - origin.x, y: frame.midY - origin.y)
                    .animation(.spring(response: 0.26, dampingFraction: 0.78), value: hovering)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Where each card or row is in the window, and how the page is scrolled.
/// Kept out of SwiftUI's state, so moving and scrolling don't redraw the page.
final class CardFrames {
    var rects: [UUID: CGRect] = [:]
    /// The page's width.
    var width: CGFloat = 0
    /// The scroll view, in the window.
    var viewport: CGRect = .zero
    var offset: CGFloat = 0
    var maxOffset: CGFloat = 0
    /// The last card the held one traded places with. It isn't traded with
    /// again until the pointer has moved on to another card, so the two
    /// don't swap back and forth.
    var lastSwap: UUID?
    /// A folder a note is held at the edge of, and since when: held there a
    /// moment, the note takes the folder's place instead of filing into it.
    var lingering: (id: UUID, since: Date)?
}

/// A card or row that can be picked up and moved. While held, its place on
/// the page shows as a soft gap.
struct Liftable: ViewModifier {
    let id: UUID
    let isHeld: Bool
    /// Off while the card's name is being edited, so dragging selects text.
    var isEnabled = true
    let radius: CGFloat
    let frames: CardFrames
    let changed: (DragGesture.Value) -> Void
    let ended: (DragGesture.Value) -> Void

    func body(content: Content) -> some View {
        content
            .opacity(isHeld ? 0 : 1)
            .overlay {
                if isHeld {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Palette.fill)
                        .transition(.opacity)
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.rects[id] = $0 }
            // A row scrolled out of a lazy list isn't anywhere.
            .onDisappear { frames.rects[id] = nil }
            .gesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .global)
                    .onChanged(changed)
                    .onEnded(ended),
                isEnabled: isEnabled
            )
    }
}
