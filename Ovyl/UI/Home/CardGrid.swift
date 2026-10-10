import SwiftUI

/// Home and folders as cards: white note cards and colored folder cards. The
/// view menu picks how they're laid out (a messy grid, where each card drops
/// into the shortest column and a note with text stands twice as tall; an even
/// grid; or a list), how they're sorted, whether folders come first, and
/// whether notes show their text. Cards and rows can be picked up and carried
/// into a new order, which is kept as the manual order for that page; a note
/// carried onto a folder, here or in the sidebar, files into it. A folder's dots bring up its rename, color
/// and delete pill; the color button opens the color flower.
struct CardGrid: View {
    @Environment(ProcessingCenter.self) private var center
    @Environment(Navigator.self) private var navigator
    let folders: [Folder]
    let notes: [Note]
    /// Every note, for counting what's in each folder.
    let allNotes: [Note]
    let allFolders: [Folder]
    /// Whose manual order this is: "home", or a folder's id.
    let scope: String

    @State private var actionsFolder: UUID?
    @State private var order: [UUID]
    /// The card being carried, shared with the window, which draws it.
    @Environment(CardDrag.self) private var windowDrag: CardDrag?
    @State private var ownDrag = CardDrag()
    @State private var frames = CardFrames()
    @State private var scrollPosition = ScrollPosition()
    @State private var autoscroll: Task<Void, Never>?
    @State private var pickerOpen: Bool
    /// How big the cards are, from the slider at the bottom; smallest at first.
    @AppStorage("homeCardScale") private var scale = CardGrid.scales.lowerBound
    @AppStorage(HomeView.layoutKey) private var layout = HomeLayout.messy
    @AppStorage(HomeView.sortKey) private var sort = HomeSort.made
    @AppStorage(HomeView.ascendingKey) private var ascending = false
    @AppStorage(HomeView.foldersFirstKey) private var foldersFirst = false
    @AppStorage(HomeView.showsTextKey) private var showsText = true
    /// The folder whose name is being edited on its card, and the name so far.
    @State private var editingFolder: UUID?
    @State private var editingName = ""
    @State private var deleting: Folder?

    /// `showsActionsFor` and `pickerOpen` start with a folder's pill, and its
    /// flower, already open, for previews and tests.
    init(folders: [Folder], notes: [Note], allNotes: [Note], allFolders: [Folder], scope: String = "home", showsActionsFor: UUID? = nil, pickerOpen: Bool = false) {
        self.folders = folders
        self.notes = notes
        self.allNotes = allNotes
        self.allFolders = allFolders
        self.scope = scope
        _order = State(initialValue: OrderStore.load(scope))
        _actionsFolder = State(initialValue: showsActionsFor)
        _pickerOpen = State(initialValue: pickerOpen)
    }

    static let spacing: CGFloat = 19
    static let padding: CGFloat = 30
    static let idealWidth: CGFloat = 300
    static let scales: ClosedRange<Double> = 0.7...1.5

    private enum Item: Identifiable {
        case folder(Folder)
        case note(Note)

        var isFolder: Bool {
            if case .folder = self { return true }
            return false
        }

        var id: UUID {
            switch self {
            case .folder(let folder): folder.id
            case .note(let note): note.id
            }
        }
    }

    /// Folders and notes together, in the chosen order. A folder dates from
    /// the newest note in it, and sorts by its name. In the manual order,
    /// anything not placed yet comes first, newest first.
    private var items: [Item] {
        var position: [UUID: Int] = [:]
        for (index, id) in order.enumerated() { position[id] = index }
        var keyed: [(date: Date, title: String, item: Item)] = notes.map { note in
            (sort == .edited ? note.updatedAt ?? note.createdAt : note.createdAt, note.displayTitle, .note(note))
        }
        for folder in folders {
            let inside = allNotes.filter { $0.folderID == folder.id }
            let latest = inside.map { sort == .edited ? $0.updatedAt ?? $0.createdAt : $0.createdAt }.max() ?? folder.createdAt
            keyed.append((max(latest, folder.createdAt), folder.name, .folder(folder)))
        }
        keyed.sort { a, b in
            if foldersFirst, a.item.isFolder != b.item.isFolder { return a.item.isFolder }
            switch sort {
            case .title:
                let order = a.title.localizedStandardCompare(b.title)
                return ascending ? order == .orderedAscending : order == .orderedDescending
            case .made, .edited:
                return ascending ? a.date < b.date : a.date > b.date
            case .manual:
                switch (position[a.item.id], position[b.item.id]) {
                case (nil, nil): return a.date > b.date
                case (nil, _): return true
                case (_, nil): return false
                case let (x?, y?): return x < y
                }
            }
        }
        return keyed.map(\.item)
    }

