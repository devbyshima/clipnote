import Foundation
import FoundationModels
import SwiftData

/// A tool the assistant can call, described once for every model.
nonisolated struct ToolSpec: Sendable {
    struct Parameter: Sendable {
        enum Kind: Sendable { case string, number }
        let name: String
        let kind: Kind
        let description: String
        var required = true
    }

    let name: String
    let description: String
    let parameters: [Parameter]

    /// The JSON Schema Claude reads.
    var inputSchema: JSONValue {
        var properties: [String: JSONValue] = [:]
        for parameter in parameters {
            properties[parameter.name] = .object([
                "type": .string(parameter.kind == .string ? "string" : "number"),
                "description": .string(parameter.description),
            ])
        }
        return .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(parameters.filter(\.required).map { .string($0.name) }),
        ])
    }

    /// The schema Apple's models read.
    func generationSchema() throws -> GenerationSchema {
        let properties = parameters.map { parameter in
            DynamicGenerationSchema.Property(
                name: parameter.name,
                description: parameter.description,
                schema: parameter.kind == .string ? DynamicGenerationSchema(type: String.self) : DynamicGenerationSchema(type: Double.self),
                isOptional: !parameter.required
            )
        }
        return try GenerationSchema(root: DynamicGenerationSchema(name: name, description: description, properties: properties), dependencies: [])
    }
}

/// A library tool for Apple's models: arguments arrive as generated
/// content and are handed to the same code Claude's calls go through.
nonisolated struct AppleLibraryTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema
    let run: @Sendable (JSONValue) async -> String

    init(spec: ToolSpec, run: @escaping @Sendable (JSONValue) async -> String) throws {
        name = spec.name
        description = spec.description
        parameters = try spec.generationSchema()
        self.run = run
    }

    @concurrent func call(arguments: GeneratedContent) async throws -> String {
        let input = (try? JSONDecoder().decode(JSONValue.self, from: Data(arguments.jsonString.utf8))) ?? .object([:])
        return await run(input)
    }
}

/// What the assistant can do in the library: find and read notes,
/// transcripts and on-screen text, and make, rewrite, rename, move and open
/// notes. Every change is recorded as a step that can be undone.
@MainActor
final class LibraryTools {
    let center: ProcessingCenter
    /// How much text one read returns, sized to the model's context.
    let readBudget: Int
    private let index: SearchIndex
    private let catchUp: () async -> Void
    var onStep: (ChatStep) -> Void = { _ in }
    var openNote: (UUID) -> Void = { _ in }

    init(center: ProcessingCenter, readBudget: Int, index: SearchIndex = .shared, catchUp: (() async -> Void)? = nil) {
        self.center = center
        self.readBudget = readBudget
        self.index = index
        self.catchUp = catchUp ?? { await LibraryIndexer.shared.catchUp(center) }
    }

    // MARK: Specs

