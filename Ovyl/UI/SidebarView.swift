import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let ovylNote = UTType(exportedAs: "com.fulltimestudio.ovyl.note")
}

/// A note dragged in the window, to drop on a folder.
struct NoteReference: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .ovylNote)
    }
}

extension Folder {
    var color: Color { Color(hex: hex) }
}

/// The left sidebar: Home and New, then the folders, each with its count.
/// The speech model's state sits at the bottom.
struct SidebarView: View {
    @Environment(ProcessingCenter.self) private var center
    @Environment(Navigator.self) private var navigator
    @AppStorage("showSidebar") private var showSidebar = true
    let notes: [Note]
    let folders: [Folder]
    var onNew: () -> Void

    @State private var renameText = ""
    @State private var dropFolderID: UUID?
    @FocusState private var renameFocused: Bool

    static let width: CGFloat = 224

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: MainWindowStyler.trafficLightsWidth)
                PillGroup {
                    PillButton(symbol: "sidebar.left", help: "Hide the sidebar (⌘.)") { showSidebar = false }
                }
            }
            .padding(.trailing, 12)
            .frame(height: MainWindowStyler.barHeight)
            .background(WindowDragHandle())

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    row("Home", symbol: "circle.grid.3x3", color: nil, count: notes.count, selected: isListShown(.home)) {
                        navigator.go(.home)
                    }
                    row("New", symbol: "plus.square", color: nil, count: nil, selected: false, action: onNew)
                        .help("New note from a video, audio or pictures (⌘N)")

                    HStack {
                        Text("Folders")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.ovylSecondary)
                        Spacer()
                        Button { center.createFolder() } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(Color.primary.opacity(0.6))
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("New folder (⇧⌘N)")
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 6)
                    .padding(.top, 18)
                    .padding(.bottom, 4)

                    if folders.isEmpty {
                        Text("Make a folder, then drag notes onto it.")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                    }
                    ForEach(folders) { folderRow($0) }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .scrollIndicators(.never)

            ModelStatusRow()
        }
        .frame(width: Self.width)
        .background(Color.ovylSidebar, ignoresSafeAreaEdges: .top)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.ovylBorder).frame(width: 1).ignoresSafeArea(edges: .top)
        }
    }

    /// Whether the sidebar shows `list` as selected: it's the list on screen,
    /// or the list the open note came from.
    private func isListShown(_ list: Route) -> Bool {
        navigator.route.isList ? navigator.route == list : navigator.listRoute == list
    }

    private func row(_ title: String, symbol: String, color: Color?, count: Int?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(color ?? Color.primary.opacity(0.7))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 12.5).monospacedDigit())
                        .foregroundStyle(Color.ovylSecondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RowBackground(selected: selected))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    private func folderRow(_ folder: Folder) -> some View {
        let route = Route.folder(folder.id)
        let count = notes.filter { $0.folderID == folder.id }.count
        return HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.system(size: 13.5))
                .foregroundStyle(folder.color)
                .frame(width: 20)
            if center.folderToRename == folder.id {
                TextField("Folder name", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .focused($renameFocused)
                    .onSubmit { commitRename(folder) }
                    .onExitCommand { center.folderToRename = nil }
                    .onAppear {
                        renameText = folder.name
                        DispatchQueue.main.async { renameFocused = true }
                    }
                    .onChange(of: renameFocused) { _, focused in
                        if !focused { commitRename(folder) }
                    }
            } else {
                Text(folder.name)
                    .font(.system(size: 13.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("\(count)")
                .font(.system(size: 12.5).monospacedDigit())
                .foregroundStyle(Color.ovylSecondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RowBackground(selected: isListShown(route), targeted: dropFolderID == folder.id))
        .contentShape(Rectangle())
        .onTapGesture { navigator.go(route) }
        .contextMenu {
            Button("New Note Here…", systemImage: "plus.square") {
                navigator.go(route)
                onNew()
            }
            Button("Rename", systemImage: "pencil") { center.folderToRename = folder.id }
            Divider()
            Button("Delete Folder", systemImage: "trash", role: .destructive) {
                center.delete(folder)
            }
        }
        .dropDestination(for: NoteReference.self) { references, _ in
            center.move(references.map(\.id), to: folder.id)
            return true
        } isTargeted: { targeted in
            if targeted { dropFolderID = folder.id } else if dropFolderID == folder.id { dropFolderID = nil }
        }
    }

    private func commitRename(_ folder: Folder) {
        guard center.folderToRename == folder.id else { return }
        center.rename(folder, to: renameText)
        center.folderToRename = nil
    }
}

/// A row's highlight: gray when selected, fainter on hover.
struct RowBackground: View {
    var selected: Bool
    var targeted = false
    @State private var isHovered = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(selected ? Color.ovylFill
                : targeted ? Color.ovylAccent.opacity(0.18)
                : isHovered ? Color.ovylFill.opacity(0.55) : .clear)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.1), value: isHovered)
    }
}

