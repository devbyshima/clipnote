import AppKit
import SwiftUI

/// Gives the main window Beam's unified look: a transparent, full-size-content
/// titlebar with the title hidden, so the panes run to the top of the window.
/// The panes' header bars share the top row with the traffic lights, which
/// are centered in it.
struct MainWindowStyler: NSViewRepresentable {
    /// The height of the top row: the pane headers and the traffic lights.
    static let barHeight: CGFloat = 50
    /// Room the traffic lights take at the left of the top row.
    static let trafficLightsWidth: CGFloat = 92
    private static let trafficLightsInset: CGFloat = 18

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = WindowObserver()
        let coordinator = context.coordinator
        view.onWindow = { coordinator.attach(to: $0) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView.window)
    }

    /// Styles the window the moment the view joins it, not on a later update.
    private final class WindowObserver: NSView {
        var onWindow: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }

    /// Keeps the titlebar transparent and its vibrancy hidden. AppKit brings the
    /// titlebar's material back after the window activates or resizes, so it's
    /// hidden again on every window update.
    @MainActor
    final class Coordinator: NSObject {
        private weak var window: NSWindow?

        func attach(to window: NSWindow?) {
            guard let window else { return }
            if window !== self.window {
                self.window = window
                for name in [NSWindow.didUpdateNotification, NSWindow.didResizeNotification, NSWindow.didExitFullScreenNotification] {
                    NotificationCenter.default.addObserver(self, selector: #selector(reapply(_:)), name: name, object: window)
                }
            }
            apply(window)
        }

        @objc private func reapply(_ note: Notification) {
            if let window = note.object as? NSWindow { apply(window) }
        }

        private func apply(_ window: NSWindow) {
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
            window.isOpaque = true
            window.backgroundColor = Palette.NS.background

            placeTrafficLights(window)

            guard let contentView = window.contentView, let frameView = contentView.superview else { return }
            if let titlebar = window.standardWindowButton(.closeButton)?.superview?.superview {
                titlebar.wantsLayer = true
                titlebar.layer?.backgroundColor = .clear
            }
            // Hide the translucent materials outside the content view, which tint
            // the top strip; glass inside the content is left alone.
            var found: [NSVisualEffectView] = []
            collect(frameView, into: &found, skipping: contentView)
            for view in found {
                if !view.isHidden { view.isHidden = true }
                if view.alphaValue != 0 { view.alphaValue = 0 }
            }
        }

        /// Centers the traffic lights in the top row by making the titlebar as
        /// tall as the pane headers. AppKit lays the titlebar out again on
        /// resize, so this runs on every update and only moves what changed.
        private func placeTrafficLights(_ window: NSWindow) {
            guard !window.styleMask.contains(.fullScreen),
                  let close = window.standardWindowButton(.closeButton),
                  let titlebar = close.superview,
                  let container = titlebar.superview
            else { return }
            let height = MainWindowStyler.barHeight
            let containerFrame = NSRect(
                x: container.frame.minX, y: window.frame.height - height,
                width: container.frame.width, height: height
            )
            if container.frame != containerFrame { container.frame = containerFrame }
            if titlebar.frame != container.bounds { titlebar.frame = container.bounds }

            let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap(window.standardWindowButton)
            let spacing = buttons.count > 1 ? buttons[1].frame.minX - buttons[0].frame.minX : 20
            for (index, button) in buttons.enumerated() {
                let origin = NSPoint(
                    x: MainWindowStyler.trafficLightsInset + CGFloat(index) * spacing,
                    y: ((height - button.frame.height) / 2).rounded()
                )
                if button.frame.origin != origin { button.setFrameOrigin(origin) }
            }
        }

        private func collect(_ view: NSView, into result: inout [NSVisualEffectView], skipping: NSView) {
            if view === skipping { return }
            if let effect = view as? NSVisualEffectView { result.append(effect) }
            view.subviews.forEach { collect($0, into: &result, skipping: skipping) }
        }
    }
}

/// A strip that drags the window when grabbed, for the pane headers.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}

/// Keeps keyboard focus off the Settings toolbar. With keyboard navigation
/// on, AppKit hands focus to the first tab whenever a tab's controls leave the
/// window, and the tab then wears a focus ring in the shape of its symbol. The
/// tabs refuse focus, and if one gets it anyway the window takes it back, so
/// Tab moves through the open tab's controls.
struct SettingsWindowStyler: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = WindowObserver()
        let coordinator = context.coordinator
        view.onWindow = { coordinator.attach(to: $0) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView.window)
    }

    private final class WindowObserver: NSView {
        var onWindow: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }

    /// Checks on every window update, since focus moves after the new tab's
    /// controls are in place, and the toolbar's buttons can be made again.
    @MainActor
    final class Coordinator: NSObject {
        private weak var window: NSWindow?

        func attach(to window: NSWindow?) {
            guard let window else { return }
            if window !== self.window {
                self.window = window
                NotificationCenter.default.addObserver(self, selector: #selector(reapply(_:)), name: NSWindow.didUpdateNotification, object: window)
            }
            apply(window)
        }

        @objc private func reapply(_ note: Notification) {
            if let window = note.object as? NSWindow { apply(window) }
        }

        private func apply(_ window: NSWindow) {
            guard let contentView = window.contentView, let frameView = contentView.superview else { return }
            var toolbarViews: [NSView] = []
            collect(frameView, into: &toolbarViews, skipping: contentView, window: window)
            for case let control as NSControl in toolbarViews where !control.refusesFirstResponder {
                control.refusesFirstResponder = true
            }
            if let responder = window.firstResponder as? NSView,
               toolbarViews.contains(where: { responder === $0 || responder.isDescendant(of: $0) }) {
                window.makeFirstResponder(nil)
            }
        }

        /// The views outside the content view that could hold focus, leaving
        /// out the traffic lights.
        private func collect(_ view: NSView, into result: inout [NSView], skipping: NSView, window: NSWindow) {
            if view === skipping { return }
            if view.acceptsFirstResponder || view is NSControl,
               ![NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].contains(where: { window.standardWindowButton($0) === view }) {
                result.append(view)
            }
            view.subviews.forEach { collect($0, into: &result, skipping: skipping, window: window) }
        }
    }
}
