import Foundation
import NaturalLanguage

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

/// Turns transcript segments and on-screen text, or the text read from
/// pictures, into a finished note.
nonisolated enum NoteComposer {
    struct Input: Sendable {
        var fileName: String
        var duration: TimeInterval
        var segments: [SpeechSegment]
        var moments: [TrackedMoment]
        var screenTitles: [String] = []
        var music: [TimeSpan] = []
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
        let moments = input.moments
        let fromCaptions = !paragraphs.isEmpty && paragraphs.allSatisfy { $0.source == .subtitles }

        var outline: Outline?
        if input.useSmartFormatting, !(paragraphs.isEmpty && moments.isEmpty && input.screenTitles.isEmpty) {
            outline = await SmartFormatter.outline(
                fileName: input.fileName,
                duration: input.duration,
                paragraphs: paragraphs,
                moments: moments,
                screenTitles: input.screenTitles,
                fromCaptions: fromCaptions,
                language: input.language,
                progress: progress
            )
        }
        let formattedWithAI = outline != nil
        var resolved = outline ?? fallbackOutline(
            fileName: input.fileName, paragraphs: paragraphs, moments: moments, screenTitles: input.screenTitles
        )
        resolved.sections = validSections(resolved.sections, paragraphCount: paragraphs.count)
        if resolved.title.isEmpty { resolved.title = Note.title(fromFileName: input.fileName) }

        let content = NoteContent(
            summary: resolved.summary.flatMap { $0.isEmpty ? nil : $0 },
            keyPoints: resolved.keyPoints,
            sections: assemble(paragraphs, starts: resolved.sections, defaultHeading: fromCaptions ? "Captions" : "Transcript"),
            screenMoments: moments.map(screenMoment),
            screenTitles: input.screenTitles,
            music: input.music,
            language: input.language,
            engine: input.engine,
            formattedWithAI: formattedWithAI,
            notice: input.notice
        )
        progress(1)
        return Output(title: resolved.title, content: content)
    }

    struct Picture: Sendable {
        /// The original file name.
        var name: String
        var thumbnail: String?
        var page: PictureReader.Page
    }

    /// A note from pictures: one section per picture with its text, in order.
    static func compose(
        pictures: [Picture],
        useSmartFormatting: Bool,
        notice: String?,
        progress: @Sendable (Double) -> Void
    ) async -> Output {
        let several = pictures.count > 1
        let sections = pictures.enumerated().map { index, picture in
            NoteSection(
                heading: tidyHeading(picture.page.title ?? (several ? "Picture \(index + 1)" : "")),
                paragraphs: picture.page.paragraphs.map { Paragraph(start: 0, end: 0, text: $0, source: .picture) },
                picture: index
            )
        }
        let text = sections.flatMap { $0.paragraphs.map(\.text) }.joined(separator: "\n")
        let language = TextLanguage.detect(text)

        var outline: Outline?
        if useSmartFormatting, !text.isEmpty {
            outline = await SmartFormatter.overview(ofPictures: sections, language: language, progress: progress)
        }
        let fileTitle = Note.title(fromFileName: pictures.first?.name ?? "")
        let readTitle = pictures.lazy.compactMap(\.page.title).first { (3...80).contains($0.count) }
        let title = outline.map(\.title).flatMap { $0.isEmpty ? nil : $0 } ?? readTitle ?? fileTitle

        let content = NoteContent(
            summary: outline?.summary.flatMap { $0.isEmpty ? nil : $0 },
            keyPoints: outline?.keyPoints ?? [],
            sections: sections,
            pictures: pictures.map { NotePicture(name: $0.name, thumbnail: $0.thumbnail) },
            language: language,
            formattedWithAI: outline != nil,
            notice: notice
        )
        progress(1)
        return Output(title: title, content: content)
    }

    /// Without Apple Intelligence: a title from text shown throughout the
    /// video, the opening slide, or the file name, and slide titles as
    /// section headings when the video has slides.
    static func fallbackOutline(fileName: String, paragraphs: [Paragraph], moments: [TrackedMoment], screenTitles: [String] = []) -> Outline {
        let titled = moments.compactMap { moment in titleLine(of: moment).map { (moment, $0) } }

        var title = Note.title(fromFileName: fileName)
        if let shown = screenTitles.first(where: { (3...80).contains($0.count) }) {
            title = shown
        } else if let first = titled.first, first.0.start <= 15, (3...80).contains(first.1.count) {
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

    static func assemble(_ paragraphs: [Paragraph], starts: [Outline.SectionStart], defaultHeading: String = "Transcript") -> [NoteSection] {
        guard !paragraphs.isEmpty else { return [] }
        guard !starts.isEmpty else {
            return [NoteSection(heading: defaultHeading, paragraphs: paragraphs)]
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
            thumbnail: moment.thumbnail,
            kind: moment.kind
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
        var sources = Set<TextSource>()
        var start: TimeInterval = 0, end: TimeInterval = 0, words = 0

        func flush() {
            guard !texts.isEmpty else { return }
            let text = tidy(texts.joined(separator: unspaced ? "" : " "))
            // Marked only when all of it came from one place other than speech.
            let source = sources.count == 1 && sources.first != .speech ? sources.first : nil
            if !text.isEmpty { paragraphs.append(Paragraph(start: start, end: end, text: text, source: source)) }
            texts = []
            sources = []
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
            sources.insert(segment.source)
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

nonisolated enum TextLanguage {
    /// The main language of some text as an ISO code ("en"), when it's clear.
    static func detect(_ text: String) -> String? {
        guard text.count >= 12 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage, language != .undetermined else { return nil }
        return language.rawValue
    }
}
