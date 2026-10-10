import AppKit
import AVFoundation
import ImageIO
import SwiftUI

/// The right pane while a note's media is in the middle: what the media is,
/// where it lives, and its folder.
struct InspectorView: View {
    @Environment(Navigator.self) private var navigator
    @AppStorage("showMedia") private var showRightPane = true
    @Bindable var note: Note
    let item: Int?
    let media: NoteMedia
    let folders: [Folder]

    @State private var details = MediaDetails()

    private var items: [GalleryItem] { media.items(for: note) }

    /// The media and its info opened from the note, its frames or the
    /// media pane, so the way out is back there, with the middle; with
    /// nowhere to go back to, the pane closes.
    private var leave: InspectorHeader.Leave {
        guard let previous = navigator.previous else { return .close { showRightPane = false } }
        let help: String = switch previous {
        case .note: "Back to the note (⌘[)"
        case .gallery: note.kind == .pictures ? "Back to the pictures (⌘[)" : "Back to the frames (⌘[)"
        case .media: "Back (⌘[)"
        case .home: "Back to Home (⌘[)"
        case .folder: "Back to the folder (⌘[)"
        }
        return .back(help) { navigator.goBack() }
    }

    /// The frame or picture described, if it's one image rather than the note's media.
    private var shownItem: GalleryItem? {
        guard let item, items.indices.contains(item) else { return nil }
        return items[item]
    }

