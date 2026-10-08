import Foundation
import SoundAnalysis
import Testing
@testable import Ovyl

struct ScreenTextSorterTests {
    private func line(_ text: String, y: Double, height: Double = 0.04) -> ScreenLine {
        ScreenLine(text: text, midY: y, height: height)
    }

    /// One frame a second, at half past; `text(t)` gives the lines in second t.
    private func frames(_ seconds: Int, _ text: (Int) -> [ScreenLine]) -> [FrameText] {
        (0..<seconds).map { FrameText(time: Double($0) + 0.5, lines: text($0)) }
    }

    @Test func captionsWithoutSpeechBecomeTheText() {
        let captions = ["Put your phone away by 10pm", "Keep your bedroom cool and dark", "Wake up at the same time every day", "Your body will thank you"]
        let input = frames(16) { t in
            [line("3 SLEEP TIPS", y: 0.85, height: 0.05), line(captions[t / 4], y: 0.5), line("@sleepcoach", y: 0.03, height: 0.02)]
        }
        let output = ScreenTextSorter.sort(.init(frames: input, interval: 1, duration: 16, transcript: []))
        #expect(output.titles == ["3 SLEEP TIPS"])
        #expect(output.transcript.map(\.text).joined(separator: " ")
            == "Put your phone away by 10pm. Keep your bedroom cool and dark. Wake up at the same time every day. Your body will thank you")
        #expect(output.transcript.allSatisfy { $0.source == .subtitles })
        #expect(output.moments.isEmpty)
    }

    @Test func spokenSubtitlesAppearOnceAndSlidesStay() {
        let input = frames(28) { t in
            if t < 9 {
                return [line("Quarterly Planning Review", y: 0.76, height: 0.09), line("Revenue grew 18 percent", y: 0.5)]
            }
            if t < 19 {
                return [line("Three Priorities", y: 0.76, height: 0.09), line("Hire two engineers", y: 0.5)]
            }
            return [
                line("Next Steps", y: 0.76, height: 0.09),
                line("Owner: Priya Raman", y: 0.45),
                line("We meet again on Friday to review the budget.", y: 0.08),
            ]
        }
        let transcript = [
            SpeechSegment(start: 0, end: 8.5, text: "Welcome to the quarterly planning review. This quarter, revenue grew eighteen percent, and the launch is set for March fourteenth."),
            SpeechSegment(start: 9.5, end: 18, text: "We have three priorities. First, we will hire two engineers."),
            SpeechSegment(start: 19.5, end: 26, text: "We meet again on Friday to review the budget. Priya will own the follow up."),
        ]
        let output = ScreenTextSorter.sort(.init(frames: input, interval: 1, duration: 28, transcript: transcript))
        let screen = output.moments.flatMap { $0.lines.map(\.text) }
        // Slide text read aloud is still slide text.
        #expect(screen.contains("Quarterly Planning Review"))
        #expect(screen.contains("Hire two engineers"))
        #expect(screen.contains("Owner: Priya Raman"))
        // The caption repeats the speech, so it's left to the transcript.
        #expect(!screen.contains("We meet again on Friday to review the budget."))
        #expect(output.transcript == transcript)
        #expect(output.moments.count == 3)
        #expect(output.moments.allSatisfy { $0.kind == .slide })
    }

    @Test func slideReadAloudKeepsItsLines() {
        // Positions and sizes as Vision reads the sample video's first slide.
        let input = frames(9) { _ in
            [
                line("Quarterly Planning Review", y: 0.748, height: 0.104),
                line("Revenue grew 18 percent", y: 0.557, height: 0.058),
                line("Launch date: March 14", y: 0.448, height: 0.067),
            ]
        }
        let transcript = [
            SpeechSegment(start: 0, end: 2.6, text: "Welcome to the quarterly planning review."),
            SpeechSegment(start: 2.6, end: 5.4, text: "This quarter, revenue grew 18%,"),
            SpeechSegment(start: 5.4, end: 8.2, text: "and the launch is set for March 14th."),
        ]
        let output = ScreenTextSorter.sort(.init(frames: input, interval: 1, duration: 9, transcript: transcript))
        #expect(output.moments.first?.lines.map(\.text) == ["Quarterly Planning Review", "Revenue grew 18 percent", "Launch date: March 14"])
    }

    @Test func subtitlesReplaceUnsureOrIncompleteSpeech() {
        let cues = [
            "Every morning I wake up at six.", "Then I drink a big glass of water.",
            "After that I go for a short walk outside.", "And I write down three goals for the day.",
        ]
        let input = frames(12) { t in [line(cues[t / 3], y: 0.5)] }
        let transcript = [
            SpeechSegment(start: 0, end: 2.8, text: "Every morning I wake up at six.", confidence: 0.9),
            SpeechSegment(start: 3, end: 5.8, text: "Then I drink a big glass of water.", confidence: 0.9),
            // Unsure, and wrong.
            SpeechSegment(start: 6, end: 8.8, text: "After that I go far a shore wok.", confidence: 0.3),
            // Sure, but it missed the end.
            SpeechSegment(start: 9, end: 11.8, text: "And I write down three goals", confidence: 0.9),
        ]
        let output = ScreenTextSorter.sort(.init(frames: input, interval: 1, duration: 12, transcript: transcript))
        #expect(output.transcript.map(\.text) == [transcript[0].text, transcript[1].text, cues[2], cues[3]])
        #expect(output.transcript.map(\.source) == [.speech, .speech, .subtitles, .subtitles])
        #expect(output.moments.isEmpty)
    }

    @Test func subtitlesFillSpeechTheEngineMissed() {
        let cues = [
            "Every morning I wake up at six.", "Then I drink a big glass of water.", "I stretch for five minutes.",
            "Then I make a cup of coffee.", "After that I go for a short walk outside.",
        ]
        let input = frames(15) { t in [line(cues[t / 3], y: 0.5)] }
        // The engine heard nothing during the last subtitle.
        let transcript = cues.prefix(4).enumerated().map {
            SpeechSegment(start: Double($0.offset) * 3, end: Double($0.offset) * 3 + 2.8, text: $0.element)
        }
        // Someone is talking the whole time.
        let sound = SoundProfile(windows: stride(from: 0.0, to: 15, by: 1.5).map {
            .init(start: $0, end: $0 + 3, speech: 0.9, vocals: 0, music: 0)
        })
        let output = ScreenTextSorter.sort(.init(frames: input, interval: 1, duration: 15, transcript: transcript, sound: sound))
        #expect(output.transcript.count == 5)
        #expect(output.transcript.last?.text == cues[4])
        #expect(output.transcript.last?.source == .subtitles)
        #expect(output.moments.isEmpty)
    }

    @Test func unspokenRemarkIsCommentary() {
        let cues = ["Every morning I wake up at six.", "Then I drink a big glass of water.", "After that I go for a short walk outside."]
        let input = frames(9) { t in
            var lines = [line(cues[t / 3], y: 0.5)]
            if (3..<6).contains(t) { lines.append(line("(this changed my life)", y: 0.73)) }
            return lines
        }
        let transcript = cues.enumerated().map { SpeechSegment(start: Double($0.offset) * 3, end: Double($0.offset) * 3 + 2.8, text: $0.element) }
        let output = ScreenTextSorter.sort(.init(frames: input, interval: 1, duration: 9, transcript: transcript))
        #expect(output.moments.count == 1)
        #expect(output.moments.first?.kind == .commentary)
        #expect(output.moments.first?.lines.map(\.text) == ["(this changed my life)"])
        #expect(output.transcript == transcript)
    }

    @Test func rollingSubtitlesDontRepeat() {
        #expect(ScreenTextSorter.merged(["we meet again on", "again on Friday to review"]) == "we meet again on Friday to review")
        #expect(ScreenTextSorter.merged(["I said no.", "No way."]) == "I said no. No way.")
        #expect(ScreenTextSorter.trimmingOverlap("the budget is due", after: "review the budget") == "is due")
    }

    @Test func captionsGetFullStopsBetweenSentences() {
        #expect(ScreenTextSorter.needsFullStop("Put your phone away", before: "Keep it cool"))
        #expect(!ScreenTextSorter.needsFullStop("Put your phone away", before: "by 10pm"))
        #expect(!ScreenTextSorter.needsFullStop("Then", before: "I left"))
        #expect(!ScreenTextSorter.needsFullStop("Done!", before: "Next"))
    }

    @Test func watermarks() {
        #expect(ScreenTextSorter.isWatermark("@sleepcoach", height: 0.04))
        #expect(ScreenTextSorter.isWatermark("CapCut", height: 0.04))
        #expect(ScreenTextSorter.isWatermark("example.com", height: 0.04))
        #expect(ScreenTextSorter.isWatermark("Confidential", height: 0.015))
        #expect(!ScreenTextSorter.isWatermark("3 SLEEP TIPS", height: 0.05))
    }
}