    static let specs: [ToolSpec] = [
        ToolSpec(name: "search_library", description: "Find notes and the passages in them (speech with its time, text on screen, picture text, edited text) that match words or meaning. Start here when you don't know which note holds something.", parameters: [
            .init(name: "query", kind: .string, description: "What to look for, in a few words."),
        ]),
        ToolSpec(name: "list_notes", description: "List notes, newest first, with their ids, kinds, lengths and folders.", parameters: [
            .init(name: "folder", kind: .string, description: "Only notes in the folder with this name.", required: false),
            .init(name: "limit", kind: .number, description: "How many notes, 20 if not given.", required: false),
        ]),
        ToolSpec(name: "list_folders", description: "List the folders and how many notes each holds.", parameters: []),
        ToolSpec(name: "read_note", description: "Read a note's text, as the user sees it, in parts. Read every part before rewriting or combining a note.", parameters: [
            .init(name: "note", kind: .string, description: "The note's id or title."),
            .init(name: "part", kind: .number, description: "Which part, from 1; 1 if not given.", required: false),
        ]),
        ToolSpec(name: "read_transcript", description: "Read what was said in a video or audio note between two times, line by line with times.", parameters: [
            .init(name: "note", kind: .string, description: "The note's id or title."),
            .init(name: "from", kind: .string, description: "Start time like 4:30, or seconds; the start if not given.", required: false),
            .init(name: "to", kind: .string, description: "End time like 9:00, or seconds; the end if not given.", required: false),
        ]),
        ToolSpec(name: "read_frames", description: "Read the text that appeared on screen in a video (slides, titles, captions), with times, or the text in each picture of a pictures note.", parameters: [
            .init(name: "note", kind: .string, description: "The note's id or title."),
        ]),
        ToolSpec(name: "create_note", description: "Make a new note of Markdown text, for example one that combines other notes. The originals are kept.", parameters: [
            .init(name: "title", kind: .string, description: "The new note's title."),
            .init(name: "markdown", kind: .string, description: "The whole note in Markdown, without the title as a heading."),
            .init(name: "folder", kind: .string, description: "A folder name to put it in; made if it doesn't exist.", required: false),
        ]),
        ToolSpec(name: "update_note", description: "Replace a note's whole text with new Markdown, to restructure or rewrite it. Keep every fact the note had unless asked otherwise.", parameters: [
            .init(name: "note", kind: .string, description: "The note's id or title."),
            .init(name: "markdown", kind: .string, description: "The note's new text in Markdown, without the title as a heading."),
        ]),
        ToolSpec(name: "append_to_note", description: "Add Markdown to the end of a note.", parameters: [
            .init(name: "note", kind: .string, description: "The note's id or title."),
            .init(name: "markdown", kind: .string, description: "The Markdown to add."),
        ]),
        ToolSpec(name: "rename_note", description: "Give a note a new title.", parameters: [
            .init(name: "note", kind: .string, description: "The note's id or title."),
            .init(name: "title", kind: .string, description: "The new title."),
        ]),
        ToolSpec(name: "move_note", description: "Put a note in a folder, made if it doesn't exist. An empty folder name takes it out of any folder.", parameters: [
            .init(name: "note", kind: .string, description: "The note's id or title."),
            .init(name: "folder", kind: .string, description: "The folder's name, or empty for none."),
        ]),
        ToolSpec(name: "open_note", description: "Open a note in the window. Only when the user asks to open, show or go to a note; to answer questions, read it instead.", parameters: [
            .init(name: "note", kind: .string, description: "The note's id or title."),
        ]),
    ]

    func appleTools() -> [any Tool] {
        Self.specs.compactMap { spec in
            try? AppleLibraryTool(spec: spec) { [weak self] input in
                await self?.run(spec.name, input) ?? "The library isn't available."
            }
        }
    }

    // MARK: Running

    func run(_ name: String, _ input: JSONValue) async -> String {
        switch name {
        case "search_library": return await search(input["query"]?.string ?? "")
        case "list_notes": return listNotes(folder: input["folder"]?.string, limit: input["limit"]?.number.map(Int.init) ?? 20)
        case "list_folders": return listFolders()
        case "read_note": return readNote(input["note"]?.string ?? "", part: input["part"]?.number.map(Int.init) ?? 1)
        case "read_transcript": return readTranscript(input["note"]?.string ?? "", from: input["from"]?.string, to: input["to"]?.string)
        case "read_frames": return readFrames(input["note"]?.string ?? "")
        case "create_note": return createNote(title: input["title"]?.string ?? "", markdown: input["markdown"]?.string ?? "", folder: input["folder"]?.string)
        case "update_note": return updateNote(input["note"]?.string ?? "", markdown: input["markdown"]?.string ?? "")
        case "append_to_note": return appendToNote(input["note"]?.string ?? "", markdown: input["markdown"]?.string ?? "")
        case "rename_note": return renameNote(input["note"]?.string ?? "", title: input["title"]?.string ?? "")
        case "move_note": return moveNote(input["note"]?.string ?? "", folder: input["folder"]?.string ?? "")
        case "open_note": return open(input["note"]?.string ?? "")
        default: return "There's no tool called \(name)."
        }
    }

    // MARK: Finding

