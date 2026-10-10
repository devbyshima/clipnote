import AppKit
import SwiftData
import SwiftUI

/// The window: the sidebar on the left, a list of notes or the open note in
/// the middle, and the note's media on the right. The media's frames or info
/// moves the media into the middle, with its details on the right. Both side
/// panes collapse (⌘. and ⌘P) and the right one resizes by its edge.
struct ContentView: View {
    @Environment(ProcessingCenter.self) private var center
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Folder.createdAt) private var folders: [Folder]
    @State private var navigator: Navigator
    @State private var media = NoteMedia()
    @State private var isDropTargeted = false
    @State private var keyMonitor: Any?
    @AppStorage("showSidebar") private var showSidebar = true
    @AppStorage("showMedia") private var showRightPane = true
    @AppStorage("showAssistant") private var showAssistant = false
    @AppStorage("mediaPaneWidth") private var mediaPaneWidth = 0.0
    @AppStorage("inspectorWidth") private var inspectorWidth = 0.0
    @AppStorage("assistantWidth") private var assistantWidth = 0.0

    // Resizing the right pane: the width when the drag began, the live width
    // while dragging (so settings aren't written every frame), and the cursor.
    @State private var paneDragStart: Double?
    @State private var paneDragLive: Double?
    @State private var paneCursorPushed = false
    @State private var paneHandleHover = false

    private let startsEditing: Bool
    private let spring = Animation.spring(response: 0.3, dampingFraction: 0.86)

    init(route: Route = .home, history: [Route] = [], startsEditing: Bool = false, showsNoteInfo: Bool = false) {
        _navigator = State(initialValue: Navigator(route, history: history, showsNoteInfo: showsNoteInfo))
        self.startsEditing = startsEditing
    }

    init(initialSelection: UUID?) {
        self.init(route: initialSelection.map(Route.note) ?? .home)
    }

    private var route: Route { navigator.route }

    private var currentNote: Note? {
        route.noteID.flatMap { id in notes.first { $0.id == id } }
    }

    /// The right pane shows the media beside a note (or the note's info), and
    /// the media's details once the media is in the middle.
    private var rightPaneIsInspector: Bool {
        switch route {
        case .gallery, .media: true
        case .note: navigator.showsNoteInfo
        default: false
        }
    }

    /// The assistant shows on any page; the media and info need a note.
    private var rightVisible: Bool { showAssistant || (showRightPane && currentNote != nil) }

    private enum PaneKind { case media, inspector, assistant }

    private var paneKind: PaneKind {
        if showAssistant { return .assistant }
        return rightPaneIsInspector ? .inspector : .media
    }

    /// Where new notes go: the folder being looked at, if any.
    private var importFolderID: UUID? {
        if case .folder(let id) = route { return id }
        return nil
    }

    var body: some View {
        @Bindable var center = center

        ZStack {
            Palette.background.ignoresSafeArea()

            GeometryReader { geo in
                HStack(spacing: 0) {
                    if showSidebar {
                        SidebarView(notes: notes, folders: folders, onNew: newNote)
                            // A plain slide: fading the pane every frame is what makes it feel slow.
                            .transition(.move(edge: .leading))
                    }

                    middle
                        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)

                    if rightVisible {
                        // The handle and pane slide out together.
                        HStack(spacing: 0) {
                            paneResizeHandle(total: geo.size.width)
                            rightPane
                                .frame(width: paneWidth(total: geo.size.width))
                        }
                        .transition(.move(edge: .trailing))
                    }
                }
                // Pinned leading, so any overflow spills off the right and the sidebar never moves.
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                .animation(spring, value: showSidebar)
                .animation(spring, value: rightVisible)
                .animation(spring, value: rightPaneIsInspector)
                .animation(spring, value: showAssistant)
            }
            // The panes' headers share the top row with the traffic lights.
            .ignoresSafeArea(.container, edges: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(navigator)
        .background { MainWindowStyler() }
        .background { shortcuts }
        .fileImporter(
            isPresented: $center.isImporterPresented,
            allowedContentTypes: [.audiovisualContent, .audio, .image],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { center.importFiles(urls, into: importFolderID) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            !center.importFiles(urls, into: importFolderID).isEmpty
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.15)) { isDropTargeted = targeted }
        }
        .overlay {
            if isDropTargeted { DropOverlay().transition(.opacity) }
        }
        .alert("Some files were skipped", isPresented: Binding(
            get: { center.importError != nil },
            set: { if !$0 { center.importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(center.importError ?? "")
        }
        .alert(deleteTitle, isPresented: Binding(
            get: { navigator.pendingDelete != nil },
            set: { if !$0 { navigator.pendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) { deletePending() }
            Button("Cancel", role: .cancel) { navigator.pendingDelete = nil }
        } message: {
            Text("The note and its frames are removed from Ovyl. The original video, audio or pictures stay where they are.")
        }
        .onChange(of: center.lastImportedID) { _, id in
            if let id { navigator.go(.note(id)) }
        }
        .onChange(of: route.noteID) { media.show(currentNote) }
        .onChange(of: showRightPane) { _, shows in
            if !shows, case .note = route { media.player.pause() }
        }
        .onChange(of: showAssistant) { _, shows in
            // The assistant covers the player, so the video stops.
            if shows, case .note = route { media.player.pause() }
        }
        .onChange(of: notes.map(\.id)) { prune() }
        .onChange(of: folders.map(\.id)) { prune() }
        .onAppear {
            media.show(currentNote)
            installKeyMonitor()
            AssistantSession.shared.openNote = { [navigator] id in navigator.go(.note(id)) }
        }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
    }

    // MARK: Panes

    @ViewBuilder
    private var middle: some View {
        switch route {
        case .home:
            home
        case .folder(let id):
            if let folder = folders.first(where: { $0.id == id }) {
                NotesListView(title: folder.name, folder: folder, notes: notes.filter { $0.folderID == id }, folders: folders, onNew: newNote)
                    .id(id)
            } else {
                home
            }
        case .note:
            if let note = currentNote {
                NotePageView(note: note, folders: folders, startsEditing: startsEditing) { handleLink($0, from: note) }
                    .id(note.id)
            } else {
                home
            }
        case .gallery:
            if let note = currentNote {
                GalleryView(note: note, media: media)
            } else {
                home
            }
        case .media(_, let item):
            if let note = currentNote {
                MediaViewer(note: note, item: item, media: media)
            } else {
                home
            }
        }
    }

    private var home: some View {
        NotesListView(title: "Home", notes: notes, folders: folders, onNew: newNote)
    }

    @ViewBuilder
    private var rightPane: some View {
        if showAssistant {
            AssistantView(currentNote: currentNote, folders: folders) { showAssistant = false }
        } else if let note = currentNote {
            notePane(note)
        }
    }

    @ViewBuilder
    private func notePane(_ note: Note) -> some View {
        switch route {
        case .media(_, let item):
            InspectorView(note: note, item: item, media: media, folders: folders)
        case .gallery:
            InspectorView(note: note, item: nil, media: media, folders: folders)
        default:
            if navigator.showsNoteInfo {
                NoteInfoView(note: note, folders: folders)
            } else {
                MediaPane(note: note, media: media)
            }
        }
    }

    // MARK: Actions

    private func newNote() {
        center.isImporterPresented = true
    }

    private var deleteTitle: String {
        let note = navigator.pendingDelete.flatMap { id in notes.first { $0.id == id } }
        return "Delete “\(note?.displayTitle ?? "this note")”?"
    }

    private func deletePending() {
        if let id = navigator.pendingDelete, let note = notes.first(where: { $0.id == id }) {
            center.delete(note)
        }
        navigator.pendingDelete = nil
    }

    private func prune() {
        navigator.prune(notes: Set(notes.map(\.id)), folders: Set(folders.map(\.id)))
    }

    /// Timestamps play the video, picture links show the picture, and
    /// [[wikilinks]] open the note with that title.
    private func handleLink(_ url: URL, from note: Note) -> OpenURLAction.Result {
        if let seconds = NoteMarkdown.seconds(in: url) {
            showRightPane = true
            media.play(note, at: seconds)
            return .handled
        }
        if let index = NoteMarkdown.pictureIndex(in: url) {
            let id = note.content?.pictures.indices.contains(index) == true ? note.content?.pictures[index].id : nil
            let position = media.items(for: note).firstIndex { $0.id == id }
            navigator.go(.media(note.id, item: position ?? 0))
            return .handled
        }
        if url.scheme == "ovyl-note" {
            let title = (url.absoluteString.dropFirst("ovyl-note:".count)).removingPercentEncoding ?? ""
            if let target = notes.first(where: { $0.displayTitle.localizedCaseInsensitiveCompare(title) == .orderedSame }) {
                navigator.go(.note(target.id))
            }
            return .handled
        }
        return .systemAction
    }

    // MARK: Keys

    /// ⌘[ and ⌘] go back and forward.
    private var shortcuts: some View {
        ZStack {
            Button { navigator.goBack() } label: { Color.clear.frame(width: 0, height: 0) }
                .keyboardShortcut("[", modifiers: .command)
            Button { navigator.goForward() } label: { Color.clear.frame(width: 0, height: 0) }
                .keyboardShortcut("]", modifiers: .command)
        }
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    /// F, I and D open the frames, open the info, and delete, for the open
    /// note, unless text is being typed.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        let navigator = navigator
        let center = center
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            let plain = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            let handled = MainActor.assumeIsolated { Self.handleKey(key, plain: plain, navigator: navigator, center: center) }
            return handled ? nil : event
        }
    }

    private static func handleKey(_ key: String, plain: Bool, navigator: Navigator, center: ProcessingCenter) -> Bool {
        guard plain,
              !(NSApp.keyWindow?.firstResponder is NSText),
              navigator.pendingDelete == nil,
              case .note(let id) = navigator.route
        else { return false }
        switch key {
        case "f":
            // Recordings and text have no frames to show.
            guard center.note(with: id)?.hasGallery == true else { return false }
            navigator.go(.gallery(id))
        case "i": navigator.go(.media(id, item: nil))
        case "d": navigator.pendingDelete = id
        default: return false
        }
        return true
    }

    // MARK: Right pane sizing

    /// Keeps the middle at least 360 points wide.
    private func clampPane(_ width: CGFloat, total: CGFloat) -> CGFloat {
        let sidebar: CGFloat = showSidebar ? SidebarView.width : 0
        let minPane: CGFloat = switch paneKind {
        case .inspector: 260
        case .media: 300
        case .assistant: 320
        }
        let maxPane = max(minPane, total - sidebar - 12 - 360)
        return min(max(width, minPane), maxPane)
    }

    /// The live drag width, else the remembered width for this pane, else its default.
    private func paneWidth(total: CGFloat) -> CGFloat {
        if let live = paneDragLive { return clampPane(CGFloat(live), total: total) }
        let (saved, fallback): (Double, CGFloat) = switch paneKind {
        case .inspector: (inspectorWidth, 320)
        case .media: (mediaPaneWidth, 420)
        case .assistant: (assistantWidth, 380)
        }
        return clampPane(saved > 0 ? CGFloat(saved) : fallback, total: total)
    }

    /// A hairline with a wide grab strip: drag to resize the pane. It turns
    /// blue while hovered or dragged.
    private func paneResizeHandle(total: CGFloat) -> some View {
        let active = paneHandleHover || paneDragLive != nil
        return ZStack {
            Color.clear.frame(width: 12).contentShape(Rectangle())
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(active ? Palette.accent : Palette.border)
                .frame(width: active ? 3 : 1)
                .frame(maxHeight: .infinity)
                .ignoresSafeArea(edges: .top)
        }
        .frame(maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea(edges: .top))
        .animation(.easeOut(duration: 0.12), value: active)
        .onHover { inside in
            paneHandleHover = inside
            if inside {
                if !paneCursorPushed { NSCursor.resizeLeftRight.push(); paneCursorPushed = true }
            } else if paneCursorPushed, paneDragLive == nil {
                NSCursor.pop()
                paneCursorPushed = false
            }
        }
        .onDisappear {
            if paneCursorPushed { NSCursor.pop(); paneCursorPushed = false }
        }
        .gesture(
            // Global coordinates: the handle moves as the pane widens, which
            // would make a local translation jitter.
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    let start = paneDragStart ?? Double(paneWidth(total: total))
                    if paneDragStart == nil { paneDragStart = start }
                    paneDragLive = Double(clampPane(CGFloat(start) - value.translation.width, total: total))
                }
                .onEnded { _ in
                    if let live = paneDragLive {
                        switch paneKind {
                        case .inspector: inspectorWidth = live
                        case .media: mediaPaneWidth = live
                        case .assistant: assistantWidth = live
                        }
                    }
                    paneDragStart = nil
                    paneDragLive = nil
                    if paneCursorPushed, !paneHandleHover { NSCursor.pop(); paneCursorPushed = false }
                }
        )
    }
}

struct DropOverlay: View {
    var body: some View {
        ZStack {
            Rectangle().fill(Palette.background.opacity(0.85))
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Palette.accentText, style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                .padding(18)
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 34))
                    .foregroundStyle(Palette.accentText)
                Text("Drop to make a note")
                    .font(.system(size: 20, weight: .semibold))
                Text("Videos, audio, or pictures")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .allowsHitTesting(false)
    }
}