struct SoundProfileTests {
    private func window(_ start: Double, speech: Double = 0, vocals: Double = 0, music: Double = 0) -> SoundProfile.Window {
        .init(start: start, end: start + 3, speech: speech, vocals: vocals, music: music)
    }

    @Test func singingIsMusicButTalkingOverMusicIsNot() {
        #expect(window(0, speech: 0.1, vocals: 0.8, music: 0.9).isMusic)
        #expect(window(0, music: 0.8).isMusic)
        #expect(!window(0, speech: 0.9, music: 0.7).isMusic)
        #expect(!window(0, speech: 0.9).isMusic)
    }

    @Test func musicSpansJoinAndSkipStings() {
        let profile = SoundProfile(windows: [
            window(0, vocals: 0.9), window(1.5, vocals: 0.9), window(3, vocals: 0.9),
            window(4.5, speech: 0.9), window(6, speech: 0.9), window(7.5, speech: 0.9),
            window(9, music: 0.8),
        ])
        #expect(profile.musicSpans().map { [$0.start, $0.end] } == [[0, 6]])

        // A song in the last window runs to the end of the audio.
        let song = SoundProfile(windows: [window(0, vocals: 0.9), window(1.5, vocals: 0.9), window(3, vocals: 0.9)], duration: 7)
        #expect(song.musicSpans().map { [$0.start, $0.end] } == [[0, 7]])
    }

