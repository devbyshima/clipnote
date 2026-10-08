import Foundation

/// The shape of a note before its paragraphs are filled in: a title, an
/// optional summary and key points, and where each section starts.
nonisolated struct Outline: Sendable, Equatable {
    struct SectionStart: Sendable, Equatable {
        var paragraph: Int
        var heading: String
    }

    var title: String
    var summary: String?
    var keyPoints: [String] = []
    var sections: [SectionStart] = []
}

/// Turns transcript segments and on-screen text into a finished note.
nonisolated enum NoteComposer {
    struct Input: Sendable {
        var fileName: String
        var duration: TimeInterval
        var segments: [SpeechSegment]
        var moments: [TrackedMoment]
        var language: String?
        var engine: String?
        var useSmartFormatting: Bool
        var notice: String?
    }

    struct Output: Sendable {
        var title: String
        var content: NoteContent
    }

    static func compose(_ input: Input, progress: @Sendable (Double) -> Void) async -> Output {
        let paragraphs = ParagraphBuilder.build(input.segments, language: input.language)
        let moments = CaptionFilter.removeCaptions(from: input.moments, transcript: input.segments)

        var outline: Outline?
        if input.useSmartFormatting, !(paragraphs.isEmpty && moments.isEmpty) {
            outline = await SmartFormatter.outline(
                fileName: input.fileName,
                duration: input.duration,
                paragraphs: paragraphs,
                moments: moments,
                language: input.language,
                progress: progress
            )
        }
        let formattedWithAI = outline != nil
        var resolved = outline ?? fallbackOutline(fileName: input.fileName, paragraphs: paragraphs, moments: moments)
        resolved.sections = validSections(resolved.sections, paragraphCount: paragraphs.count)
        if resolved.title.isEmpty { resolved.title = Note.title(fromFileName: input.fileName) }

        let content = NoteContent(
            summary: resolved.summary.flatMap { $0.isEmpty ? nil : $0 },
            keyPoints: resolved.keyPoints,
            sections: assemble(paragraphs, starts: resolved.sections),
            screenMoments: moments.map(screenMoment),
            language: input.language,
            engine: input.engine,
            formattedWithAI: formattedWithAI,
            notice: input.notice
        )
        progress(1)
        return Output(title: resolved.title, content: content)
    }

    /// Without Apple Intelligence: a title from the opening slide or the file
    /// name, and slide titles as section headings when the video has slides.
    static func fallbackOutline(fileName: String, paragraphs: [Paragraph], moments: [TrackedMoment]) -> Outline {
        let titled = moments.compactMap { moment in titleLine(of: moment).map { (moment, $0) } }

        var title = Note.title(fromFileName: fileName)
        if let first = titled.first, first.0.start <= 15, (3...80).contains(first.1.count) {
            title = first.1
        }

        var sections: [Outline.SectionStart] = []
        if titled.count >= 2, paragraphs.count >= 2 {
            for (moment, line) in titled {
                let index = paragraphs.firstIndex { $0.end > moment.start } ?? paragraphs.count - 1
                if let last = sections.last, last.paragraph == index { continue }
                sections.append(.init(paragraph: index, heading: line))
            }
        }
        return Outline(title: title, sections: sections)
    }

    /// Sorted, in range, without duplicates, and starting at paragraph 0.
    static func validSections(_ sections: [Outline.SectionStart], paragraphCount: Int) -> [Outline.SectionStart] {
        guard paragraphCount > 0 else { return [] }
        var result: [Outline.SectionStart] = []
        for section in sections.sorted(by: { $0.paragraph < $1.paragraph }) {
            let heading = tidyHeading(section.heading)
            guard !heading.isEmpty, (0..<paragraphCount).contains(section.paragraph) else { continue }
            if result.last?.paragraph == section.paragraph { continue }
            result.append(.init(paragraph: section.paragraph, heading: heading))
        }
        if result.isEmpty { return [] }
        result[0].paragraph = 0
        return result
    }

    static func assemble(_ paragraphs: [Paragraph], starts: [Outline.SectionStart]) -> [NoteSection] {
        guard !paragraphs.isEmpty else { return [] }
        guard !starts.isEmpty else {
            return [NoteSection(heading: "Transcript", paragraphs: paragraphs)]
        }
        return starts.indices.map { i in
            let from = starts[i].paragraph
            let to = i + 1 < starts.count ? starts[i + 1].paragraph : paragraphs.count
            return NoteSection(heading: starts[i].heading, paragraphs: Array(paragraphs[from..<to]))
        }
    }

    static func screenMoment(_ moment: TrackedMoment) -> ScreenMoment {
        ScreenMoment(
            start: moment.start,
            end: moment.end,
            lines: moment.lines.map(\.text),
            title: titleLine(of: moment),
            thumbnail: moment.thumbnail
        )
    }

    /// The line that reads as a heading: marked as a title by Vision, or
    /// clearly taller than the rest and in the top half of the frame.
    static func titleLine(of moment: TrackedMoment) -> String? {
        if let title = moment.lines.first(where: \.isTitle) { return title.text }
        guard moment.lines.count >= 2,
              let tallest = moment.lines.max(by: { $0.height < $1.height }) else { return nil }
        let others = moment.lines.filter { $0 != tallest }.map(\.height).sorted()
        guard !others.isEmpty else { return nil }
        let median = others[others.count / 2]
        return tallest.height >= median * 1.3 && tallest.midY > 0.45 ? tallest.text : nil
    }

    static func tidyHeading(_ text: String) -> String {
        var heading = text.trimmingCharacters(in: .whitespacesAndNewlines)
        heading = heading.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’#*:.-– "))
        if heading.count > 70 { heading = String(heading.prefix(70)).trimmingCharacters(in: .whitespaces) + "…" }
        return heading
    }
}

