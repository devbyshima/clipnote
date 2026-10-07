import Foundation

/// Markdown and plain-text versions of a note, for copying and exporting.
nonisolated enum NoteExporter {
    struct Snapshot: Sendable {
        var title: String
        var date: Date
        var duration: TimeInterval
        var content: NoteContent
    }

    static func markdown(_ note: Snapshot) -> String {
        var out = "# \(note.title)\n\n"
        out += "*\(metadata(note))*\n\n"
        if let notice = note.content.notice { out += "> **Note:** \(notice)\n\n" }
        if let summary = note.content.summary { out += "> \(summary)\n\n" }
        if !note.content.keyPoints.isEmpty {
            out += "## Key points\n\n"
            out += note.content.keyPoints.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        for item in Timeline.sections(of: note.content) {
            if let heading = item.heading { out += "## \(heading)\n\n" }
            for entry in item.entries {
                switch entry {
                case .paragraph(let paragraph):
                    out += "**\(TimeFormat.clock(paragraph.start))** \(paragraph.text)\n\n"
                case .screen(let moment):
                    out += "> **On screen at \(TimeFormat.clock(moment.start))**\n"
                    out += moment.lines.map { "> \($0)" }.joined(separator: "  \n") + "\n\n"
                }
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    static func plainText(_ note: Snapshot) -> String {
        var out = "\(note.title)\n\(metadata(note))\n\n"
        if let summary = note.content.summary { out += "\(summary)\n\n" }
        if !note.content.keyPoints.isEmpty {
            out += note.content.keyPoints.map { "• \($0)" }.joined(separator: "\n") + "\n\n"
        }
        for item in Timeline.sections(of: note.content) {
            if let heading = item.heading { out += "\(heading)\n\n" }
            for entry in item.entries {
                switch entry {
                case .paragraph(let paragraph):
                    out += "[\(TimeFormat.clock(paragraph.start))] \(paragraph.text)\n\n"
                case .screen(let moment):
                    out += "On screen at \(TimeFormat.clock(moment.start)):\n"
                    out += moment.lines.map { "  \($0)" }.joined(separator: "\n") + "\n\n"
                }
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    static func metadata(_ note: Snapshot) -> String {
        var parts = [note.date.formatted(date: .abbreviated, time: .omitted)]
        if note.duration > 0 { parts.append(TimeFormat.duration(note.duration)) }
        if let code = note.content.language,
           let name = Locale.current.localizedString(forLanguageCode: code) {
            parts.append(name)
        }
        return parts.joined(separator: " · ")
    }
}

/// A note's sections with on-screen text placed among the paragraphs at the
/// moment it appeared.
nonisolated enum Timeline {
    enum Entry: Identifiable, Equatable {
        case paragraph(Paragraph)
        case screen(ScreenMoment)

        var id: UUID {
            switch self {
            case .paragraph(let p): p.id
            case .screen(let m): m.id
            }
        }

        var start: TimeInterval {
            switch self {
            case .paragraph(let p): p.start
            case .screen(let m): m.start
            }
        }

        var rank: Int {
            if case .screen = self { 0 } else { 1 }
        }
    }

    struct Section: Identifiable, Equatable {
        var id: UUID
        /// Index into `NoteContent.sections`, nil for on-screen text with no transcript.
        var sectionIndex: Int?
        var heading: String?
        var entries: [Entry]
    }

    static func sections(of content: NoteContent) -> [Section] {
        guard !content.sections.isEmpty else {
            guard !content.screenMoments.isEmpty else { return [] }
            return [Section(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                            sectionIndex: nil, heading: "On-screen text",
                            entries: content.screenMoments.map(Entry.screen))]
        }
        var moments = content.screenMoments.sorted { $0.start < $1.start }[...]
        return content.sections.enumerated().map { index, section in
            let isLast = index == content.sections.count - 1
            let nextStart = isLast ? .infinity : content.sections[index + 1].start
            var mine: [ScreenMoment] = []
            while let moment = moments.first, moment.start < nextStart {
                mine.append(moment)
                moments.removeFirst()
            }
            // A slide shown just as a paragraph begins goes before it.
            let entries = (section.paragraphs.map(Entry.paragraph) + mine.map(Entry.screen))
                .sorted { ($0.start, $0.rank) < ($1.start, $1.rank) }
            return Section(id: section.id, sectionIndex: index, heading: section.heading, entries: entries)
        }
    }
}
