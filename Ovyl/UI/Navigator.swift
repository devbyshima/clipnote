import Foundation
import Observation

/// Where the window is: a list of notes, a note, or a note's media pushed
/// into the middle.
enum Route: Hashable {
    case home
    case folder(UUID)
    case note(UUID)
    /// The frames grabbed from a note's video, or its pictures, in a grid.
    case gallery(UUID)
    /// A note's media in the middle: its video (or first picture) when `item`
    /// is nil, otherwise that frame or picture.
    case media(UUID, item: Int?)

    /// The note this route shows, if any.
    var noteID: UUID? {
        switch self {
        case .note(let id), .gallery(let id), .media(let id, _): id
        case .home, .folder: nil
        }
    }

    var isList: Bool {
        switch self {
        case .home, .folder: true
        default: false
        }
    }
}

/// The window's route with back and forward history, like a browser.
@MainActor @Observable
final class Navigator {
    private(set) var route: Route
    private(set) var back: [Route] = []
    private(set) var forward: [Route] = []
    /// The list a note was opened from, for the sidebar highlight.
    private(set) var listRoute: Route = .home
    /// The note waiting for the user to confirm its deletion.
    var pendingDelete: UUID?
    /// Beside a note, the right pane shows the note's info instead of its media.
    var showsNoteInfo = false
    /// The note's info was opened over its media, so leaving it goes back to
    /// the media; opened into a hidden pane, leaving it closes the pane.
    var noteInfoReturnsToMedia = false

    init(_ route: Route = .home, history: [Route] = [], showsNoteInfo: Bool = false) {
        self.route = route
        back = history
        self.showsNoteInfo = showsNoteInfo
        noteInfoReturnsToMedia = showsNoteInfo
        if route.isList { listRoute = route }
    }

    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }

    /// Where going back leads.
    var previous: Route? { back.last }

    /// Goes to `next` as a step back when it's where the window just came
    /// from, so returning doesn't pile up history.
    func goBack(to next: Route) {
        if back.last == next { goBack() } else { go(next) }
    }

    func go(_ next: Route) {
        guard next != route else { return }
        back.append(route)
        forward.removeAll()
        set(next)
    }

    func goBack() {
        guard let previous = back.popLast() else { return }
        forward.append(route)
        set(previous)
    }

    func goForward() {
        guard let next = forward.popLast() else { return }
        back.append(route)
        set(next)
    }

    /// Drops routes to notes and folders that no longer exist.
    func prune(notes: Set<UUID>, folders: Set<UUID>) {
        func valid(_ route: Route) -> Bool {
            if let id = route.noteID { return notes.contains(id) }
            if case .folder(let id) = route { return folders.contains(id) }
            return true
        }
        back = back.filter(valid)
        forward = forward.filter(valid)
        if !valid(listRoute) { listRoute = .home }
        if !valid(route) { set(listRoute) }
    }

    private func set(_ next: Route) {
        route = next
        if next.isList { listRoute = next }
    }
}