nonisolated enum ParagraphBuilder {
    /// Languages written without spaces between words.
    static let unspacedLanguages: Set<String> = ["zh", "ja", "th", "lo", "my", "km", "yue"]

    static func build(_ segments: [SpeechSegment], language: String?) -> [Paragraph] {
        let unspaced = unspacedLanguages.contains(language ?? "")
        var paragraphs: [Paragraph] = []
        var texts: [String] = []
        var start: TimeInterval = 0, end: TimeInterval = 0, words = 0

        func flush() {
            guard !texts.isEmpty else { return }
            let text = tidy(texts.joined(separator: unspaced ? "" : " "))
            if !text.isEmpty { paragraphs.append(Paragraph(start: start, end: end, text: text)) }
            texts = []
            words = 0
        }

        for segment in segments.sorted(by: { $0.start < $1.start }) {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if let last = texts.last {
                let gap = segment.start - end
                let endsSentence = last.last.map { ".!?…。！？".contains($0) } ?? false
                if gap >= 2.5 || (words >= 70 && endsSentence) || words >= 150 { flush() }
            }
            if texts.isEmpty { start = segment.start }
            texts.append(text)
            end = max(end, segment.end)
            words += unspaced ? text.count / 2 : text.split(separator: " ").count
        }
        flush()
        return paragraphs
    }

    static func tidy(_ text: String) -> String {
        var result = text
            .replacing(/\s+/, with: " ")
            .replacing(/\s+([,.;:!?])/, with: { $0.output.1 })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = result.first, first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }
        return result
    }
}

nonisolated enum CaptionFilter {
    /// Drops burned-in captions: lines low in the frame whose words were
    /// also spoken around the same time. They'd repeat the transcript.
    static func removeCaptions(from moments: [TrackedMoment], transcript: [SpeechSegment]) -> [TrackedMoment] {
        guard !transcript.isEmpty else { return moments }
        return moments.compactMap { moment in
            let spoken = transcript.filter { $0.end >= moment.start - 6 && $0.start <= moment.end + 6 }
            let vocabulary = Set(spoken.flatMap { Similarity.normalize($0.text).split(separator: " ").map(String.init) })
            var kept = moment
            kept.lines = moment.lines.filter { line in
                let wordCount = line.key.split(separator: " ").count
                let isCaption = line.midY < 0.33 && wordCount >= 3
                    && Similarity.wordCoverage(of: line.text, in: vocabulary) >= 0.7
                return !isCaption
            }
            return kept.lines.isEmpty ? nil : kept
        }
    }
}