/// The actions for a note, shared by the list and the note's menu.
struct NoteMenuItems: View {
    @Environment(ProcessingCenter.self) private var center
    @Environment(Navigator.self) private var navigator
    let note: Note
    let folders: [Folder]

    var body: some View {
        Menu("Move to", systemImage: "folder") {
            Button("No Folder") { center.move([note.id], to: nil) }
                .disabled(note.folderID == nil)
            if !folders.isEmpty { Divider() }
            ForEach(folders) { folder in
                Button(folder.name) { center.move([note.id], to: folder.id) }
                    .disabled(note.folderID == folder.id)
            }
        }
        switch note.status {
        case .queued, .processing:
            Button("Stop Processing", systemImage: "stop.circle") { center.stop(note) }
        case .ready, .failed:
            Button("Process Again", systemImage: "arrow.clockwise") { center.enqueue(note) }
        }
        Button("Show in Finder", systemImage: "folder") { note.revealSource() }
        Divider()
        Button("Delete…", systemImage: "trash", role: .destructive) {
            navigator.pendingDelete = note.id
        }
    }
}

extension Note {
    /// Shows the note's video or pictures in Finder.
    func revealSource() {
        let urls = kind == .pictures ? resolvePictures() : resolveSource().map { [$0] } ?? []
        let accessed = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { for url in accessed { url.stopAccessingSecurityScopedResource() } }
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }
}

/// Settings at the foot of the sidebar. While the speech model loads, a pill
/// beside it says so; it goes away once the model is ready.
struct ModelStatusRow: View {
    @Environment(ProcessingCenter.self) private var center

    var body: some View {
        HStack(spacing: 8) {
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.72))
                    .frame(width: 42, height: 30)
                    .background(Capsule(style: .continuous).fill(Color.ovylSurface))
                    .overlay(Capsule(style: .continuous).strokeBorder(Color.ovylBorder, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.05), radius: 1.5, y: 0.5)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help("Settings (⌘,)")

            if let status {
                HStack(spacing: 7) {
                    if status.isProblem {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.orange)
                    } else {
                        ProgressView().controlSize(.mini)
                    }
                    Text(status.label)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ovylSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Capsule(style: .continuous).fill(Color.ovylSurface))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.ovylBorder, lineWidth: 0.5))
                .help(status.help)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: status?.label)
    }

    private struct Status {
        let label: String
        let help: String
        var isProblem = false
    }

    /// Nothing while the model is idle or ready.
    private var status: Status? {
        switch center.speechPhase {
        case .loading(let firstTime):
            Status(
                label: "Loading speech model",
                help: firstTime ? "The first time takes about a minute." : "This takes a few seconds."
            )
        case .optimizing:
            Status(
                label: "Optimizing speech",
                help: "Videos are transcribed already. When this one-time step finishes, transcription is faster and uses less power."
            )
        case .failed(let message):
            Status(label: "Using Apple Speech", help: message, isProblem: true)
        case .idle, .ready:
            nil
        }
    }
}