    private func search(_ query: String) async -> String {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return "Say what to look for." }
        await catchUp()
        let hits = await index.find(query, limit: 14)
        onStep(ChatStep(kind: .searched, summary: "Searched for “\(query)”"))
        guard !hits.isEmpty else { return "Nothing in the library matches “\(query)”." }
        var lines: [String] = []
        var order: [UUID] = []
        var grouped: [UUID: [SearchHit]] = [:]
        for hit in hits {
            if grouped[hit.noteID] == nil { order.append(hit.noteID) }
            grouped[hit.noteID, default: []].append(hit)
        }
        for id in order {
            guard let note = center.note(with: id) else { continue }
            lines.append(describe(note))
            for hit in grouped[id] ?? [] where hit.kind != .title {
                lines.append("  - \(place(of: hit)): \(Self.oneLine(hit.plainSnippet, limit: 260))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func listNotes(folder: String?, limit: Int) -> String {
        var notes = allNotes()
        if let folder, !folder.isEmpty {
            guard let match = findFolder(folder) else { return "There's no folder called “\(folder)”." }
            notes = notes.filter { $0.folderID == match.id }
        }
        onStep(ChatStep(kind: .listed, summary: folder.map { "Listed notes in \($0)" } ?? "Listed notes"))
        guard !notes.isEmpty else { return "No notes yet." }
        let shown = notes.prefix(max(1, min(limit, 80)))
        var text = shown.map(describe).joined(separator: "\n")
        if notes.count > shown.count { text += "\n(\(notes.count - shown.count) more)" }
        return text
    }

    private func listFolders() -> String {
        let folders = allFolders()
        guard !folders.isEmpty else { return "There are no folders." }
        let notes = allNotes()
        return folders.map { folder in
            "- \(folder.name): \(notes.filter { $0.folderID == folder.id }.count) notes"
        }.joined(separator: "\n")
    }

    // MARK: Reading

    private func readNote(_ ref: String, part: Int) -> String {
        guard let note = resolve(ref) else { return missing(ref) }
        guard note.status == .ready else { return "“\(note.displayTitle)” isn't ready yet: \(note.stage.isEmpty ? note.status.rawValue : note.stage)." }
        let parts = Self.split(Self.readable(note.markdown), budget: readBudget)
        let index = min(max(part, 1), parts.count) - 1
        onStep(ChatStep(kind: .read, summary: parts.count > 1 ? "Read \(note.displayTitle), part \(index + 1) of \(parts.count)" : "Read \(note.displayTitle)", noteID: note.id))
        var text = describe(note) + "\n"
        if parts.count > 1 { text += "Part \(index + 1) of \(parts.count):\n" }
        text += parts[index]
        if index + 1 < parts.count { text += "\n(Part \(index + 2) continues it.)" }
        return text
    }

    private func readTranscript(_ ref: String, from: String?, to: String?) -> String {
        guard let note = resolve(ref) else { return missing(ref) }
        guard let content = note.content, note.kind != .text else { return "“\(note.displayTitle)” has no transcript." }
        let start = from.flatMap(Self.seconds) ?? 0
        let end = to.flatMap(Self.seconds) ?? .infinity
        var lines: [String] = []
        var used = 0
        var stoppedAt: Double?
        for section in content.sections {
            for paragraph in section.paragraphs where paragraph.source != .picture && paragraph.start >= start && paragraph.start <= end {
                let line = "[\(TimeFormat.clock(paragraph.start))] \(paragraph.text)"
                if used + line.count > readBudget {
                    stoppedAt = paragraph.start
                    break
                }
                lines.append(line)
                used += line.count
            }
            if stoppedAt != nil { break }
        }
        onStep(ChatStep(kind: .read, summary: "Read what was said in \(note.displayTitle)", noteID: note.id))
        guard !lines.isEmpty else { return "Nothing was said in “\(note.displayTitle)” between those times." }
        var text = describe(note) + "\n" + lines.joined(separator: "\n")
        if let stoppedAt { text += "\n(More from \(TimeFormat.clock(stoppedAt)).)" }
        return text
    }

    private func readFrames(_ ref: String) -> String {
        guard let note = resolve(ref) else { return missing(ref) }
        guard let content = note.content else { return "“\(note.displayTitle)” has nothing on screen." }
        var lines: [String] = []
        if content.isPictures {
            for (index, picture) in content.pictures.enumerated() {
                let text = content.sections.filter { $0.picture == index }.flatMap(\.paragraphs).map(\.text).joined(separator: " ")
                lines.append("Picture \(index + 1), \(picture.name): \(text.isEmpty ? "no text" : text)")
            }
        } else {
            for moment in content.screenMoments {
                let title = moment.title.map { "\($0): " } ?? ""
                lines.append("[\(TimeFormat.clock(moment.start))] \(moment.kind == .slide ? "Frame" : "On screen") \(title)\(moment.lines.joined(separator: " / "))")
            }
            if !content.screenTitles.isEmpty {
                lines.insert("On screen throughout: \(content.screenTitles.joined(separator: " / "))", at: 0)
            }
        }
        onStep(ChatStep(kind: .read, summary: "Read the frames of \(note.displayTitle)", noteID: note.id))
        guard !lines.isEmpty else { return "No text was read off the screen in “\(note.displayTitle)”." }
        return describe(note) + "\n" + Self.split(lines.joined(separator: "\n"), budget: readBudget)[0]
    }

    // MARK: Changing

    private func createNote(title: String, markdown: String, folder: String?) -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !markdown.isEmpty else { return "A note needs a title and some text." }
        let folderID = folder.flatMap { $0.isEmpty ? nil : folderNamed($0, create: true)?.id }
        let note = center.createTextNote(title: title, markdown: Self.stripTitle(markdown, title: title), in: folderID)
        onStep(ChatStep(kind: .created, summary: "Made \(title)", noteID: note.id, undo: .removeNote(note.id)))
        return "Made the note \(describe(note))."
    }

    private func updateNote(_ ref: String, markdown: String) -> String {
        guard let note = resolve(ref) else { return missing(ref) }
        guard !markdown.isEmpty else { return "The new text is empty; nothing changed." }
        let previous = note.editedMarkdown
        note.setMarkdown(Self.stripTitle(markdown, title: note.displayTitle))
        center.save()
        onStep(ChatStep(kind: .edited, summary: "Rewrote \(note.displayTitle)", noteID: note.id, undo: .restoreText(note.id, previous: previous)))
        return "Rewrote “\(note.displayTitle)”."
    }

    private func appendToNote(_ ref: String, markdown: String) -> String {
        guard let note = resolve(ref) else { return missing(ref) }
        guard !markdown.isEmpty else { return "Nothing to add." }
        let previous = note.editedMarkdown
        let current = note.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        note.setMarkdown(current + "\n\n" + markdown.trimmingCharacters(in: .whitespacesAndNewlines) + "\n")
        center.save()
        onStep(ChatStep(kind: .edited, summary: "Added to \(note.displayTitle)", noteID: note.id, undo: .restoreText(note.id, previous: previous)))
        return "Added to “\(note.displayTitle)”."
    }

    private func renameNote(_ ref: String, title: String) -> String {
        guard let note = resolve(ref) else { return missing(ref) }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return "The new title is empty." }
        let previous = note.title
        let wasEdited = note.titleEdited
        note.title = title
        note.titleEdited = true
        center.save()
        onStep(ChatStep(kind: .renamed, summary: "Renamed \(previous) to \(title)", noteID: note.id, undo: .restoreTitle(note.id, previous: previous, wasEdited: wasEdited)))
        return "Renamed it “\(title)”."
    }