    var body: some View {
        GeometryReader { geo in
            let metrics = metrics(width: geo.size.width)
            let s = metrics.scale
            let spacing = metrics.spacing
            let columns = metrics.columns
            let unit = metrics.unit
            let even = metrics.even
            ScrollView {
                if layout == .list {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            switch item {
                            case .folder(let folder):
                                FolderListRow(folder: folder, count: count(in: folder), isDropTarget: drag.fileTarget == folder.id, naming: naming(folder)) {
                                    navigator.go(.folder(folder.id))
                                } more: {
                                    toggleActions(for: folder)
                                }
                                .modifier(liftable(item, radius: 12))
                            case .note(let note):
                                NoteListRow(note: note, folderName: folderName(of: note), folders: allFolders, isDraggable: false)
                                    .modifier(liftable(item, radius: 12))
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                } else {
                    MasonryLayout(columns: columns, spacing: spacing) {
                        ForEach(items) { item in
                            switch item {
                            case .folder(let folder):
                                FolderCard(
                                    folder: folder,
                                    count: count(in: folder),
                                    height: even ?? unit,
                                    scale: s,
                                    isActive: actionsFolder == folder.id,
                                    isDropTarget: drag.fileTarget == folder.id,
                                    naming: naming(folder)
                                ) {
                                    navigator.go(.folder(folder.id))
                                } more: {
                                    toggleActions(for: folder)
                                }
                                .modifier(liftable(item, radius: 28 * s))
                                .zIndex(actionsFolder == folder.id ? 1 : 0)
                            case .note(let note):
                                NoteCard(note: note, folders: allFolders, unit: unit, scale: s, height: even, showsText: showsText)
                                    .modifier(liftable(item, radius: 28 * s))
                            }
                        }
                    }
                    .padding(.horizontal, Self.padding)
                    .padding(.top, 10)
                    .padding(.bottom, 84)
                }
            }
            .scrollIndicators(.visible)
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, y in frames.offset = y }
            .onScrollGeometryChange(for: CGFloat.self, of: { max(0, $0.contentSize.height - $0.containerSize.height) }) { _, most in
                frames.maxOffset = most
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.viewport = $0 }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { frames.width = $0 }
            .onDisappear {
                autoscroll?.cancel()
                if drag.held != nil, drag.isFollowing { NSCursor.pop() }
                if drag.held != nil { drag.end() }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: layout)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: sort)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: ascending)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: foldersFirst)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showsText)
            .overlay(alignment: .bottom) {
                if layout != .list {
                    CardSizeBar(scale: $scale, range: Self.scales)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlayPreferenceValue(FolderDotsAnchor.self) { anchors in
                GeometryReader { proxy in
                    if let id = actionsFolder, let anchor = anchors[id], let folder = folders.first(where: { $0.id == id }) {
                        actions(for: folder, at: proxy[anchor], in: proxy.size)
                    }
                }
            }
        }
        .background(Palette.background)
        // A folder made from Home's toolbar is named right on its card.
        .onChange(of: center.folderToRename, initial: true) { _, _ in beginPendingRename() }
        .onChange(of: folders.map(\.id)) { _, _ in beginPendingRename() }
        .alert(
            "Delete “\(deleting?.name ?? "")”?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let deleting { center.delete(deleting) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("The notes in it stay in Ovyl, out of any folder.")
        }
    }

    // MARK: Folder actions

    /// The pill over the folder's dots, and the flower over the pill's color
    /// button. They open below when there's no room above. Clicking anywhere
    /// else closes them.
    @ViewBuilder
    private func actions(for folder: Folder, at dots: CGRect, in size: CGSize) -> some View {
        let barHeight = FolderActionsBar.height
        let flower = FlowerPicker.size
        let above = dots.minY - 14 - barHeight - flower + 12 > 0
        let barX = min(max(dots.midX, FolderActionsBar.width / 2 + 10), size.width - FolderActionsBar.width / 2 - 10)
        let barY = above ? dots.minY - 14 - barHeight / 2 : dots.maxY + 14 + barHeight / 2
        let flowerY = above ? barY - barHeight / 2 - flower / 2 + 12 : barY + barHeight / 2 + flower / 2 - 12

        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { close() } }

            FlowerPicker(progress: pickerOpen ? 1 : 0, origin: barY - flowerY) { hex in
                withAnimation(.easeInOut(duration: 0.35)) {
                    folder.colorName = hex
                }
                center.save()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { close() }
            }
            .animation(pickerOpen ? FlowerPicker.opening : FlowerPicker.closing, value: pickerOpen)
            .position(x: barX + FolderActionsBar.colorOffset, y: flowerY)

            // The pill gives way to whatever it opens: the flower, or the
            // name being edited on the card.
            if !pickerOpen {
            FolderActionsBar(pickerOpen: pickerOpen, isPinned: folder.isPinned) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    close()
                    beginRename(folder)
                }
            } color: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { pickerOpen = true }
            } pin: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    center.setPinned(folder, !folder.isPinned)
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { close() }
            } delete: {
                deleting = folder
                close()
            }
            .position(x: barX, y: barY)
            .transition(.scale(scale: 0.85, anchor: above ? .bottom : .top).combined(with: .opacity))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func close() {
        pickerOpen = false
        actionsFolder = nil
    }

    // MARK: Renaming

    private func beginRename(_ folder: Folder) {
        editingName = folder.name
        editingFolder = folder.id
    }

    /// Keeps the name typed, if it's not empty, and stops editing.
    private func commitRename(_ folder: Folder) {
        guard editingFolder == folder.id else { return }
        center.rename(folder, to: editingName)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { editingFolder = nil }
    }

    private func cancelRename(_ folder: Folder) {
        editingName = folder.name
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { editingFolder = nil }
    }

    /// Starts naming a folder just made from Home's toolbar, once it's on
    /// the page. A pinned one is named in the sidebar instead.
    private func beginPendingRename() {
        guard let id = center.folderToRename, let folder = folders.first(where: { $0.id == id }), !folder.isPinned else { return }
        center.folderToRename = nil
        beginRename(folder)
    }

    /// What a folder card or row needs to edit its name in place.
    private func naming(_ folder: Folder) -> FolderNaming {
        FolderNaming(
            isEditing: editingFolder == folder.id,
            name: $editingName,
            commit: { commitRename(folder) },
            cancel: { cancelRename(folder) }
        )
    }

    // MARK: Reordering

    private var drag: CardDrag { windowDrag ?? ownDrag }

    /// The folder this page shows, if it's a folder's page.
    private var pageFolderID: UUID? { UUID(uuidString: scope) }

    private struct Metrics {
        var scale: CGFloat
        var spacing: CGFloat
        var columns: Int
        /// A card's height, from its column's width: one row of the messy grid.
        var unit: CGFloat
        /// The even grid gives every card the same height.
        var even: CGFloat?
    }

    /// How the cards are sized for a page this wide.
    private func metrics(width: CGFloat) -> Metrics {
        let s = CGFloat(scale)
        let spacing = (Self.spacing * s).rounded()
        let available = width - 2 * Self.padding
        let columns = max(1, Int((available + spacing) / (Self.idealWidth * s + spacing)))
        let column = floor((available - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        // Cards keep their proportions; one column caps them at their ideal size.
        let unit = (min(column, Self.idealWidth * s * 1.25) * 0.6).rounded()
        return Metrics(scale: s, spacing: spacing, columns: columns, unit: unit, even: layout == .grid ? (unit * 1.4).rounded() : nil)
    }

    /// Lets a card or row be picked up and carried to a new place.
    private func liftable(_ item: Item, radius: CGFloat) -> Liftable {
        Liftable(
            id: item.id,
            isHeld: drag.held?.id == item.id,
            isEnabled: editingFolder != item.id,
            radius: radius,
            frames: frames,
            changed: { dragChanged(item, $0) },
            ended: { _ in dragEnded(item) }
        )
    }

    /// Picks the card up on its first move, then keeps it under the pointer,
    /// leaning a little into the way it's going.
    private func dragChanged(_ item: Item, _ value: DragGesture.Value) {
        if drag.held?.id != item.id {
            guard drag.held == nil, let frame = frames.rects[item.id] else { return }
            drag.pickUp(
                CardDrag.Held(id: item.id, isFolder: item.isFolder),
                frame: frame,
                at: value.startLocation,
                preview: preview(of: item, size: frame.size)
            )
            frames.lastSwap = nil
            NSCursor.closedHand.push()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.68)) { drag.lift = 1 }
            startAutoscroll()
        }
        guard drag.isFollowing else { return }
        drag.pointer = value.location
        let lean = max(-1, min(1, value.velocity.width / 1400))
        withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.72)) { drag.tilt = lean * 3 }
        retarget()
    }

    /// Makes room where the card is over another, or marks the folder it
    /// would file into: a folder on the page, or a folder in the sidebar. A
    /// note held at a folder's edge for a moment takes the folder's place
    /// instead, so reaching a folder never pushes it away.
    private func retarget() {
        guard let held = drag.held, drag.isFollowing else { return }
        let point = drag.pointer
        if frames.viewport.contains(point) {
            if frames.rects[held.id]?.contains(point) == true {
                frames.lingering = nil
                setFileTarget(nil)
                return
            }
            if let target = items.first(where: { $0.id != held.id && frames.rects[$0.id]?.contains(point) == true }),
               let rect = frames.rects[target.id] {
                if target.isFolder, !held.isFolder {
                    if rect.insetBy(dx: rect.width * 0.14, dy: rect.height * 0.14).contains(point) {
                        frames.lingering = nil
                        setFileTarget(target.id)
                        return
                    }
                    setFileTarget(nil)
                    guard let lingering = frames.lingering, lingering.id == target.id else {
                        frames.lingering = (target.id, .now)
                        return
                    }
                    guard Date.now.timeIntervalSince(lingering.since) > 0.35 else { return }
                } else {
                    setFileTarget(nil)
                }
                frames.lingering = nil
                guard frames.lastSwap != target.id else { return }
                frames.lastSwap = target.id
                withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) { move(held.id, to: target.id) }
                return
            }
            frames.lastSwap = nil
            frames.lingering = nil
            setFileTarget(nil)
            return
        }
        frames.lastSwap = nil
        frames.lingering = nil
        if held.isFolder {
            // A folder carried onto the sidebar is pinned there.
            let pins = drag.sidebarFrame.contains(point) && folders.first { $0.id == held.id }?.isPinned == false
            if drag.pinsToSidebar != pins {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { drag.pinsToSidebar = pins }
            }
            return
        }
        let row = drag.sidebarFolders.first { $0.value.contains(point) }?.key
        setFileTarget(row == pageFolderID ? nil : row)
    }

    private func setFileTarget(_ id: UUID?) {
        if drag.pinsToSidebar {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { drag.pinsToSidebar = false }
        }
        guard drag.fileTarget != id else { return }
        withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) { drag.fileTarget = id }
    }

    /// Lets go: the card settles into its place, or sinks into the folder
    /// it's over and files into it.
    private func dragEnded(_ item: Item) {
        guard let held = drag.held, held.id == item.id, drag.isFollowing else { return }
        autoscroll?.cancel()
        NSCursor.pop()
        if drag.pinsToSidebar, let folder = folders.first(where: { $0.id == held.id }) {
            // Flies to its place in the sidebar, which takes it, and shows
            // again in its place on the page.
            let slot = drag.sidebarPinSlot
            let size = drag.size
            withAnimation(.spring(response: 0.36, dampingFraction: 0.88), completionCriteria: .removed) {
                drag.landing = CGRect(x: slot.midX - size.width / 2, y: slot.midY - size.height / 2, width: size.width, height: size.height)
                drag.sinks = true
                drag.tilt = 0
            } completion: {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                    center.setPinned(folder, true)
                    drag.end()
                }
            }
            return
        }
        if let folder = drag.fileTarget, let rect = frames.rects[folder] ?? drag.sidebarFolders[folder] {
            let size = drag.size
            withAnimation(.spring(response: 0.34, dampingFraction: 0.9), completionCriteria: .removed) {
                drag.landing = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
                drag.sinks = true
                drag.tilt = 0
            } completion: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                    center.move([held.id], to: folder)
                }
                // The note leaves the page first, so its place closes up
                // before the drag lets go of it.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    drag.end()
                }
            }
        } else {
            let place = frames.rects[held.id] ?? drag.frame
            withAnimation(.spring(response: 0.38, dampingFraction: 0.8), completionCriteria: .removed) {
                drag.landing = place
                drag.lift = 0
                drag.tilt = 0
            } completion: {
                drag.end()
            }
        }
    }

    /// Scrolls the page while the held card is near its top or bottom edge,
    /// faster the closer it gets, and checks again on a card held lingering
    /// at a folder's edge.
    private func startAutoscroll() {
        autoscroll?.cancel()
        frames.lingering = nil
        autoscroll = Task { @MainActor in
            while !Task.isCancelled, drag.isFollowing {
                try? await Task.sleep(for: .milliseconds(16))
                if frames.lingering != nil { retarget() }
                let view = frames.viewport
                let point = drag.pointer
                let edge: CGFloat = 70
                guard view.width > 0, point.x >= view.minX, point.x <= view.maxX else { continue }
                var push: CGFloat = 0
                if point.y < view.minY + edge {
                    push = -min(1, (view.minY + edge - point.y) / edge)
                } else if point.y > view.maxY - edge {
                    push = min(1, (point.y - (view.maxY - edge)) / edge)
                }
                guard push != 0 else { continue }
                let offset = min(max(frames.offset + push * abs(push) * 18, 0), frames.maxOffset)
                guard abs(offset - frames.offset) > 0.5 else { continue }
                frames.offset = offset
                scrollPosition.scrollTo(y: offset)
                retarget()
            }
        }
    }

    /// The card or row as it looks on the page, drawn by the window while
    /// it's held.
    private func preview(of item: Item, size: CGSize) -> AnyView {
        let metrics = metrics(width: frames.width)
        let row = RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.surface)
        switch (item, layout == .list) {
        case (.folder(let folder), true):
            return AnyView(FolderListRow(folder: folder, count: count(in: folder), open: {}, more: {}).background(row))
        case (.note(let note), true):
            let text = note.status == .ready ? NoteCard.preview(of: note.markdown, limit: 320) : ""
            return AnyView(NoteListRow(note: note, folderName: folderName(of: note), folders: allFolders, isDraggable: false, thumbnailPreview: text).background(row))
        case (.folder(let folder), false):
            return AnyView(FolderCard(folder: folder, count: count(in: folder), height: size.height, scale: metrics.scale, isActive: false, open: {}, more: {}))
        case (.note(let note), false):
            let text = note.status == .ready ? NoteCard.preview(of: note.markdown) : ""
            return AnyView(NoteCard(note: note, folders: allFolders, unit: metrics.unit, scale: metrics.scale, height: metrics.even, showsText: showsText, initialPreview: text))
        }
    }