    var body: some View {
        VStack(spacing: 0) {
            InspectorHeader(title: "Info", leave: leave)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let shownItem {
                        Text(shownItem.title)
                            .font(.system(size: 15, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 16)
                    } else {
                        EditableTitle(note: note)
                            .padding(.bottom, 16)
                    }
                    rows
                    InspectorSection(title: "Folder") { FolderChips(note: note, folders: folders) }
                    if let shownItem, !shownItem.lines.isEmpty {
                        InspectorSection(title: "Text on screen") {
                            Text(shownItem.lines.joined(separator: "\n"))
                                .font(.system(size: 13))
                                .lineSpacing(3)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.never)

            InspectorBottomBar(note: note, copyHelp: shownItem == nil ? "Copy the note" : "Copy the image") {
                if let shownItem, let image = ThumbnailCache.image(at: shownItem.imageURL) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([image])
                } else {
                    copyString(note.markdown)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background, ignoresSafeAreaEdges: .top)
        .task(id: "\(note.id)-\(item ?? -1)-\(note.contentData?.count ?? 0)") {
            details = await MediaDetails.load(for: note, item: shownItem, pictureIndex: pictureIndex)
        }
    }

    /// The index into the note's pictures of the picture shown, for its file.
    private var pictureIndex: Int? {
        guard note.kind == .pictures else { return nil }
        guard let shownItem else { return 0 }
        return note.content?.pictures.firstIndex { $0.id == shownItem.id }
    }

    @ViewBuilder
    private var rows: some View {
        VStack(alignment: .leading, spacing: 11) {
            InspectorRow("Type") { TypePill(label: typeLabel) }
            if let shownItem, let time = shownItem.time {
                InspectorRow("On screen") {
                    HStack(spacing: 8) {
                        Text(TimeFormat.clock(time)).monospacedDigit()
                        Button("Play") {
                            media.play(note, at: time)
                            navigator.go(.media(note.id, item: nil))
                        }
                        .buttonStyle(.link)
                    }
                }
            }
            if shownItem == nil, note.kind == .video, note.duration > 0 {
                InspectorRow("Length") { Text(TimeFormat.clock(note.duration)) }
            }
            if let size = details.dimensions {
                InspectorRow("Dimensions") { Text("\(Int(size.width)) × \(Int(size.height))") }
            }
            if let bytes = details.fileSize {
                InspectorRow("Size") { Text(bytes.formatted(.byteCount(style: .file))) }
            }
            InspectorRow("Created") { Text(note.createdAt.formatted(date: .abbreviated, time: .shortened)) }
            if let code = note.content?.language, let name = Locale.current.localizedString(forLanguageCode: code) {
                InspectorRow("Language") { Text(name) }
            }
            if let path = details.path {
                InspectorRow("On this Mac") {
                    HStack(spacing: 6) {
                        Text(path)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer(minLength: 4)
                        InspectorIconButton(symbol: "doc.on.doc", help: "Copy the path") { copyString(path) }
                        InspectorIconButton(symbol: "folder", help: "Show in Finder") { note.revealSource() }
                    }
                }
            }
            InspectorRow("Source") {
                Text(note.sourceName)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .font(.system(size: 13))
    }

    private var typeLabel: String {
        guard let shownItem else {
            return note.kind == .pictures ? "Pictures" : (media.player.hasVideo ? "Video" : "Audio")
        }
        return shownItem.time != nil ? "Frame" : "Picture"
    }
}

/// The right pane beside a note when its Info is on: a preview of the note,
/// its details, its folder and its summary.
struct NoteInfoView: View {
    @Environment(Navigator.self) private var navigator
    @Bindable var note: Note
    let folders: [Folder]

    private var plainText: String { NoteMarkdown.plainText(note.markdown) }

    @AppStorage("showMedia") private var showRightPane = true

    /// Opened over the note's media, back to it; opened into a hidden pane,
    /// or for a note with no media, closing the pane.
    private var leave: InspectorHeader.Leave {
        if navigator.noteInfoReturnsToMedia, note.kind != .text {
            let media = switch note.mediaKind {
            case .audio: "recording"
            case .pictures: "pictures"
            default: "video"
            }
            return .back("Back to the \(media)") { navigator.showsNoteInfo = false }
        }
        return .close {
            navigator.showsNoteInfo = false
            showRightPane = false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            InspectorHeader(title: "Note info", leave: leave)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    preview
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 22)
                    EditableTitle(note: note)
                        .padding(.bottom, 16)
                    rows
                    InspectorSection(title: "Folder") { FolderChips(note: note, folders: folders) }
                    if let summary = note.content?.summary, !summary.isEmpty {
                        InspectorSection(title: "Summary") { SummaryBullets(summary: summary) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.never)

            InspectorBottomBar(note: note, copyHelp: "Copy the note") { copyString(note.markdown) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background, ignoresSafeAreaEdges: .top)
    }

    /// A small card with the start of the note, as in a file preview.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(note.displayTitle)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2)
            Text(String(plainText.prefix(500)))
                .font(.system(size: 8.5))
                .foregroundStyle(Palette.textSecondary)
                .lineSpacing(1)
        }
        .padding(12)
        .frame(width: 180, height: 136, alignment: .topLeading)
        .clipped()
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
        .shadow(color: Palette.shadow, radius: 4, y: 1)
    }

    private var madeFrom: String {
        switch note.mediaKind {
        case .pictures: note.pictureBookmarks.count == 1 ? "1 picture" : "\(note.pictureBookmarks.count) pictures"
        case .text: "Written in Ovyl"
        case .audio: note.duration > 0 ? "\(TimeFormat.clock(note.duration)) audio" : "Audio"
        case .video: note.duration > 0 ? "\(TimeFormat.clock(note.duration)) video" : "Video"
        }
    }

    @ViewBuilder
    private var rows: some View {
        let content = note.content
        let words = plainText.split(whereSeparator: \.isWhitespace).count
        VStack(alignment: .leading, spacing: 11) {
            InspectorRow("Type") { TypePill(label: "Note") }
            InspectorRow("Made from") {
                Text(madeFrom)
            }
            InspectorRow("Created") { Text(note.createdAt.formatted(date: .abbreviated, time: .shortened)) }
            InspectorRow("Updated") {
                Text((note.updatedAt ?? note.createdAt).formatted(.relative(presentation: .named)))
            }
            InspectorRow("Length") {
                Text("\(words.formatted()) words · \(max(1, Int((Double(words) / 230).rounded()))) min read")
            }
            if let code = content?.language, let name = Locale.current.localizedString(forLanguageCode: code) {
                InspectorRow("Language") { Text(name) }
            }
            if let engine = content?.engine {
                InspectorRow("Transcript") { Text(engine) }
            }
            if let content, !content.music.isEmpty {
                InspectorRow("Music") { Text("Left out") }
            }
            if content?.formattedWithAI == true {
                InspectorRow("Written with") { Text("Apple Intelligence") }
            }
            if note.editedMarkdown != nil {
                InspectorRow("Edited") { Text("Yes") }
            }
            InspectorRow("Source") {
                HStack(spacing: 6) {
                    Text(note.sourceName)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    InspectorIconButton(symbol: "folder", help: "Show in Finder") { note.revealSource() }
                }
            }
        }
        .font(.system(size: 13))
    }
}

/// The summary as bullet points, a sentence each.
struct SummaryBullets: View {
    let summary: String

    private var sentences: [String] {
        var result: [String] = []
        summary.enumerateSubstrings(in: summary.startIndex..., options: .bySentences) { sentence, _, _, _ in
            if let sentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty {
                result.append(sentence)
            }
        }
        return result.isEmpty ? [summary] : result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(sentences.enumerated()), id: \.offset) { _, sentence in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundStyle(Palette.textSecondary)
                    Text(sentence)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.system(size: 13))
        .textSelection(.enabled)
    }
}

// MARK: - Shared parts

/// The inspector's top row: its name and a close button.
/// The top of a view in the right pane: first a way out, then the title.
/// A view opened from another goes back to it; the pane's first view
/// closes the pane. Never both, so the way out says where it leads.
struct InspectorHeader: View {
    enum Leave {
        /// Back to what this opened from, with help naming it.
        case back(String, () -> Void)
        case close(() -> Void)
    }

    let title: String
    let leave: Leave

    var body: some View {
        HStack(spacing: 10) {
            PillGroup {
                switch leave {
                case .back(let help, let action):
                    PillButton(symbol: "chevron.left", help: help, action: action)
                case .close(let action):
                    PillButton(symbol: "xmark", help: "Close (⌘P)", action: action)
                }
            }
            Text(title)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: MainWindowStyler.barHeight)
        .background(WindowDragHandle())
    }
}

/// A label and its value.
struct InspectorRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: Value

    init(_ label: String, @ViewBuilder value: () -> Value) {
        self.label = label
        self.value = value()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 92, alignment: .leading)
            value
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A titled part of the inspector, under a rule.
struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Palette.border).frame(height: 1).padding(.vertical, 8)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textSecondary)
            content
        }
        .padding(.top, 8)
    }
}

