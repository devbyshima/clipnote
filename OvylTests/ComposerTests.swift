import Foundation
import Testing
@testable import Ovyl

struct ParagraphBuilderTests {
    @Test func splitsOnLongPauses() {
        let segments = [
            SpeechSegment(start: 0, end: 2, text: "Hello there."),
            SpeechSegment(start: 2.2, end: 4, text: "this continues."),
            SpeechSegment(start: 8, end: 10, text: "After a pause."),
        ]
        let paragraphs = ParagraphBuilder.build(segments, language: "en")
        #expect(paragraphs.map(\.text) == ["Hello there. this continues.", "After a pause."])
        #expect(paragraphs[1].start == 8)
    }

    @Test func splitsLongParagraphsAtSentenceEnds() {
        let sentence = Array(repeating: "word", count: 40).joined(separator: " ") + "."
        let segments = (0..<4).map { SpeechSegment(start: Double($0) * 10, end: Double($0) * 10 + 9, text: sentence) }
        let paragraphs = ParagraphBuilder.build(segments, language: "en")
        #expect(paragraphs.count == 2)
    }

    @Test func joinsUnspacedLanguagesWithoutSpaces() {
        let segments = [
            SpeechSegment(start: 0, end: 1, text: "こんにちは。"),
            SpeechSegment(start: 1, end: 2, text: "元気ですか。"),
        ]
        #expect(ParagraphBuilder.build(segments, language: "ja").first?.text == "こんにちは。元気ですか。")
    }

    @Test func tidiesSpacingAndCapitalizes() {
        #expect(ParagraphBuilder.tidy("  well , this  is it .") == "Well, this is it.")
    }
}

struct ComposerTests {
    @Test func sectionsAreSortedClampedAndStartAtZero() {
        let sections: [Outline.SectionStart] = [
            .init(paragraph: 4, heading: "Later"),
            .init(paragraph: 2, heading: "\"Middle\""),
            .init(paragraph: 2, heading: "Duplicate"),
            .init(paragraph: 99, heading: "Out of range"),
        ]
        let valid = NoteComposer.validSections(sections, paragraphCount: 6)
        #expect(valid.map(\.paragraph) == [0, 4])
        #expect(valid.map(\.heading) == ["Middle", "Later"])
    }

    @Test func assembleSplitsParagraphsBySection() {
        let paragraphs = (0..<5).map { Paragraph(start: Double($0), end: Double($0) + 1, text: "P\($0)") }
        let sections = NoteComposer.assemble(paragraphs, starts: [.init(paragraph: 0, heading: "A"), .init(paragraph: 3, heading: "B")])
        #expect(sections.map(\.heading) == ["A", "B"])
        #expect(sections.map { $0.paragraphs.count } == [3, 2])
    }

    @Test func fallbackUsesSlideTitlesForHeadings() {
        let paragraphs = [
            Paragraph(start: 0, end: 8, text: "Intro"),
            Paragraph(start: 10, end: 18, text: "Second"),
            Paragraph(start: 20, end: 28, text: "Third"),
        ]
        let moments = [
            TrackedMoment(start: 0.5, end: 9, lines: [
                ScreenLine(text: "Quarterly Review", midY: 0.8, height: 0.1),
                ScreenLine(text: "Revenue grew", midY: 0.5, height: 0.05),
            ]),
            TrackedMoment(start: 19, end: 28, lines: [
                ScreenLine(text: "Next Steps", midY: 0.8, height: 0.1),
                ScreenLine(text: "Budget review", midY: 0.5, height: 0.05),
            ]),
        ]
        let outline = NoteComposer.fallbackOutline(fileName: "q3_review.mp4", paragraphs: paragraphs, moments: moments)
        #expect(outline.title == "Quarterly Review")
        #expect(outline.sections.map(\.heading) == ["Quarterly Review", "Next Steps"])
        #expect(outline.sections.map(\.paragraph) == [0, 2])
    }

    @Test func titleFromFileName() {
        #expect(Note.title(fromFileName: "team_sync-2026-03 FINAL.mov") == "Team Sync 2026 03 Final")
        #expect(Note.title(fromFileName: ".mp4") == "Untitled Video")
    }
}

struct ScreenTextTests {
    private func line(_ text: String, y: Double = 0.7) -> ScreenLine {
        ScreenLine(text: text, midY: y, height: 0.05)
    }

    @Test func slideBuildsStayOneMoment() {
        var tracker = MomentTracker()
        _ = tracker.observe(lines: [line("Three priorities"), line("1. Hire two engineers")], at: 1)
        let event = tracker.observe(lines: [line("Three priorities"), line("1. Hire two engineers"), line("2. Ship the beta")], at: 2)
        #expect(event == .continued)
        _ = tracker.finish(at: 3)
        #expect(tracker.moments.count == 1)
        #expect(tracker.moments[0].lines.count == 3)
    }