    @Test func silencingKeepsTheEdges() {
        let rate = AudioLoader.sampleRate
        let samples = [Float](repeating: 0.5, count: rate * 4)
        let quiet = SoundProfile.silencing([TimeSpan(start: 1, end: 3)], in: samples)
        #expect(quiet[rate * 2] == 0)
        #expect(quiet[rate + 100] == 0.5)
        #expect(quiet[rate * 3 + 100] == 0.5)
    }

    @Test func shareOfTimeInSpans() {
        let spans = [TimeSpan(start: 0, end: 4)]
        #expect(TimeSpan.share(from: 2, to: 6, in: spans) == 0.5)
        #expect(TimeSpan.share(from: 5, to: 6, in: spans) == 0)
    }

    @Test func classifierKnowsTheLabelsUsed() throws {
        let known = Set(try SNClassifySoundRequest(classifierIdentifier: .version1).knownClassifications)
        for label in SoundClassifier.speechLabels + SoundClassifier.vocalLabels + SoundClassifier.musicLabels {
            #expect(known.contains(label), "\(label)")
        }
    }
}

struct PictureAndContentTests {
    @Test func pictureTextIsTidied() {
        #expect(PictureReader.tidy("inter-\nnational  travel\nplans ") == "international travel plans")
        #expect(PictureReader.tidy("Self-\nDriving") == "Self- Driving")
    }

    @Test func picturesGoInFileNameOrder() {
        let files = ProcessingCenter.inReadingOrder([(name: "Shot 10.png", bookmark: 1), (name: "Shot 2.png", bookmark: 2)])
        #expect(files.map(\.name) == ["Shot 2.png", "Shot 10.png"])
    }

    @Test func olderNotesStillOpen() throws {
        let json = #"{"keyPoints":[],"sections":[],"screenMoments":[{"start":1,"end":2,"lines":["Hello"]}],"formattedWithAI":false}"#
        let content = try JSONDecoder().decode(NoteContent.self, from: Data(json.utf8))
        #expect(content.screenMoments.first?.kind == .slide)
        #expect(content.music.isEmpty && content.pictures.isEmpty && content.screenTitles.isEmpty)
    }

    @Test func exportShowsMusicTitlesAndPictures() {
        var video = NoteContent()
        video.screenTitles = ["3 SLEEP TIPS"]
        video.music = [TimeSpan(start: 0, end: 16)]
        video.sections = [NoteSection(heading: "Captions", paragraphs: [Paragraph(start: 1, end: 3, text: "Keep it cool.", source: .subtitles)])]
        let markdown = NoteExporter.markdown(.init(title: "Sleep", date: .now, duration: 16, content: video))
        #expect(markdown.contains("**On screen throughout:** 3 SLEEP TIPS"))
        #expect(markdown.contains("*♪ Music, 0:00–0:16 (not transcribed)*"))
        #expect(markdown.contains("**0:01** Keep it cool."))

        var pictures = NoteContent()
        pictures.pictures = [NotePicture(name: "list.png")]
        pictures.sections = [NoteSection(heading: "Packing List", paragraphs: [Paragraph(start: 0, end: 0, text: "Bring the tent.", source: .picture)], picture: 0)]
        let exported = NoteExporter.markdown(.init(title: "Trip", date: .now, duration: 0, content: pictures))
        #expect(exported.contains("## Packing List\n\n*list.png*\n\nBring the tent."))
        #expect(exported.contains("1 picture"))
    }
}
