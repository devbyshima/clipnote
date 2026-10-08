import Foundation

/// The body of a note: everything Ovyl found in a video or in pictures,
/// organized for reading. Stored as JSON on `Note`, so it can grow without
/// migrations: fields added later decode as empty from older notes.
nonisolated struct NoteContent: Codable, Sendable, Equatable {
    var summary: String?
    var keyPoints: [String] = []
    var sections: [NoteSection] = []
    var screenMoments: [ScreenMoment] = []
    /// Text that stayed on screen through most of the video, such as a
    /// headline banner. Watermarks and account handles are left out.
    var screenTitles: [String] = []
    /// Songs and other music, which aren't transcribed.
    var music: [TimeSpan] = []
    /// The pictures the note was made from, in order; empty for a video.
    var pictures: [NotePicture] = []
    /// Spoken language as an ISO code ("en"), when known.
    var language: String?
    /// Which speech engine produced the transcript.
    var engine: String?
    /// Whether Apple Intelligence wrote the title, summary and headings.
    var formattedWithAI = false
    /// Something the reader should know, e.g. speech could not be transcribed.
    var notice: String?

    var paragraphs: [Paragraph] { sections.flatMap(\.paragraphs) }
    var isEmpty: Bool { paragraphs.isEmpty && screenMoments.isEmpty }
    var isPictures: Bool { !pictures.isEmpty }

    var plainText: String {
        var parts: [String] = []
        if let summary { parts.append(summary) }
        parts += keyPoints
        parts += screenTitles
        for section in sections {
            parts.append(section.heading)
            parts += section.paragraphs.map(\.text)
        }
        parts += screenMoments.flatMap(\.lines)
        return parts.joined(separator: "\n")
    }
}

nonisolated extension NoteContent {
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        summary = try values.decodeIfPresent(String.self, forKey: .summary)
        keyPoints = try values.decodeIfPresent([String].self, forKey: .keyPoints) ?? []
        sections = try values.decodeIfPresent([NoteSection].self, forKey: .sections) ?? []
        screenMoments = try values.decodeIfPresent([ScreenMoment].self, forKey: .screenMoments) ?? []
        screenTitles = try values.decodeIfPresent([String].self, forKey: .screenTitles) ?? []
        music = try values.decodeIfPresent([TimeSpan].self, forKey: .music) ?? []
        pictures = try values.decodeIfPresent([NotePicture].self, forKey: .pictures) ?? []
        language = try values.decodeIfPresent(String.self, forKey: .language)
        engine = try values.decodeIfPresent(String.self, forKey: .engine)
        formattedWithAI = try values.decodeIfPresent(Bool.self, forKey: .formattedWithAI) ?? false
        notice = try values.decodeIfPresent(String.self, forKey: .notice)
    }
}

nonisolated struct NoteSection: Codable, Sendable, Equatable, Identifiable {
    var id = UUID()
    var heading: String
    var paragraphs: [Paragraph]
    /// Index into `NoteContent.pictures` when the section holds one picture's text.
    var picture: Int?

    var start: TimeInterval { paragraphs.first?.start ?? 0 }
}

/// Where a piece of the note's text came from.
nonisolated enum TextSource: String, Codable, Sendable {
    case speech
    /// Subtitles or captions read off the screen.
    case subtitles
    case picture
}

nonisolated struct Paragraph: Codable, Sendable, Equatable, Identifiable {
    var id = UUID()
    var start: TimeInterval
    var end: TimeInterval
    var text: String
    /// Nil for speech.
    var source: TextSource?
}

/// Text that stayed on screen for a stretch of the video, such as a slide.
nonisolated struct ScreenMoment: Codable, Sendable, Equatable, Identifiable {
    enum Kind: String, Codable, Sendable {
        /// A slide, title card or other block of text, shown with a frame grab.
        case slide
        /// A short remark on screen that isn't said aloud.
        case commentary
    }

    var id = UUID()
    var start: TimeInterval
    var end: TimeInterval
    var lines: [String]
    /// The line that reads as the slide's title, if one stands out.
    var title: String?
    /// File name of a frame grab in the note's thumbnail folder.
    var thumbnail: String?
    var kind: Kind = .slide
}

nonisolated extension ScreenMoment {
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            start: try values.decode(TimeInterval.self, forKey: .start),
            end: try values.decode(TimeInterval.self, forKey: .end),
            lines: try values.decode([String].self, forKey: .lines),
            title: try values.decodeIfPresent(String.self, forKey: .title),
            thumbnail: try values.decodeIfPresent(String.self, forKey: .thumbnail),
            kind: try values.decodeIfPresent(Kind.self, forKey: .kind) ?? .slide
        )
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    }
}

/// A stretch of a video, such as a song that wasn't transcribed.
nonisolated struct TimeSpan: Codable, Sendable, Equatable, Identifiable {
    var id = UUID()
    var start: TimeInterval
    var end: TimeInterval

    var length: TimeInterval { end - start }

    /// How much of `start...end` falls inside `spans`, from 0 to 1.
    static func share(from start: TimeInterval, to end: TimeInterval, in spans: [TimeSpan]) -> Double {
        guard end > start else {
            return spans.contains { $0.start <= start && start <= $0.end } ? 1 : 0
        }
        let covered = spans.reduce(0.0) { $0 + max(0, min(end, $1.end) - max(start, $1.start)) }
        return min(1, covered / (end - start))
    }
}

/// A picture a note was made from.
nonisolated struct NotePicture: Codable, Sendable, Equatable, Identifiable {
    var id = UUID()
    /// The original file name.
    var name: String
    /// File name of a copy in the note's thumbnail folder.
    var thumbnail: String?
}

/// One timed piece of text from a speech engine, or from subtitles.
nonisolated struct SpeechSegment: Sendable, Equatable {
    var start: TimeInterval
    var end: TimeInterval
    var text: String
    /// How sure the speech engine was, from 0 to 1, when it says.
    var confidence: Double?
    var source: TextSource = .speech
}

nonisolated enum TimeFormat {
    /// 75 → "1:15", 3725 → "1:02:05".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// 75 → "1 min", 3725 → "1 hr 2 min", 40 → "40 sec".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) sec" }
        let h = total / 3600, m = (total % 3600) / 60
        return h > 0 ? "\(h) hr \(m) min" : "\(m) min"
    }

    /// 12, 45 → "0:12–0:45".
    static func range(_ start: TimeInterval, _ end: TimeInterval) -> String {
        "\(clock(start))–\(clock(end))"
    }
}