struct TypePill: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(Palette.fill))
    }
}

struct InspectorIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.textSecondary)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// The note's title with a pencil to rename it.
struct EditableTitle: View {
    @Environment(ProcessingCenter.self) private var center
    @Bindable var note: Note
    @State private var isRenaming = false
    @State private var draft = ""

    var body: some View {
        if isRenaming {
            TextField("Title", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .onSubmit(commit)
                .onExitCommand { isRenaming = false }
        } else {
            HStack(alignment: .firstTextBaseline) {
                Text(note.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button {
                    draft = note.displayTitle
                    isRenaming = true
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Rename")
            }
        }
    }

    private func commit() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, title != note.displayTitle {
            note.title = title
            note.titleEdited = true
            note.updatedAt = .now
            center.save()
        }
        isRenaming = false
    }
}

/// The note's folder as a chip with a remove button, and a menu to move it.
struct FolderChips: View {
    @Environment(ProcessingCenter.self) private var center
    let note: Note
    let folders: [Folder]

    var body: some View {
        HStack(spacing: 8) {
            if let folder = folders.first(where: { $0.id == note.folderID }) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").foregroundStyle(folder.color)
                    Text(folder.name).lineLimit(1)
                    Button { center.move([note.id], to: nil) } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.textSecondary)
                    .help("Take it out of the folder")
                }
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Palette.fill))
            }
            Menu {
                ForEach(folders) { folder in
                    Button(folder.name) { center.move([note.id], to: folder.id) }
                        .disabled(note.folderID == folder.id)
                }
                if !folders.isEmpty { Divider() }
                Button("New Folder") { center.createFolder() }
            } label: {
                Label(note.folderID == nil ? "Add" : "Move", systemImage: "plus")
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Palette.fill))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

/// Copy, Show in Finder and Delete, at the foot of the inspector.
struct InspectorBottomBar: View {
    @Environment(Navigator.self) private var navigator
    let note: Note
    let copyHelp: String
    let copy: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            circleButton("doc.on.doc", copyHelp, action: copy)
            circleButton("folder", "Show in Finder") { note.revealSource() }
            Spacer()
            circleButton("trash", "Delete the note") { navigator.pendingDelete = note.id }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: 1) }
    }

    private func circleButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.textPrimary.opacity(0.72))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Palette.surface))
                .overlay(Circle().strokeBorder(Palette.border, lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help(help)
    }
}

@MainActor
func copyString(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

/// Facts about a note's media read from its files.
struct MediaDetails {
    var fileSize: Int64?
    var dimensions: CGSize?
    /// Where the original file is, for "On this Mac".
    var path: String?

    @MainActor
    static func load(for note: Note, item: GalleryItem?, pictureIndex: Int?) async -> MediaDetails {
        var details = MediaDetails()
        let original: URL? = if let pictureIndex { note.resolvePicture(at: pictureIndex) } else { note.resolveSource() }
        if let original {
            let accessing = original.startAccessingSecurityScopedResource()
            defer { if accessing { original.stopAccessingSecurityScopedResource() } }
            details.path = original.path(percentEncoded: false)
            if item == nil || pictureIndex != nil {
                details.fileSize = (try? original.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
                if note.kind == .video {
                    let asset = AVURLAsset(url: original)
                    if let track = try? await asset.loadTracks(withMediaType: .video).first,
                       let loaded = try? await track.load(.naturalSize, .preferredTransform) {
                        let size = loaded.0.applying(loaded.1)
                        details.dimensions = CGSize(width: abs(size.width), height: abs(size.height))
                    }
                } else {
                    details.dimensions = pixelSize(of: original)
                }
            }
        }
        if let item, note.kind == .video {
            details.fileSize = (try? item.imageURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
            details.dimensions = pixelSize(of: item.imageURL)
        }
        return details
    }

    private static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: width, height: height)
    }
}
