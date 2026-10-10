import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A finished note. It opens in reader mode: the title, then the note
/// rendered. Edit mode (⌘E) edits its Markdown, with the syntax shown only on
/// the line being edited, and saves as you type. Info shows the note's details
/// and summary in the right pane.
struct NoteDocumentView: View {
    @Environment(ProcessingCenter.self) private var center
    @Environment(Navigator.self) private var navigator
    @AppStorage("showMedia") private var showRightPane = true
    @AppStorage("showAssistant") private var showAssistant = false
    @Bindable var note: Note
    let folders: [Folder]
    let folderName: String?
    var onLink: (URL) -> OpenURLAction.Result

    @State private var isEditing: Bool
    @State private var text = ""
    @State private var blocks: [MarkdownBlock] = []
    @State private var draftTitle = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var copied = false
    @State private var editor = EditorController()
    @AppStorage("readerSerif") private var serif = false
    @AppStorage("readerSize") private var size = 16.0

    init(note: Note, folders: [Folder], folderName: String?, startsEditing: Bool = false, onLink: @escaping (URL) -> OpenURLAction.Result) {
        self.note = note
        self.folders = folders
        self.folderName = folderName
        self.onLink = onLink
        _isEditing = State(initialValue: startsEditing)
    }

    private var style: ReaderStyle { ReaderStyle(size: size, serif: serif) }

