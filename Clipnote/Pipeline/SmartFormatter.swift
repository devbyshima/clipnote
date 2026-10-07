import Foundation
import FoundationModels

/// Writes the title, summary, key points and section headings with Apple's
/// on-device language model. The transcript itself is never rewritten, so
/// the model can't change what was said; it only organizes it.
nonisolated enum SmartFormatter {
    enum Availability: Equatable {
        case available
        case unavailable(String)
    }

    static var availability: Availability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Turn on Apple Intelligence in System Settings to use smart formatting.")
        case .unavailable(.deviceNotEligible):
            return .unavailable("This Mac doesn't support Apple Intelligence.")
        case .unavailable(.modelNotReady):
            return .unavailable("Apple Intelligence is still downloading its model.")
        case .unavailable:
            return .unavailable("Apple Intelligence isn't available right now.")
        }
    }

    /// A session that has started loading the model; keep it alive until
    /// formatting so the load overlaps with transcription.
    static func prewarmedSession() -> LanguageModelSession? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let session = LanguageModelSession(instructions: instructions)
        session.prewarm()
        return session
    }

    static let instructions = """
        You organize video transcripts into clear, well-structured notes.
        Use only facts from the transcript and the on-screen text. Never add information, names, or numbers.
        Write every title, heading, summary, and key point in the same language as the transcript.
        A heading names the topic of its section, like a chapter title in a book.
        """

    /// Returns nil when the model is unavailable or fails, so the caller can
    /// fall back to plain formatting.
    static func outline(
        fileName: String,
        duration: TimeInterval,
        paragraphs: [Paragraph],
        moments: [TrackedMoment],
        language: String?,
        progress: @Sendable (Double) -> Void
    ) async -> Outline? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }
        if let language, !model.supportsLocale(Locale(identifier: language)) { return nil }

        // Room for the instructions, the response schema and the response.
        let budget = max(1200, model.contextSize - 1400)
        let header = "Video: \"\(fileName)\", \(TimeFormat.duration(duration))."

        do {
            if paragraphs.isEmpty {
                let screen = screenText(moments, maxTokens: budget / 3 * 2)
                let overview = try await respond(
                    GeneratedOverview.self,
                    prompt: """
                    \(header)
                    The video has no speech. This is the text that appeared on screen:
                    \(screen)

                    Write a title, a short summary, and key points for notes about this video.
                    """
                )
                return Outline(title: overview.title, summary: overview.summary, keyPoints: clean(overview.keyPoints))
            }

            let single = singlePassPrompt(header: header, paragraphs: paragraphs, moments: moments, budget: budget)
            if try await model.tokenCount(for: single) <= budget {
                progress(0.2)
                let result = try await respond(GeneratedOutline.self, prompt: single)
                return Outline(
                    title: result.title,
                    summary: result.summary,
                    keyPoints: clean(result.keyPoints),
                    sections: result.sections.map { .init(paragraph: $0.paragraph, heading: $0.heading) }
                )
            }

            // Too long for one pass: outline each part, then write the overview
            // from the parts' summaries.
            let chunks = try await chunked(paragraphs, model: model, budget: budget, header: header)
            var sections: [Outline.SectionStart] = []
            var summaries: [String] = []
            for (index, range) in chunks.enumerated() {
                try Task.checkCancellation()
                let prompt = chunkPrompt(header: header, paragraphs: paragraphs, range: range, part: index + 1, of: chunks.count)
                if let part = try? await respond(GeneratedPart.self, prompt: prompt) {
                    sections += part.sections
                        .filter { range.contains($0.paragraph) }
                        .map { .init(paragraph: $0.paragraph, heading: $0.heading) }
                    summaries.append("Part \(index + 1) (from \(TimeFormat.clock(paragraphs[range.lowerBound].start))): \(part.summary)")
                } else {
                    summaries.append("Part \(index + 1): (unavailable)")
                }
                progress(Double(index + 1) / Double(chunks.count + 1))
            }

            let screen = screenText(moments, maxTokens: budget / 4)
            let overview = try await respond(
                GeneratedOverview.self,
                prompt: """
                \(header)
                Summaries of the video's parts, in order:
                \(summaries.joined(separator: "\n"))
                \(screen.isEmpty ? "" : "\nText that appeared on screen:\n\(screen)\n")
                Write a title, a short summary of the whole video, and its key points.
                """
            )
            return Outline(
                title: overview.title,
                summary: overview.summary,
                keyPoints: clean(overview.keyPoints),
                sections: sections
            )
        } catch {
            return nil
        }
    }

    private static func respond<Content: Generable>(_ type: Content.Type, prompt: String) async throws -> Content {
        let session = LanguageModelSession(instructions: instructions)
        let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 900)
        return try await session.respond(to: prompt, generating: type, options: options).content
    }

    private static func singlePassPrompt(header: String, paragraphs: [Paragraph], moments: [TrackedMoment], budget: Int) -> String {
        let screen = screenText(moments, maxTokens: budget / 5)
        return """
        \(header)
        \(screen.isEmpty ? "" : "Text that appeared on screen:\n\(screen)\n")
        Transcript, in numbered paragraphs:
        \(numbered(paragraphs, range: paragraphs.indices))

        Split the transcript into sections by topic. The first section starts at paragraph 0. \
        A short transcript may need only one or two sections; otherwise use about one section for every 3 to 8 paragraphs.
        """
    }

    private static func chunkPrompt(header: String, paragraphs: [Paragraph], range: Range<Int>, part: Int, of total: Int) -> String {
        """
        \(header)
        This is part \(part) of \(total) of the transcript, in numbered paragraphs:
        \(numbered(paragraphs, range: range))

        Split this part into sections by topic, using the paragraph numbers shown. \
        Use about one section for every 3 to 8 paragraphs. Then summarize this part in two sentences.
        """
    }

    private static func numbered(_ paragraphs: [Paragraph], range: Range<Int>) -> String {
        range.map { "[\($0)] (\(TimeFormat.clock(paragraphs[$0].start))) \(paragraphs[$0].text)" }
            .joined(separator: "\n")
    }

    /// On-screen text as "[0:05] line · line", trimmed to roughly `maxTokens`.
    static func screenText(_ moments: [TrackedMoment], maxTokens: Int) -> String {
        var lines: [String] = []
        var characters = 0
        let limit = maxTokens * 3
        for moment in moments {
            let line = "[\(TimeFormat.clock(moment.start))] " + moment.lines.prefix(8).map(\.text).joined(separator: " · ")
            if characters + line.count > limit { break }
            lines.append(line)
            characters += line.count
        }
        return lines.joined(separator: "\n")
    }

    /// Splits paragraphs into parts that each fit the model's context.
    private static func chunked(_ paragraphs: [Paragraph], model: SystemLanguageModel, budget: Int, header: String) async throws -> [Range<Int>] {
        // Estimate first (about 3 characters per token), then confirm each part.
        var ranges: [Range<Int>] = []
        var start = 0, characters = 0
        let target = Int(Double(budget) * 0.8) * 3
        for (index, paragraph) in paragraphs.enumerated() {
            let size = paragraph.text.count + 16
            if characters + size > target, index > start {
                ranges.append(start..<index)
                start = index
                characters = 0
            }
            characters += size
        }
        ranges.append(start..<paragraphs.count)

        var confirmed: [Range<Int>] = []
        var queue = ranges
        while !queue.isEmpty {
            let range = queue.removeFirst()
            let prompt = chunkPrompt(header: header, paragraphs: paragraphs, range: range, part: 1, of: 1)
            if range.count > 1, try await model.tokenCount(for: prompt) > budget {
                let middle = range.lowerBound + range.count / 2
                queue.insert(contentsOf: [range.lowerBound..<middle, middle..<range.upperBound], at: 0)
            } else {
                confirmed.append(range)
            }
        }
        return confirmed
    }

    private static func clean(_ points: [String]) -> [String] {
        points
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "-•* ")) }
            .filter { !$0.isEmpty }
            .prefix(6)
            .map { $0 }
    }
}

@Generable
struct GeneratedSection {
    @Guide(description: "Number of the paragraph where this section starts")
    var paragraph: Int
    @Guide(description: "A short heading for the section, 2 to 6 words")
    var heading: String
}

@Generable
struct GeneratedOutline {
    @Guide(description: "Sections that divide the transcript into its main topics, in order")
    var sections: [GeneratedSection]
    @Guide(description: "Two or three sentences summarizing what the video covers")
    var summary: String
    @Guide(description: "The main takeaways, each one short sentence", .count(2...6))
    var keyPoints: [String]
    @Guide(description: "A specific title for the video, 3 to 8 words, without quotes")
    var title: String
}

@Generable
struct GeneratedPart {
    @Guide(description: "Sections that divide this part into its topics, in order")
    var sections: [GeneratedSection]
    @Guide(description: "Two sentences summarizing this part")
    var summary: String
}

@Generable
struct GeneratedOverview {
    @Guide(description: "Two or three sentences summarizing what the video covers")
    var summary: String
    @Guide(description: "The main takeaways, each one short sentence", .count(2...6))
    var keyPoints: [String]
    @Guide(description: "A specific title for the video, 3 to 8 words, without quotes")
    var title: String
}