/// Puts `dragged` where `target` is. The first move switches the page to
    /// its manual order, starting from the order on screen.
    private func move(_ dragged: UUID, to target: UUID) {
        let ids = OrderStore.moving(dragged, to: target, in: items.map(\.id))
        if sort != .manual { sort = .manual }
        order = ids
        OrderStore.save(ids, for: scope)
    }

    private func toggleActions(for folder: Folder) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if actionsFolder == folder.id {
                close()
            } else {
                pickerOpen = false
                actionsFolder = folder.id
            }
        }
    }

    private func count(in folder: Folder) -> Int {
        allNotes.filter { $0.folderID == folder.id }.count
    }

    /// The folder a note is in, shown in the list on Home.
    private func folderName(of note: Note) -> String? {
        guard !folders.isEmpty, let id = note.folderID else { return nil }
        return allFolders.first { $0.id == id }?.name
    }
}

/// Where each folder card's dots are, so the pill can sit over them.
struct FolderDotsAnchor: PreferenceKey {
    static let defaultValue: [UUID: Anchor<CGRect>] = [:]
    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Layout

/// Columns of equal width; each view goes in the shortest column so far.
struct MasonryLayout: Layout {
    var columns: Int
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 900
        let heights = place(subviews, width: width) { _, _, _ in }
        return CGSize(width: width, height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        _ = place(subviews, width: bounds.width) { subview, point, size in
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: ProposedViewSize(size))
        }
    }