    private func moveNote(_ ref: String, folder: String) -> String {
        guard let note = resolve(ref) else { return missing(ref) }
        let previous = note.folderID
        let name = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = name.isEmpty || name.lowercased() == "none" ? nil : folderNamed(name, create: true)
        note.folderID = target?.id
        center.save()
        let summary = target.map { "Moved \(note.displayTitle) to \($0.name)" } ?? "Took \(note.displayTitle) out of its folder"
        onStep(ChatStep(kind: .moved, summary: summary, noteID: note.id, undo: .restoreFolder(note.id, previous: previous)))
        return summary + "."
    }

    private func open(_ ref: String) -> String {
        guard let note = resolve(ref) else { return missing(ref) }
        openNote(note.id)
        onStep(ChatStep(kind: .opened, summary: "Opened \(note.displayTitle)", noteID: note.id))
        return "Opened “\(note.displayTitle)”."
    }

    /// Puts a change back.
    func undo(_ record: UndoRecord) {
        switch record {
        case .removeNote(let id):
            if let note = center.note(with: id) { center.delete(note) }
        case .restoreText(let id, let previous):
            guard let note = center.note(with: id) else { return }
            note.setMarkdown(previous ?? NoteMarkdown.body(of: note.content ?? NoteContent()))
        case .restoreTitle(let id, let previous, let wasEdited):
            guard let note = center.note(with: id) else { return }
            note.title = previous
            note.titleEdited = wasEdited
        case .restoreFolder(let id, let previous):
            center.note(with: id)?.folderID = previous
        }
        center.save()
    }

    // MARK: Notes