    var body: some View {
        VStack(spacing: 0) {
            PaneToolbar {
                NoteTitle(note: note, subtitle: folderName)
            } trailing: {
                PillGroup {
                    PillButton(symbol: "book", help: "Reader (⌘E)", isActive: !isEditing) { setEditing(false) }
                    PillButton(symbol: "pencil", help: "Edit (⌘E)", isActive: isEditing) { setEditing(true) }
                    PillButton(symbol: copied ? "checkmark" : "doc.on.doc", help: "Copy the note as Markdown") { copyNote() }
                    PillButton(symbol: "info.circle", help: "Note info", isActive: showsInfo) { toggleInfo() }
                }
                PillGroup {
                    PillMenu(help: "Export and more") { moreItems }
                }
                RightPaneToggle()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    title
                    content
                        .padding(.top, 24)
                }
                .frame(maxWidth: style.lineWidth, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.top, 34)
                .padding(.bottom, 140)
                .frame(maxWidth: .infinity)
            }
            .textSelection(.enabled)
            .tint(Palette.accentText)
            .environment(\.openURL, OpenURLAction(handler: onLink))
            .environment(\.readerStyle, style)
            .overlay(alignment: .bottom) {
                if !isEditing { typographyBar.padding(.bottom, 16) }
            }
        }
        .background(Palette.background)
        .background { shortcuts }
        .onAppear(perform: load)
        .onDisappear(perform: flush)
        .onChange(of: note.contentData) {
            if !isEditing { load() }
        }
        .onChange(of: text) {
            if isEditing { scheduleSave() }
        }
    }

    // MARK: Page

    @ViewBuilder
    private var title: some View {
        let font = Font.ovyl(style.titleSize, .bold, serif: serif)
        if isEditing {
            TextField("Untitled", text: $draftTitle, axis: .vertical)
                .textFieldStyle(.plain)
                .font(font)
                .onSubmit(commitTitle)
        } else {
            Text(note.displayTitle)
                .font(font)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isEditing {
            MarkdownEditor(text: $text, controller: editor, style: style)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Start writing…")
                            .font(.ovyl(style.size, serif: serif))
                            .foregroundStyle(Palette.faint)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .topLeading) { FormatBar(editor: editor) }
        } else if blocks.isEmpty {
            Text("This note is empty. Press ⌘E to write in it.")
                .font(.ovyl(style.size, serif: serif))
                .foregroundStyle(Palette.faint)
        } else {
            MarkdownView(blocks: blocks) { line in toggleTask(at: line) }
        }
    }

    private var showsInfo: Bool { showRightPane && !showAssistant && navigator.showsNoteInfo }

    /// Shows the note's info in the right pane, or goes back to its media.
    /// Opened over the media, the info's way out is back to it; opened into
    /// a hidden pane or over the assistant, it closes.
    private func toggleInfo() {
        if showsInfo {
            navigator.showsNoteInfo = false
        } else {
            navigator.noteInfoReturnsToMedia = showRightPane && !showAssistant && navigator.showsNoteInfo == false && note.kind != .text
            showAssistant = false
            navigator.showsNoteInfo = true
            showRightPane = true
        }
    }

    /// Sans or serif, and the text size, as in a reader.
    private var typographyBar: some View {
        FloatingBar {
            segment("Sans", isOn: !serif) { serif = false }
            segment("Serif", isOn: serif) { serif = true }
            Rectangle().fill(Palette.border).frame(width: 1, height: 16).padding(.horizontal, 4)
            Button { size = max(12, size - 1) } label: {
                Image(systemName: "minus").frame(width: 26, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(size <= 12)
            Text("\(Int(size))")
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .frame(minWidth: 22)
            Button { size = min(24, size + 1) } label: {
                Image(systemName: "plus").frame(width: 26, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(size >= 24)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Palette.textPrimary.opacity(0.8))
    }

    private func segment(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.ovyl(13, isOn ? .semibold : .regular, serif: title == "Serif"))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(isOn ? Palette.fill : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Editing

    private func load() {
        text = note.markdown
        blocks = MarkdownDocument.parse(text)
        draftTitle = note.displayTitle
    }

    private func setEditing(_ editing: Bool) {
        guard editing != isEditing else { return }
        if editing {
            draftTitle = note.displayTitle
        } else {
            flush()
            blocks = MarkdownDocument.parse(text)
        }
        withAnimation(.snappy(duration: 0.2)) { isEditing = editing }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func save() {
        guard text != note.markdown else { return }
        note.setMarkdown(text)
        center.save()
    }

    /// Saves anything pending now: the text and the title.
    private func flush() {
        saveTask?.cancel()
        saveTask = nil
        if isEditing {
            save()
            commitTitle()
        }
    }

    private func commitTitle() {
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != note.displayTitle else { return }
        note.title = title
        note.titleEdited = true
        note.updatedAt = .now
        center.save()
    }

    private func toggleTask(at line: Int) {
        text = MarkdownDocument.togglingTask(in: text, line: line)
        blocks = MarkdownDocument.parse(text)
        save()
    }

    /// ⌘E switches between reader and edit mode.
    private var shortcuts: some View {
        Button { setEditing(!isEditing) } label: { Color.clear.frame(width: 0, height: 0) }
            .buttonStyle(.plain)
            .keyboardShortcut("e", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    // MARK: Copy and export

    private func copyNote() {
        copy(exportMarkdown)
        withAnimation(.snappy(duration: 0.15)) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.snappy(duration: 0.15)) { copied = false }
        }
    }

    @ViewBuilder
    private var moreItems: some View {
        Button("Copy as Markdown", systemImage: "doc.on.doc") { copy(exportMarkdown) }
        Button("Copy as Plain Text", systemImage: "doc.plaintext") { copy(exportPlainText) }
        Button("Export Markdown File…", systemImage: "square.and.arrow.down") { saveMarkdownFile() }
        ShareLink("Share…", item: exportMarkdown)
        if note.editedMarkdown != nil {
            Divider()
            Button("Revert to Ovyl's Text", systemImage: "arrow.uturn.backward") {
                note.editedMarkdown = nil
                note.searchText = note.content?.plainText ?? ""
                center.save()
                load()
            }
        }
        Divider()
        NoteMenuItems(note: note, folders: folders)
    }

    private var snapshot: NoteExporter.Snapshot {
        NoteExporter.Snapshot(title: note.displayTitle, date: note.createdAt, duration: note.duration, content: note.content ?? NoteContent())
    }

    private var exportMarkdown: String {
        guard note.editedMarkdown != nil else { return NoteExporter.markdown(snapshot) }
        let body = NoteMarkdown.portable(text).trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = note.content?.summary.map { "> \($0)\n\n" } ?? ""
        return "# \(note.displayTitle)\n\n*\(NoteExporter.metadata(snapshot))*\n\n\(summary)\(body)\n"
    }

    private var exportPlainText: String {
        guard note.editedMarkdown != nil else { return NoteExporter.plainText(snapshot) }
        let body = NoteMarkdown.plainText(NoteMarkdown.portable(text))
        let summary = note.content?.summary.map { "\($0)\n\n" } ?? ""
        return "\(note.displayTitle)\n\(NoteExporter.metadata(snapshot))\n\n\(summary)\(body)\n"
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func saveMarkdownFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = note.displayTitle
            .replacing(/[\/:\\?%*|"<>]/, with: "-")
            .trimmingCharacters(in: .whitespaces) + ".md"
        let markdown = exportMarkdown
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