    @Test func newSlideStartsNewMoment() {
        var tracker = MomentTracker()
        _ = tracker.observe(lines: [line("Quarterly planning")], at: 1)
        let event = tracker.observe(lines: [line("Next steps"), line("Budget on Friday")], at: 5)
        #expect(event == .started(closed: 0))
    }

    @Test func ocrNoiseStillMatches() {
        #expect(Similarity.isSame("Launch date: March 14", "Launch date March 14."))
        #expect(Similarity.isSame("Revenue grew 18 percent", "Revenue qrew 18 percent"))
        #expect(!Similarity.isSame("Next steps", "Three priorities"))
    }

    @Test func repeatedTextAppearsOnce() {
        let moments = [
            TrackedMoment(start: 0, end: 5, lines: [line("Channel Name"), line("Intro")]),
            TrackedMoment(start: 6, end: 9, lines: [line("Channel Name"), line("Chapter two")]),
            TrackedMoment(start: 10, end: 12, lines: [line("Channel Name")]),
        ]
        let result = MomentTracker.removeRepeats(moments)
        #expect(result.count == 2)
        #expect(result[1].lines.map(\.text) == ["Chapter two"])
    }
}

struct AudioTests {
    @Test func chunksStayUnderThirtySecondsAndSkipSilence() {
        let rate = AudioLoader.sampleRate
        // 10 s of tone, 5 s of silence, 40 s of tone.
        var samples = (0..<(10 * rate)).map { Float(sin(Double($0) * 0.05)) * 0.3 }
        samples += Array(repeating: 0, count: 5 * rate)
        samples += (0..<(40 * rate)).map { Float(sin(Double($0) * 0.05)) * 0.3 }
        let chunks = AudioChunker.chunks(for: samples)
        #expect(chunks.allSatisfy { $0.range.count <= 29 * rate })
        #expect(chunks.first?.range.lowerBound == 0)
        #expect(chunks.last?.range.upperBound == samples.count)
        // The first cut lands in the silence.
        let firstCut = Double(chunks[0].range.upperBound) / Double(rate)
        #expect(firstCut > 10 && firstCut < 15)
    }

    @Test func whisperPhantomsAreFiltered() {
        #expect(WhisperCleanup.isHallucination(text: " [Music]", noSpeechProb: 0.1, avgLogprob: -0.2))
        #expect(WhisperCleanup.isHallucination(text: "Thanks for watching!", noSpeechProb: 0.5, avgLogprob: -0.3))
        #expect(!WhisperCleanup.isHallucination(text: "Thanks for watching!", noSpeechProb: 0.01, avgLogprob: -0.1))
        #expect(!WhisperCleanup.isHallucination(text: "We have three priorities.", noSpeechProb: 0.1, avgLogprob: -0.2))
        #expect(WhisperCleanup.clean("<|startoftranscript|> Hello  world<|endoftext|>") == "Hello world")
    }

    @Test func loopsCollapse() {
        let segments = [
            SpeechSegment(start: 0, end: 2, text: "Okay."),
            SpeechSegment(start: 2, end: 4, text: "okay."),
            SpeechSegment(start: 4, end: 6, text: "Moving on."),
        ]
        #expect(WhisperCleanup.removeRepeats(segments).map(\.text) == ["Okay.", "Moving on."])
    }
}

struct ExportTests {
    @Test func markdownHasStructure() {
        var content = NoteContent()
        content.summary = "A short review."
        content.keyPoints = ["Revenue grew."]
        content.sections = [NoteSection(heading: "Results", paragraphs: [Paragraph(start: 65, end: 70, text: "We grew.")])]
        content.screenMoments = [ScreenMoment(start: 66, end: 70, lines: ["Revenue +18%"])]
        let markdown = NoteExporter.markdown(.init(title: "Review", date: .now, duration: 70, content: content))
        #expect(markdown.hasPrefix("# Review\n"))
        #expect(markdown.contains("> A short review."))
        #expect(markdown.contains("- Revenue grew."))
        #expect(markdown.contains("## Results"))
        #expect(markdown.contains("**1:05** We grew."))
        #expect(markdown.contains("> **On screen at 1:06**\n> Revenue +18%"))
    }

    @Test func clockFormatting() {
        #expect(TimeFormat.clock(75) == "1:15")
        #expect(TimeFormat.clock(3725) == "1:02:05")
        #expect(TimeFormat.duration(40) == "40 sec")
        #expect(TimeFormat.duration(3725) == "1 hr 2 min")
    }
}