    /// "[1a2b3c4d] “Lecture 4” · video, 52:10 · 3 Oct 2026 · in School"
    func describe(_ note: Note) -> String {
        var parts = ["[\(Self.ref(note.id))] “\(note.displayTitle)”"]
        var kind = note.mediaKind.noun
        if note.kind == .pictures {
            kind = "\(note.pictureBookmarks.count) pictures"
        } else if note.duration > 0 {
            kind += ", \(TimeFormat.clock(note.duration))"
        }
        parts.append(kind)
        parts.append(note.createdAt.formatted(date: .abbreviated, time: .omitted))
        if let id = note.folderID, let folder = allFolders().first(where: { $0.id == id }) {
            parts.append("in \(folder.name)")
        }
        if note.status != .ready { parts.append(note.status.rawValue) }
        return parts.joined(separator: " · ")
    }

    static func ref(_ id: UUID) -> String {
        String(id.uuidString.prefix(8)).lowercased()
    }

    /// A note by id (or the start of one), else by title.
    func resolve(_ ref: String) -> Note? {
        let cleaned = ref.trimmingCharacters(in: CharacterSet(charactersIn: "[] “”\"'").union(.whitespacesAndNewlines))
        guard !cleaned.isEmpty else { return nil }
        let notes = allNotes()
        let lower = cleaned.lowercased()
        if lower.count >= 6, let note = notes.first(where: { $0.id.uuidString.lowercased().hasPrefix(lower) }) {
            return note
        }
        return notes.first { $0.displayTitle.localizedCaseInsensitiveCompare(cleaned) == .orderedSame }
            ?? notes.first { $0.displayTitle.localizedStandardContains(cleaned) }
    }

    private func missing(_ ref: String) -> String {
        "There's no note “\(ref)”. Use search_library or list_notes to find it."
    }

    private func place(of hit: SearchHit) -> String {
        let time = hit.start.map { " at \(TimeFormat.clock($0))" } ?? ""
        switch hit.kind {
        case .speech: return "said\(time)"
        case .screen: return "on screen\(time)"
        case .picture: return "in a picture"
        case .summary: return "summary"
        case .text: return "text\(time)"
        case .title: return "title"
        }
    }

    private func allNotes() -> [Note] {
        (try? center.context.fetch(FetchDescriptor<Note>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
    }

    private func allFolders() -> [Folder] {
        (try? center.context.fetch(FetchDescriptor<Folder>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    private func findFolder(_ name: String) -> Folder? {
        allFolders().first { $0.name.localizedCaseInsensitiveCompare(name.trimmingCharacters(in: .whitespaces)) == .orderedSame }
    }

    private func folderNamed(_ name: String, create: Bool) -> Folder? {
        if let folder = findFolder(name) { return folder }
        guard create else { return nil }
        let folder = Folder(name: name.trimmingCharacters(in: .whitespaces), colorName: Folder.colors[allFolders().count % Folder.colors.count])
        center.context.insert(folder)
        center.save()
        return folder
    }

    // MARK: Text

    /// The note's Markdown with in-app links made plain: timestamps read
    /// as "[4:02]" and picture links as the picture's name.
    static func readable(_ markdown: String) -> String {
        markdown
            .replacing(/\[([^\]\n]*)\]\(#t=[0-9.]+\)/) { "[\($0.output.1)]" }
            .replacing(/\[([^\]\n]*)\]\(#p=[0-9]+\)/) { "[picture: \($0.output.1)]" }
    }

    /// Cuts text into parts of about `budget` characters, at paragraph
    /// breaks where it can.
    static func split(_ text: String, budget: Int) -> [String] {
        guard text.count > budget else { return [text] }
        var parts: [String] = []
        var current = ""
        for paragraph in text.components(separatedBy: "\n\n") {
            if current.count + paragraph.count + 2 > budget, !current.isEmpty {
                parts.append(current)
                current = ""
            }
            if paragraph.count > budget {
                var rest = Substring(paragraph)
                while rest.count > budget {
                    parts.append(String(rest.prefix(budget)))
                    rest = rest.dropFirst(budget)
                }
                current = String(rest)
            } else {
                current += current.isEmpty ? paragraph : "\n\n" + paragraph
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    /// Notes keep their title apart, so a leading "# Title" is dropped.
    static func stripTitle(_ markdown: String, title: String) -> String {
        var lines = markdown.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        if let first = lines.first, first.hasPrefix("# ") {
            lines.removeFirst()
            while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeFirst() }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// "4:30", "1:02:05" or "270" as seconds.
    static func seconds(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":").map { Double($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
    }

    static func oneLine(_ text: String, limit: Int) -> String {
        let flat = text.replacing("\n", with: " ")
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }
}