    private func place(_ subviews: Subviews, width: CGFloat, _ put: (LayoutSubview, CGPoint, CGSize) -> Void) -> [CGFloat] {
        let count = max(1, columns)
        let column = (width - CGFloat(count - 1) * spacing) / CGFloat(count)
        var heights = Array(repeating: CGFloat(0), count: count)
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: column, height: nil))
            let index = heights.indices.min { heights[$0] < heights[$1] - 0.5 } ?? 0
            let y = heights[index] + (heights[index] > 0 ? spacing : 0)
            put(subview, CGPoint(x: CGFloat(index) * (column + spacing), y: y), CGSize(width: column, height: size.height))
            heights[index] = y + size.height
        }
        return heights
    }
}

// MARK: - Note card

/// A note as a white card: its title, the first of its text fading out,
/// and the day it was made with a menu.
struct NoteCard: View {
    @Environment(Navigator.self) private var navigator
    let note: Note
    let folders: [Folder]
    let unit: CGFloat
    var scale: CGFloat = 1
    /// A set height, for the even grid; nil sizes the card by its text.
    var height: CGFloat?
    var showsText = true

    @State private var preview: String
    @State private var isHovered = false

    /// `initialPreview` is the note's text when it's already known, as for a
    /// card that's being carried, so it's drawn whole from the start.
    init(note: Note, folders: [Folder], unit: CGFloat, scale: CGFloat = 1, height: CGFloat? = nil, showsText: Bool = true, initialPreview: String = "") {
        self.note = note
        self.folders = folders
        self.unit = unit
        self.scale = scale
        self.height = height
        self.showsText = showsText
        _preview = State(initialValue: initialPreview)
    }

