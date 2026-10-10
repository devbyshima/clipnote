import SwiftUI

/// The middle pane for Home or a folder: the notes, newest first, grouped by
/// when they were made.
struct NotesListView: View {
    @Environment(Navigator.self) private var navigator
    let title: String
    var folder: Folder?
    let notes: [Note]
    let folders: [Folder]
    var onNew: () -> Void

    @State private var query = ""
    @State private var isSearching = false
    @FocusState private var searchFocused: Bool
    /// What the index found for `searched`, best first.
    @State private var matches: [NoteMatch] = []
    @State private var searched = ""

    /// The notes the index found, best first, then any whose title matches
    /// but that the index hasn't caught up with yet.
    private var results: [Note] {
        guard !query.isEmpty else { return notes }
        var byID: [UUID: Note] = [:]
        for note in notes { byID[note.id] = note }
        let found = matches.compactMap { byID[$0.noteID] }
        let foundIDs = Set(found.map(\.id))
        let titles = notes.filter { !foundIDs.contains($0.id) && $0.displayTitle.localizedStandardContains(query) }
        return found + titles
    }

    private func match(for note: Note) -> NoteMatch? {
        matches.first { $0.noteID == note.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            PaneToolbar {
                if isSearching {
                    EmptyView()
                } else {
                    HStack(spacing: 7) {
                        if let folder {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(folder.color)
                        }
                        Text(title)
                            .font(.system(size: 14, weight: .medium))
                        CountBadge(count: notes.count)
                    }
                }
            } trailing: {
                if isSearching { searchField }
                PillGroup {
                    PillButton(symbol: "magnifyingglass", help: "Search (⌘F)", isActive: isSearching) {
                        toggleSearch()
                    }
                    .keyboardShortcut("f", modifiers: .command)
                    PillButton(symbol: "plus", help: "New note from a video, audio or pictures (⌘N)", action: onNew)
                }
                if query.isEmpty, !(notes.isEmpty && folders.isEmpty) {
                    PillGroup { HomeView(hasFolders: folder == nil && !folders.isEmpty) }
                }
                AssistantToggle()
            }
            list
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ovylBG)
        .task(id: query) {
            guard !query.isEmpty else {
                matches = []
                searched = ""
                return
            }
            // Let typing settle before asking the index.
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            let scope = folder == nil ? nil : Set(notes.map(\.id))
            let found = await SearchIndex.shared.search(query, in: scope)
            guard !Task.isCancelled else { return }
            matches = found
            searched = query
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            TextField(folder == nil ? "Search notes" : "Search \(title)", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onSubmit {
                    if let first = results.first { navigator.go(.note(first.id)) }
                }
                .onExitCommand { toggleSearch() }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 240, height: 30)
        .background(Capsule(style: .continuous).fill(Color.ovylSurface))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.ovylBorder, lineWidth: 0.5))
    }

    private func toggleSearch() {
        withAnimation(.snappy(duration: 0.2)) { isSearching.toggle() }
        if isSearching {
            DispatchQueue.main.async { searchFocused = true }
        } else {
            query = ""
        }
    }

    @ViewBuilder
    private var list: some View {
        if notes.isEmpty, folder == nil, folders.isEmpty {
            HomeEmptyState(onNew: onNew)
        } else if notes.isEmpty, folder != nil {
            FolderEmptyState(onNew: onNew)
        } else if !query.isEmpty, results.isEmpty, searched == query {
            SearchEmptyState(query: query)
                .id(query)
        } else if !query.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Text("Best matches")
                        Text("\(results.count)")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ovylSecondary)
                    .padding(.horizontal, 30)
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                    ForEach(results) { note in
                        NoteListRow(note: note, folderName: folderName(of: note), folders: folders, match: match(for: note))
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.visible)
        } else {
            // Home shows the folders and the notes outside them; a folder, its notes.
            CardGrid(
                folders: folder == nil ? folders : [],
                notes: folder == nil ? notes.filter { $0.folderID == nil } : notes,
                allNotes: notes,
                allFolders: folders,
                scope: folder?.id.uuidString ?? "home"
            )
        }
    }

    private func folderName(of note: Note) -> String? {
        guard folder == nil, let id = note.folderID else { return nil }
        return folders.first { $0.id == id }?.name
    }
}

/// One note in the list: the note's card in miniature, the title, when and
/// how long, and a menu. The note last opened is highlighted.
struct NoteListRow: View {
    @Environment(Navigator.self) private var navigator
    let note: Note
    var folderName: String?
    let folders: [Folder]
    /// Where a search found the note, shown under its title.
    var match: NoteMatch?
    /// Whether the row drags itself; the grid's list does it instead.
    var isDraggable = true
    @State private var isHovered = false

