import Foundation
import UniformTypeIdentifiers

/// What a note is made from, as the app shows it: a video, an audio file,
/// pictures, or text written in Ovyl.
nonisolated enum MediaKind: String, Sendable, Codable {
    case video, audio, pictures, text

    var noun: String {
        switch self {
        case .video: "video"
        case .audio: "audio"
        case .pictures: "pictures"
        case .text: "text"
        }
    }

    var symbol: String {
        switch self {
        case .video: "play.rectangle"
        case .audio: "waveform"
        case .pictures: "photo"
        case .text: "doc.text"
        }
    }
}

/// A note's searchable parts, copied off the main actor for indexing.
nonisolated struct NoteSnapshot: Sendable {
    let id: UUID
    let title: String
    let sourceName: String
    let folderName: String?
    let kind: MediaKind
    let createdAt: Date
    /// Changes whenever anything indexed changes.
    let fingerprint: String
    /// The edited text, when the note has been edited.
    let editedMarkdown: String?
    let content: NoteContent?

    /// A stretch of a note that can be found on its own.
    struct Passage: Sendable, Equatable {
        enum Kind: String, Sendable {
            case title, summary, speech, screen, picture, text
        }

        var kind: Kind
        /// Where in the video or audio it is, if anywhere.
        var start: Double?
        /// The section heading or slide title it sits under.
        var heading: String
        var text: String
    }

    /// The note cut into passages: its title, then either its edited text
    /// by paragraph, or what Ovyl found: summary, speech by paragraph, text
    /// on screen by moment, and picture text.
    var passages: [Passage] {
        var passages = [Passage(kind: .title, start: nil, heading: title, text: [sourceName, folderName].compactMap { $0 }.joined(separator: " · "))]
        if let editedMarkdown {
            passages += Self.passages(ofMarkdown: editedMarkdown)
            return passages
        }
        guard let content else { return passages }
        let summary = ([content.summary].compactMap { $0 } + content.keyPoints + content.screenTitles).joined(separator: "\n")
        if !summary.isEmpty {
            passages.append(Passage(kind: .summary, start: nil, heading: "Summary", text: summary))
        }
        for section in content.sections {
            for paragraph in section.paragraphs where !paragraph.text.isEmpty {
                passages.append(Passage(
                    kind: paragraph.source == .picture ? .picture : .speech,
                    start: paragraph.source == .picture ? nil : paragraph.start,
                    heading: section.heading,
                    text: paragraph.text
                ))
            }
        }
        for moment in content.screenMoments where !moment.lines.isEmpty {
            passages.append(Passage(kind: .screen, start: moment.start, heading: moment.title ?? "", text: moment.lines.joined(separator: "\n")))
        }
        return passages
    }

    /// Edited Markdown by block, each under the heading before it, with the
    /// time of its first timestamp link.
    static func passages(ofMarkdown markdown: String) -> [Passage] {
        var passages: [Passage] = []
        var heading = ""
        let blocks = markdown.components(separatedBy: "\n\n")
        for block in blocks {
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("#"), !trimmed.contains("\n") {
                heading = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                continue
            }
            let text = NoteMarkdown.plainText(trimmed).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let start = trimmed.firstMatch(of: /\(#t=([0-9.]+)\)/).flatMap { Double($0.output.1) }
            passages.append(Passage(kind: .text, start: start, heading: heading, text: text))
        }
        return passages
    }
}

extension Note {
    /// Video, audio, pictures or text, from the kind and the file it came from.
    var mediaKind: MediaKind {
        switch kind {
        case .pictures: return .pictures
        case .text: return .text
        case .video:
            if let type = UTType(filenameExtension: (sourceName as NSString).pathExtension), type.conforms(to: .audio) {
                return .audio
            }
            return .video
        }
    }

    func snapshot(folderName: String?) -> NoteSnapshot {
        NoteSnapshot(
            id: id,
            title: displayTitle,
            sourceName: sourceName,
            folderName: folderName,
            kind: mediaKind,
            createdAt: createdAt,
            fingerprint: indexFingerprint(folderName: folderName),
            editedMarkdown: editedMarkdown,
            content: content
        )
    }

    /// Cheap to work out (no note text is read), and different whenever the
    /// title, folder, text or state change.
    func indexFingerprint(folderName: String?) -> String {
        "\(displayTitle)|\(folderName ?? "")|\(updatedAt?.timeIntervalSince1970 ?? 0)|\(createdAt.timeIntervalSince1970)|\(statusRaw)"
    }
}
