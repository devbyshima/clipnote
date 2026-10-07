import Foundation

/// The body of a note: everything Clipnote found in a video, organized for
/// reading. Stored as JSON on `Note`, so it can grow without migrations.
nonisolated struct NoteContent: Codable, Sendable, Equatable {
    var summary: String?
    var keyPoints: [String] = []
    var sections: [NoteSection] = []
    var screenMoments: [ScreenMoment] = []
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

    var plainText: String {
        var parts: [String] = []
        if let summary { parts.append(summary) }
        parts += keyPoints
        for section in sections {
            parts.append(section.heading)
            parts += section.paragraphs.map(\.text)
        }
        parts += screenMoments.flatMap(\.lines)
        return parts.joined(separator: "\n")
    }
}

nonisolated struct NoteSection: Codable, Sendable, Equatable, Identifiable {
    var id = UUID()
    var heading: String
    var paragraphs: [Paragraph]

    var start: TimeInterval { paragraphs.first?.start ?? 0 }
}

nonisolated struct Paragraph: Codable, Sendable, Equatable, Identifiable {
    var id = UUID()
    var start: TimeInterval
    var end: TimeInterval
    var text: String
}

/// Text that stayed on screen for a stretch of the video, such as a slide.
nonisolated struct ScreenMoment: Codable, Sendable, Equatable, Identifiable {
    var id = UUID()
    var start: TimeInterval
    var end: TimeInterval
    var lines: [String]
    /// The line that reads as the slide's title, if one stands out.
    var title: String?
    /// File name of a frame grab in the note's thumbnail folder.
    var thumbnail: String?
}

/// One timed piece of transcript from a speech engine.
nonisolated struct SpeechSegment: Sendable, Equatable {
    var start: TimeInterval
    var end: TimeInterval
    var text: String
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
}