    /// Notes with text stand two rows tall; an empty or unfinished note, one.
    private var isTall: Bool { note.status == .ready && !preview.isEmpty && showsText }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(note.displayTitle)
                .font(.system(size: 25 * scale, weight: .bold))
                .foregroundStyle(CardColor.title)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            content
            Spacer(minLength: 0)

            HStack(alignment: .center) {
                Text(Self.day(note.createdAt))
                    .font(.system(size: 14.5 * scale, weight: .semibold))
                    .tracking(1.7 * scale)
                    .foregroundStyle(CardColor.meta)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Menu {
                    Button("Open", systemImage: "doc.text") { navigator.go(.note(note.id)) }
                    Divider()
                    NoteMenuItems(note: note, folders: folders)
                } label: {
                    MoreDots(color: CardColor.meta, scale: scale)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.horizontal, 25 * scale)
        .padding(.top, 29 * scale)
        .padding(.bottom, 23 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height ?? (isTall ? unit * 2 : unit))
        .background(
            RoundedRectangle(cornerRadius: 28 * scale, style: .continuous)
                .fill(LinearGradient(colors: [CardColor.top, CardColor.bottom], startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28 * scale, style: .continuous)
                .strokeBorder(CardColor.edge, lineWidth: 1)
        )
        .shadow(color: CardColor.shadow, radius: isHovered ? 16 : 10, y: isHovered ? 8 : 5)
        .scaleEffect(isHovered ? 1.012 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 28 * scale, style: .continuous))
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isHovered)
        .onTapGesture { navigator.go(.note(note.id)) }
        .contextMenu {
            Button("Open", systemImage: "doc.text") { navigator.go(.note(note.id)) }
            Divider()
            NoteMenuItems(note: note, folders: folders)
        }
        .task(id: "\(note.statusRaw)|\(note.updatedAt?.timeIntervalSince1970 ?? 0)") {
            preview = note.status == .ready ? Self.preview(of: note.markdown) : ""
        }
    }

    @ViewBuilder
    private var content: some View {
        switch note.status {
        case .ready:
            if !preview.isEmpty, showsText {
                Text(preview)
                    .font(.system(size: 12 * scale))
                    .lineSpacing(6.5 * scale)
                    .foregroundStyle(CardColor.body)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                    .mask(
                        LinearGradient(
                            stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.3), .init(color: .clear, location: 0.97)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .padding(.top, 22 * scale)
                    .padding(.bottom, 14 * scale)
            }
        case .queued, .processing:
            VStack(alignment: .leading, spacing: 10) {
                LogoLoader(LogoMotion(note: note))
                    .frame(width: 30 * scale, height: 30 * scale)
                    .foregroundStyle(CardColor.title)
                Text(note.status == .queued ? "Waiting" : (note.stage.isEmpty ? "Working" : note.stage))
                    .font(.system(size: 12.5))
                    .foregroundStyle(CardColor.body)
                AccentProgressBar(value: note.progress, height: 4)
            }
            .padding(.top, 14)
        case .failed:
            Label(note.errorMessage ?? "Couldn't make this note", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Palette.danger)
                .lineLimit(3)
                .padding(.top, 14)
        }
    }

    /// "TODAY", "YESTERDAY", or "WED, 26 APR 23".
    static func day(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "TODAY" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "YESTERDAY"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "EEE, d MMM yy"
        return formatter.string(from: date).uppercased()
    }

    /// The start of the note as plain lines: Markdown marks, links and
    /// callout headers made plain, blank lines kept single.
    static func preview(of markdown: String, limit: Int = 700) -> String {
        var lines: [String] = []
        for raw in markdown.components(separatedBy: "\n") {
            var line = raw.trimmingCharacters(in: .whitespaces)
            line = line.replacing(/^>\s*\[![a-z]+\]\s*/) { _ in "" }
            line = line.replacing(/^>\s?/) { _ in "" }
            line = line.replacing(/^#{1,6}\s+/) { _ in "" }
            line = line.replacing(/\[([^\]\n]*)\]\([^)\n]*\)/) { "\($0.output.1)" }
            line = line.replacing(/[*_`]{1,3}/) { _ in "" }
            line = line.replacing(/^\s*[-*+]\s+\[[ xX]\]\s+/) { _ in "- " }
            if line.isEmpty {
                if let last = lines.last, !last.isEmpty { lines.append("") }
                continue
            }
            lines.append(line)
            if lines.joined(separator: "\n").count > limit { break }
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }
}

/// Three round dots, the cards' menu.
struct MoreDots: View {
    let color: Color
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 4 * scale) {
            ForEach(0..<3, id: \.self) { _ in
                Circle().fill(color).frame(width: 5.5 * scale, height: 5.5 * scale)
            }
        }
        .frame(height: 24)
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
    }
}

/// The note cards' colors, from the palette: a surface with a hairline
/// edge, and ink.
enum CardColor {
    static let top = Palette.surface
    static let bottom = Palette.surface
    static let edge = Palette.border
    static let shadow = Palette.shadow
    static let title = Palette.textPrimary
    static let body = Palette.textSecondary
    static let meta = Palette.textSecondary
}

// MARK: - Folder card

/// A folder as a colored card: the back with its tab, the notes inside
/// showing as paper sheets, and the front with the name, the count and a
/// menu. Notes dropped on it move into it.
struct FolderCard: View {
    @Environment(ProcessingCenter.self) private var center
    let folder: Folder
    let count: Int
    let height: CGFloat
    var scale: CGFloat = 1
    let isActive: Bool
    /// A note is being dragged over it, to file into it.
    var isDropTarget = false
    var naming = FolderNaming()
    var open: () -> Void
    var more: () -> Void

    @State private var isHovered = false

    private var isTargeted: Bool { isDropTarget }

    var body: some View {
        let tint = HexColor(folder.hex)
        let text: Color = tint.isLight ? Palette.onLight : Palette.onDark
        GeometryReader { geo in
            let h = geo.size.height
            let front = (h * FolderArtwork.front).rounded()
            ZStack(alignment: .topLeading) {
                FolderArtwork(tint: tint, count: count, isRaised: isHovered || isTargeted)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        FolderName(name: folder.name, naming: naming, font: .system(size: 25 * scale, weight: .bold))
                        HStack(spacing: 6 * scale) {
                            Text("\(count)")
                                .font(.system(size: 15 * scale, weight: .medium).monospacedDigit())
                                .tracking(1.5 * scale)
                            if folder.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 11 * scale, weight: .semibold))
                                    .help("Pinned to the sidebar")
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .opacity(0.82)
                    }
                    Spacer(minLength: 8)
                    Button(action: more) {
                        MoreDots(color: text, scale: scale)
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .help("Rename, color or delete")
                    .anchorPreference(key: FolderDotsAnchor.self, value: .bounds) { [folder.id: $0] }
                }
                .foregroundStyle(text)
                .padding(.horizontal, 25 * scale)
                .padding(.top, front + (h - front) * 0.16)
            }
        }
        .frame(height: height)
        .contentShape(FolderBackShape(tabWidth: 0, tabDrop: 0, radius: 28))
        .shadow(color: tint.color.opacity(0.32), radius: isHovered ? 20 : 16, y: isHovered ? 12 : 9)
        .scaleEffect(isTargeted ? 1.03 : isHovered ? 1.012 : 1)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isTargeted)
        .onTapGesture { if !naming.isEditing { open() } }
        .contextMenu {
            Button("Open", systemImage: "folder") { open() }
            Button("Rename, Color or Delete…", systemImage: "drop") { more() }
            PinMenuItem(folder: folder)
        }
    }
}

/// A folder drawn at any size: the back with its tab, a paper sheet for each
/// note inside up to three, sinking into the folder's color, and the front.
/// The folder cards and the list's thumbnails are both drawn with it.
struct FolderArtwork: View {
    let tint: HexColor
    let count: Int
    var isRaised = false

    /// Where the front begins, as a share of the height.
    static let front: CGFloat = 0.49

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let front = (h * Self.front).rounded()
            let radius = (h * 0.15).rounded()
            ZStack(alignment: .topLeading) {
                FolderBackShape(tabWidth: w * 0.445, tabDrop: h * 0.096, radius: radius)
                    .fill(LinearGradient(colors: [tint.mixed(0.26).color, tint.mixed(0.17).color], startPoint: .top, endPoint: .bottom))
                    .frame(height: front + radius)

                PaperSheets(count: min(count, 3), width: w, height: h, isRaised: isRaised)

                // The sheets sink into the folder's color as they reach the front.
                LinearGradient(colors: [tint.mixed(0.17).color.opacity(0), tint.mixed(0.17).color], startPoint: .top, endPoint: .bottom)
                    .frame(height: h * 0.13)
                    .offset(y: front - h * 0.13)

                UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [tint.color, tint.mixed(-0.025).color], startPoint: .top, endPoint: .bottom))
                    .frame(height: h - front)
                    .offset(y: front)
            }
        }
    }
}

/// A folder card in miniature, for the list: the same folder, no words.
struct FolderThumbnail: View {
    let folder: Folder
    let count: Int

    var body: some View {
        FolderArtwork(tint: HexColor(folder.hex), count: count)
            .frame(width: ListThumbnail.size.width, height: ListThumbnail.size.height)
            .shadow(color: folder.color.opacity(0.3), radius: 4, y: 2)
    }
}

/// A note card in miniature, for the list: a portrait page with the note's
/// own title, the start of its text fading out, and the day and dots along
/// the foot. It's laid out at three times the size and scaled down, so the
/// type stays sharp and true to the full card.
struct NoteThumbnail: View {
    let note: Note
    @State private var preview: String

    /// `initialPreview` is the note's text when it's already known.
    init(note: Note, initialPreview: String = "") {
        self.note = note
        _preview = State(initialValue: initialPreview)
    }

    static let size = CGSize(width: 40, height: 52)
    private static let scale: CGFloat = 1.0 / 3

    var body: some View {
        let inner = CGSize(width: Self.size.width / Self.scale, height: Self.size.height / Self.scale)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Text(note.displayTitle)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(CardColor.title)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(preview)
                .font(.system(size: 8.5))
                .lineSpacing(3)
                .foregroundStyle(CardColor.body)
                .padding(.top, 7)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .mask(
                    LinearGradient(
                        stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.35), .init(color: .clear, location: 1)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            HStack(spacing: 0) {
                Text(NoteCard.day(note.createdAt))
                    .font(.system(size: 7.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(CardColor.meta)
                    .lineLimit(1)
                Spacer(minLength: 2)
                MoreDots(color: CardColor.meta, scale: 0.55)
                    .frame(height: 8)
            }
            .padding(.top, 5)
        }
        .padding(.horizontal, 11)
        .padding(.top, 12)
        .padding(.bottom, 9)
        .frame(width: inner.width, height: inner.height, alignment: .topLeading)
        .background(shape.fill(LinearGradient(colors: [CardColor.top, CardColor.bottom], startPoint: .top, endPoint: .bottom)))
        .overlay(shape.strokeBorder(CardColor.edge, lineWidth: 2.5))
        .scaleEffect(Self.scale, anchor: .topLeading)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .shadow(color: CardColor.shadow, radius: 3, y: 1.5)
        .task(id: "\(note.statusRaw)|\(note.updatedAt?.timeIntervalSince1970 ?? 0)") {
            preview = note.status == .ready ? NoteCard.preview(of: note.markdown, limit: 320) : ""
        }
    }
}

/// The list's thumbnails: folders in the folder cards' wide shape, notes as
/// portrait pages, both centered in one column so the rows line up.
enum ListThumbnail {
    static let size = CGSize(width: 58, height: 40)
    static let column: CGFloat = 58
}

/// The back of a folder card: a tab on the left rising over the rest, the
/// two joined by a soft S-curve, round at the top corners.
struct FolderBackShape: Shape {
    let tabWidth: CGFloat
    let tabDrop: CGFloat
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height / 2)
        let top = rect.minY + tabDrop
        let curve = tabDrop * 1.7
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        if tabDrop > 0 {
            path.addLine(to: CGPoint(x: rect.minX + tabWidth - curve, y: rect.minY))
            path.addCurve(
                to: CGPoint(x: rect.minX + tabWidth + curve, y: top),
                control1: CGPoint(x: rect.minX + tabWidth - curve * 0.1, y: rect.minY),
                control2: CGPoint(x: rect.minX + tabWidth + curve * 0.1, y: top)
            )
        }
        path.addLine(to: CGPoint(x: rect.maxX - r, y: top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: top + r), control: CGPoint(x: rect.maxX, y: top))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Sheets standing in the folder, one for each note up to three, tilted a
/// little, with lines for text. They're the note cards' color, so they
/// follow light and dark mode as the cards do. They rise a touch when the
/// folder is hovered or a note is dragged over it.
struct PaperSheets: View {
    let count: Int
    let width: CGFloat
    let height: CGFloat
    var isRaised = false

    private struct Sheet {
        let x: CGFloat
        let top: CGFloat
        let width: CGFloat
        let angle: Double
        let lines: [CGFloat]
    }

    private var sheets: [Sheet] {
        switch count {
        case 0: return []
        case 1: return [Sheet(x: 0.3, top: 0.18, width: 0.385, angle: -2.5, lines: [0.85, 0.75, 0.6])]
        case 2: return [
            Sheet(x: 0.1, top: 0.2, width: 0.375, angle: -3, lines: [0.75, 0.55, 0.65]),
            Sheet(x: 0.47, top: 0.175, width: 0.385, angle: 1.5, lines: [0.8, 0.35, 0.45]),
        ]
        default: return [
            Sheet(x: 0.095, top: 0.2, width: 0.375, angle: -3, lines: [0.75, 0.55, 0.65]),
            Sheet(x: 0.33, top: 0.185, width: 0.3, angle: 2, lines: [0.6, 0.5]),
            Sheet(x: 0.525, top: 0.175, width: 0.385, angle: 0, lines: [0.8, 0.25, 0.4]),
        ]
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(sheets.enumerated()), id: \.offset) { index, sheet in
                RoundedRectangle(cornerRadius: width * 0.035, style: .continuous)
                    .fill(CardColor.top)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: height * 0.032) {
                            ForEach(Array(sheet.lines.enumerated()), id: \.offset) { _, line in
                                Capsule()
                                    .fill(CardColor.body.opacity(0.25))
                                    .frame(width: width * sheet.width * 0.78 * line, height: max(1, height * 0.028))
                            }
                        }
                        .padding(.top, height * 0.075)
                        .padding(.leading, width * 0.045)
                    }
                    .shadow(color: CardColor.shadow, radius: min(3, height * 0.02), y: min(1, height * 0.006))
                    .frame(width: width * sheet.width, height: height * 0.6)
                    .rotationEffect(.degrees(sheet.angle), anchor: .bottom)
                    .offset(x: width * sheet.x, y: height * sheet.top - (isRaised ? height * (0.03 + 0.012 * Double(index)) : 0))
            }
        }
    }
}

// MARK: - Size

/// The card size slider at the foot of Home: small cards at the left,
/// large at the right; the grid icons step it too.
struct CardSizeBar: View {
    @Binding var scale: Double
    let range: ClosedRange<Double>

    var body: some View {
        FloatingBar {
            Button { step(-0.1) } label: {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 10.5, weight: .medium))
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Smaller cards")
            SizeSlider(value: $scale, range: range)
                .frame(width: 150, height: 24)
                .padding(.horizontal, 4)
            Button { step(0.1) } label: {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Larger cards")
        }
        .foregroundStyle(Palette.textPrimary.opacity(0.62))
    }

    private func step(_ amount: Double) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            scale = min(max((scale + amount) * 10, range.lowerBound * 10), range.upperBound * 10).rounded() / 10
        }
    }
}

/// A slim track with a white knob; the part before the knob is filled.
struct SizeSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let knob: CGFloat = 16
            let travel = geo.size.width - knob
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let x = travel * CGFloat(min(max(fraction, 0), 1))
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.fill).frame(height: 4)
                Capsule().fill(Palette.accent).frame(width: x + knob / 2, height: 4)
                Circle()
                    .fill(Palette.onDark)
                    .overlay(Circle().strokeBorder(Palette.border, lineWidth: 0.5))
                    .shadow(color: Palette.shadow, radius: isDragging ? 4 : 2, y: 1)
                    .frame(width: knob, height: knob)
                    .scaleEffect(isDragging ? 1.12 : 1)
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        let fraction = min(max((drag.location.x - knob / 2) / travel, 0), 1)
                        value = range.lowerBound + Double(fraction) * (range.upperBound - range.lowerBound)
                    }
                    .onEnded { _ in isDragging = false }
            )
            .animation(.easeOut(duration: 0.12), value: isDragging)
        }
        .help("Card size")
        .accessibilityRepresentation {
            Slider(value: $value, in: range) { Text("Card size") }
                .tint(Palette.accent)
        }
    }
}

// MARK: - View options

/// How Home and folders lay out their cards.
enum HomeLayout: String, CaseIterable, Identifiable {
    case messy, grid, list

    var id: String { rawValue }

    var label: String {
        switch self {
        case .messy: "Messy Grid"
        case .grid: "Grid"
        case .list: "List"
        }
    }

    var symbol: String {
        switch self {
        case .messy: "rectangle.3.group"
        case .grid: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }
}

/// What Home and folders sort by.
enum HomeSort: String, CaseIterable, Identifiable {
    case made, edited, title
    /// The order the cards were dragged into.
    case manual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .made: "Date Made"
        case .edited: "Date Edited"
        case .title: "Title"
        case .manual: "Manual"
        }
    }
}

/// The view menu in the toolbar: layout, sort, order, folders first and
/// note text, kept for next time.
struct HomeView: View {
    static let layoutKey = "homeLayout"
    static let sortKey = "homeSort"
    static let ascendingKey = "homeAscending"
    static let foldersFirstKey = "homeFoldersFirst"
    static let showsTextKey = "homeShowsText"

    @AppStorage(layoutKey) private var layout = HomeLayout.messy
    @AppStorage(sortKey) private var sort = HomeSort.made
    @AppStorage(ascendingKey) private var ascending = false
    @AppStorage(foldersFirstKey) private var foldersFirst = false
    @AppStorage(showsTextKey) private var showsText = true
    /// Whether the page has folders to put first.
    var hasFolders = true

    var body: some View {
        PillMenu(symbol: layout.symbol, help: "View options") {
            Picker("View", selection: $layout) {
                ForEach(HomeLayout.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.inline)
            Picker("Sort By", selection: $sort) {
                ForEach(HomeSort.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
            if sort != .manual {
            Picker("Order", selection: $ascending) {
                Text(sort == .title ? "A to Z" : "Newest First").tag(sort == .title)
                Text(sort == .title ? "Z to A" : "Oldest First").tag(sort != .title)
            }
            .pickerStyle(.inline)
            }
            Divider()
            if hasFolders {
                Toggle("Folders First", isOn: $foldersFirst)
            }
            Toggle("Show Note Text", isOn: $showsText)
                .disabled(layout == .list)
        }
        // Titles read best A to Z, dates newest first.
        .onChange(of: sort) { _, sort in ascending = sort == .title }
    }
}

/// A folder as a row in the list view: its color, name and count, and the
/// dots for its pill.
struct FolderListRow: View {
    @Environment(ProcessingCenter.self) private var center
    let folder: Folder
    let count: Int
    var isDropTarget = false
    var naming = FolderNaming()
    var open: () -> Void
    var more: () -> Void
    @State private var isHovered = false

    private var isTargeted: Bool { isDropTarget }

    var body: some View {
        HStack(spacing: 14) {
            FolderThumbnail(folder: folder, count: count)
                .frame(width: ListThumbnail.column, height: NoteThumbnail.size.height)
            VStack(alignment: .leading, spacing: 3) {
                FolderName(name: folder.name, naming: naming, font: .system(size: 13.5, weight: .medium))
                Text((folder.isPinned ? "Pinned · " : "") + (count == 1 ? "1 note" : "\(count) notes"))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 8)
            Button(action: more) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Rename, color or delete")
            .anchorPreference(key: FolderDotsAnchor.self, value: .bounds) { [folder.id: $0] }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 10)
        .background(isTargeted ? Palette.accentSoft : isHovered ? Palette.hover : .clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { if !naming.isEditing { open() } }
        .contextMenu {
            Button("Open", systemImage: "folder") { open() }
            Button("Rename, Color or Delete…", systemImage: "drop") { more() }
            PinMenuItem(folder: folder)
        }
    }
}

/// Pins a folder to the sidebar, or takes it off, from a menu.
struct PinMenuItem: View {
    @Environment(ProcessingCenter.self) private var center
    let folder: Folder

    var body: some View {
        Button(folder.isPinned ? "Unpin from Sidebar" : "Pin to Sidebar", systemImage: folder.isPinned ? "pin.slash" : "pin") {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                center.setPinned(folder, !folder.isPinned)
            }
        }
    }
}

/// A folder's name being edited where it's shown: whether it is, the name
/// so far, and keeping or dropping it.
struct FolderNaming {
    var isEditing = false
    var name: Binding<String> = .constant("")
    var commit: () -> Void = {}
    var cancel: () -> Void = {}
}

/// A folder's name, or, while it's being edited, a field in its place,
/// focused with the name selected. Return or clicking away keeps it; Escape
/// drops it.
struct FolderName: View {
    let name: String
    let naming: FolderNaming
    let font: Font
    @FocusState private var focused: Bool

    var body: some View {
        if naming.isEditing {
            TextField("Folder name", text: naming.name)
                .textFieldStyle(.plain)
                .font(font)
                .lineLimit(1)
                .focused($focused)
                .onSubmit(naming.commit)
                .onExitCommand(perform: naming.cancel)
                .onAppear { DispatchQueue.main.async { focused = true } }
                .onChange(of: focused) { _, focused in
                    if !focused { naming.commit() }
                }
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.foreground.opacity(0.14))
                        .padding(.horizontal, -7)
                        .padding(.vertical, -3)
                }
                .transition(.opacity)
        } else {
            Text(name)
                .font(font)
                .lineLimit(1)
        }
    }
}