    private var isLastOpened: Bool {
        navigator.back.last?.noteID == note.id || navigator.forward.last?.noteID == note.id
    }

    var body: some View {
        HStack(spacing: 14) {
            NoteThumbnail(note: note)
                .frame(width: ListThumbnail.column)

            VStack(alignment: .leading, spacing: 3) {
                Text(note.displayTitle)
                    .font(.system(size: 13.5))
                    .lineLimit(1)
                if let match, match.best.kind != .title {
                    MatchSnippet(hit: match.best, count: match.count)
                } else {
                    subtitle
                }
            }

            Spacer(minLength: 8)

            Menu {
                Button("Open", systemImage: "doc.text") { navigator.go(.note(note.id)) }
                Divider()
                NoteMenuItems(note: note, folders: folders)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.ovylSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 10)
        .background(isLastOpened ? Color.ovylSelection : (isHovered ? Color.ovylFill.opacity(0.5) : .clear))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { navigator.go(.note(note.id)) }
        .modifier(NoteDrag(id: note.id, title: note.displayTitle, isOn: isDraggable))
        .contextMenu {
            Button("Open", systemImage: "doc.text") { navigator.go(.note(note.id)) }
            Divider()
            NoteMenuItems(note: note, folders: folders)
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        switch note.status {
        case .processing:
            HStack(spacing: 8) {
                ProgressView(value: note.progress)
                    .frame(width: 70)
                Text(note.stage.isEmpty ? "Working" : note.stage)
                    .lineLimit(1)
            }
            .font(.system(size: 12))
            .foregroundStyle(Color.ovylSecondary)
        case .queued:
            Text("Waiting")
                .font(.system(size: 12))
                .foregroundStyle(Color.ovylSecondary)
        case .failed:
            Label(note.errorMessage ?? "Couldn't make this note", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .lineLimit(1)
        case .ready:
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(Color.ovylSecondary)
                .lineLimit(1)
        }
    }

    private var caption: String {
        var parts = [Self.age(of: note.createdAt)]
        if note.kind == .pictures {
            let count = note.pictureBookmarks.count
            parts.append(count == 1 ? "1 picture" : "\(count) pictures")
        } else if note.duration > 0 {
            parts.append(TimeFormat.clock(note.duration))
        }
        if let folderName { parts.append(folderName) }
        return parts.joined(separator: " · ")
    }

    /// "7m", "3h", "2d", "5w".
    static func age(of date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        case ..<(86_400 * 7): return "\(Int(seconds / 86_400))d"
        case ..<(86_400 * 365): return "\(Int(seconds / (86_400 * 7)))w"
        default: return "\(Int(seconds / (86_400 * 365)))y"
        }
    }
}

/// Where a search matched inside a note: when, and the words around it with
/// the matched ones marked.
struct MatchSnippet: View {
    let hit: SearchHit
    let count: Int

    var body: some View {
        Text(line)
            .font(.system(size: 12))
            .foregroundStyle(Color.ovylSecondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var line: AttributedString {
        var placeText = AttributedString(place)
        placeText.foregroundColor = Color.ovylAccent
        return placeText + Self.marked(hit.snippet)
    }

    private var place: String {
        let more = count > 1 ? " +\(count - 1)" : ""
        switch hit.kind {
        case .screen: return "On screen\(hit.start.map { " " + TimeFormat.clock($0) } ?? "")\(more)  "
        case .picture: return "Picture\(more)  "
        case .summary: return "Summary\(more)  "
        default: return hit.start.map { TimeFormat.clock($0) + more + "  " } ?? (count > 1 ? "\(count) matches  " : "")
        }
    }

    /// The snippet with the matched words in the primary color.
    static func marked(_ snippet: String) -> AttributedString {
        var result = AttributedString()
        var current = ""
        var inside = false
        func flush() {
            guard !current.isEmpty else { return }
            var piece = AttributedString(current)
            if inside {
                piece.foregroundColor = .primary
                piece.backgroundColor = Color.ovylHighlight
            }
            result += piece
            current = ""
        }
        for character in snippet.replacing("\n", with: " ") {
            if character == SearchHit.markStart {
                flush()
                inside = true
            } else if character == SearchHit.markEnd {
                flush()
                inside = false
            } else {
                current.append(character)
            }
        }
        flush()
        return result
    }
}

/// A note row that can be dragged onto a folder, when the row drags itself.
struct NoteDrag: ViewModifier {
    let id: UUID
    let title: String
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.draggable(NoteReference(id: id)) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.ovylSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        } else {
            content
        }
    }
}
