import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A finished note, laid out for reading: video, title, summary, key points,
/// then the transcript in sections with on-screen text where it appeared.
struct NoteDocumentView: View {
    @Environment(ProcessingCenter.self) private var center
    @Bindable var note: Note
    @State private var content = NoteContent()
    @State private var timeline: [Timeline.Section] = []
    @State private var player = PlayerModel()
    @State private var isEditing = false
    @State private var draftTitle = ""
    @State private var isLocating = false
    @AppStorage("showsVideo") private var showsVideo = true

    /// Room on the left for timestamps that hang outside the text column.
    private let gutter: CGFloat = 64

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if showsVideo {
                    videoArea.padding(.bottom, 32)
                }
                if isEditing { editor } else { reader }
            }
            .frame(maxWidth: 740, alignment: .leading)
            .padding(.leading, gutter + 24)
            .padding(.trailing, 48)
            .padding(.top, 30)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .navigationTitle(note.displayTitle)
        .toolbar { toolbar }
        .onAppear {
            reloadContent()
            if showsVideo { player.load(note) }
        }
        .onDisappear {
            if isEditing { commitEdits() }
            player.unload()
        }
        .onChange(of: note.contentData) {
            if !isEditing { reloadContent() }
        }
        .onChange(of: showsVideo) { _, shows in
            if shows { player.load(note) } else { player.unload() }
        }
        .fileImporter(isPresented: $isLocating, allowedContentTypes: [.audiovisualContent]) { result in
            guard case .success(let url) = result else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            note.sourceBookmark = try? Note.bookmark(for: url)
            center.save()
            player.reload(note)
        }
    }

    // MARK: Reading

    @ViewBuilder
    private var reader: some View {
        Text(note.displayTitle)
            .font(.system(size: 34, weight: .bold))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)

        metadata.padding(.top, 10)

        if let notice = content.notice {
            Label(notice, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.primary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.yellow.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.top, 20)
        }

        if let summary = content.summary {
            VStack(alignment: .leading, spacing: 8) {
                Text("Summary")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(Color.accentColor)
                Text(summary)
                    .font(.system(size: 15.5))
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 26)
        }

        if !content.keyPoints.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Key Points")
                    .font(.title3.weight(.semibold))
                    .padding(.bottom, 2)
                ForEach(Array(content.keyPoints.enumerated()), id: \.offset) { _, point in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Image(systemName: "circle.fill"))
                            .font(.system(size: 6))
                            .baselineOffset(3)
                            .foregroundStyle(Color.accentColor)
                        Text(point)
                            .font(.system(size: 15))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 28)
        }

        if timeline.isEmpty {
            Text("No speech or on-screen text was found in this video.")
                .foregroundStyle(.secondary)
                .padding(.top, 32)
        }

        ForEach(timeline) { section in
            VStack(alignment: .leading, spacing: 16) {
                if let heading = section.heading {
                    Text(heading)
                        .font(.system(size: 22, weight: .bold))
                        .textSelection(.enabled)
                        .padding(.bottom, 2)
                }
                ForEach(section.entries) { entry in
                    switch entry {
                    case .paragraph(let paragraph):
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            TimestampButton(seconds: paragraph.start) { play(at: paragraph.start) }
                                .frame(width: gutter - 12, alignment: .trailing)
                            Text(paragraph.text)
                                .font(.system(size: 15))
                                .lineSpacing(5)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.leading, -gutter)
                    case .screen(let moment):
                        ScreenMomentCard(moment: moment, folder: note.thumbnailsFolder) { play(at: moment.start) }
                    }
                }
            }
            .padding(.top, 36)
        }
    }

    private var metadata: some View {
        FlowLayout(spacing: 16, lineSpacing: 6) {
            Label(note.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
            if note.duration > 0 {
                Label(TimeFormat.duration(note.duration), systemImage: "clock")
            }
            if let code = content.language, let name = Locale.current.localizedString(forLanguageCode: code) {
                Label(name, systemImage: "globe")
            }
            if let engine = content.engine {
                Label(engine, systemImage: "waveform")
            }
            if content.formattedWithAI {
                Label("Apple Intelligence", systemImage: "sparkles")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    // MARK: Video

    @ViewBuilder
    private var videoArea: some View {
        if player.isUnavailable {
            HStack(spacing: 12) {
                Image(systemName: "video.slash")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Video not found").font(.headline)
                    Text("\(note.sourceName) was moved or deleted. The note is safe.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Locate…") { isLocating = true }
            }
            .padding(16)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else if let avPlayer = player.player {
            PlayerView(player: avPlayer)
                .frame(height: player.hasVideo ? nil : 56)
                .aspectRatio(player.hasVideo ? 16 / 9 : nil, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 440)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
    }

    private func play(at seconds: TimeInterval) {
        if !showsVideo {
            showsVideo = true
            player.load(note)
        }
        player.seek(to: seconds)
    }

    // MARK: Editing

    @ViewBuilder
    private var editor: some View {
        TextField("Title", text: $draftTitle, axis: .vertical)
            .font(.system(size: 34, weight: .bold))
            .textFieldStyle(.plain)
            .editableField()

        VStack(alignment: .leading, spacing: 8) {
            Text("Summary").font(.caption.weight(.bold)).textCase(.uppercase).foregroundStyle(.secondary)
            TextField("Add a summary", text: Binding(
                get: { content.summary ?? "" },
                set: { content.summary = $0 }
            ), axis: .vertical)
            .font(.system(size: 15.5))
            .textFieldStyle(.plain)
            .editableField()
        }
        .padding(.top, 24)

        VStack(alignment: .leading, spacing: 8) {
            Text("Key Points").font(.caption.weight(.bold)).textCase(.uppercase).foregroundStyle(.secondary)
            ForEach(content.keyPoints.indices, id: \.self) { index in
                TextField("Key point", text: $content.keyPoints[index], axis: .vertical)
                    .font(.system(size: 15))
                    .textFieldStyle(.plain)
                    .editableField()
            }
            Button("Add Key Point", systemImage: "plus") { content.keyPoints.append("") }
                .buttonStyle(.borderless)
        }
        .padding(.top, 24)

        ForEach($content.sections) { $section in
            VStack(alignment: .leading, spacing: 10) {
                TextField("Heading", text: $section.heading)
                    .font(.system(size: 22, weight: .bold))
                    .textFieldStyle(.plain)
                    .editableField()
                ForEach($section.paragraphs) { $paragraph in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(TimeFormat.clock(paragraph.start))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: gutter - 12, alignment: .trailing)
                        TextField("", text: $paragraph.text, axis: .vertical)
                            .font(.system(size: 15))
                            .textFieldStyle(.plain)
                            .editableField()
                    }
                    .padding(.leading, -gutter)
                }
            }
            .padding(.top, 32)
        }
    }

    private func toggleEditing() {
        if isEditing {
            commitEdits()
        } else {
            draftTitle = note.displayTitle
            content = note.content ?? content
        }
        withAnimation(.snappy) { isEditing.toggle() }
    }

    private func commitEdits() {
        content.summary = content.summary.flatMap { $0.trimmed.isEmpty ? nil : $0.trimmed }
        content.keyPoints = content.keyPoints.map(\.trimmed).filter { !$0.isEmpty }
        for index in content.sections.indices {
            content.sections[index].heading = content.sections[index].heading.trimmed
            content.sections[index].paragraphs.removeAll { $0.text.trimmed.isEmpty }
        }
        content.sections.removeAll { $0.paragraphs.isEmpty && $0.heading.isEmpty }
        let title = draftTitle.trimmed
        if !title.isEmpty, title != note.title {
            note.title = title
            note.titleEdited = true
        }
        note.content = content
        center.save()
        timeline = Timeline.sections(of: content)
    }

    private func reloadContent() {
        content = note.content ?? NoteContent()
        timeline = Timeline.sections(of: content)
    }

    // MARK: Toolbar and export

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: $showsVideo) {
                Label("Show Video", systemImage: "play.rectangle")
            }
            .help(showsVideo ? "Hide the video" : "Show the video")

            Button(isEditing ? "Done" : "Edit", systemImage: isEditing ? "checkmark" : "pencil") {
                toggleEditing()
            }
            .help(isEditing ? "Finish editing" : "Edit the note")

            Menu {
                Button("Copy as Markdown", systemImage: "doc.on.doc") { copy(NoteExporter.markdown(snapshot)) }
                Button("Copy as Plain Text", systemImage: "doc.plaintext") { copy(NoteExporter.plainText(snapshot)) }
                Divider()
                Button("Export Markdown File…", systemImage: "square.and.arrow.down") { exportMarkdown() }
                ShareLink("Share…", item: NoteExporter.markdown(snapshot))
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Copy or export this note")
        }
    }

    private var snapshot: NoteExporter.Snapshot {
        NoteExporter.Snapshot(title: note.displayTitle, date: note.createdAt, duration: note.duration, content: content)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = note.displayTitle
            .replacing(/[\/:\\?%*|"<>]/, with: "-")
            .trimmingCharacters(in: .whitespaces) + ".md"
        let markdown = NoteExporter.markdown(snapshot)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

private extension View {
    func editableField() -> some View {
        padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct TimestampButton: View {
    let seconds: TimeInterval
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(TimeFormat.clock(seconds))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(isHovered ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovered = $0 }
        .help("Play from \(TimeFormat.clock(seconds))")
    }
}

struct ScreenMomentCard: View {
    let moment: ScreenMoment
    let folder: URL
    let play: () -> Void
    @State private var isExpanded = false

    private let collapsedLineCount = 10

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if let name = moment.thumbnail, let image = ThumbnailCache.image(at: folder.appending(path: name)) {
                Button(action: play) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 168)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(.separator)
                        }
                }
                .buttonStyle(.plain)
                .help("Play from \(TimeFormat.clock(moment.start))")
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "text.viewfinder")
                    Text("On screen")
                    TimestampButton(seconds: moment.start, action: play)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

                let lines = isExpanded ? moment.lines : Array(moment.lines.prefix(collapsedLineCount))
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(line == moment.title ? .system(size: 14.5, weight: .semibold) : .system(size: 13.5))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if moment.lines.count > collapsedLineCount {
                    Button(isExpanded ? "Show less" : "Show all \(moment.lines.count) lines") {
                        withAnimation(.snappy) { isExpanded.toggle() }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator.opacity(0.6))
        }
    }
}

@MainActor
enum ThumbnailCache {
    private static let cache = NSCache<NSURL, NSImage>()

    static func image(at url: URL) -> NSImage? {
        if let image = cache.object(forKey: url as NSURL) { return image }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// Lays out children left to right, wrapping onto new lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 12
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
