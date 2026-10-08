import Foundation
import Testing
@testable import Ovyl

/// Runs the real pipeline on the caption and picture fixtures made by
/// scripts/make-test-video.sh. Apple Speech keeps these quick; Whisper is
/// covered by PipelineIntegrationTests.
@Suite(.serialized, .timeLimit(.minutes(10)))
struct ContentKindsTests {
    private final class Token {}

    private func fixture(_ name: String, _ type: String) throws -> URL {
        try #require(
            Bundle(for: Token.self).url(forResource: name, withExtension: type, subdirectory: "Fixtures"),
            "Run scripts/make-test-video.sh to make the test fixtures"
        )
    }

    private var options: PipelineOptions {
        var options = PipelineOptions()
        options.engine = .apple
        options.language = "en"
        options.smartFormatting = false
        return options
    }

    private var folder: URL {
        FileManager.default.temporaryDirectory.appending(path: "ovyl-tests-\(UUID().uuidString)")
    }

    private func show(_ name: String, _ result: PipelineResult) {
        print("──── \(name) ────")
        print(NoteExporter.markdown(.init(title: result.title, date: .now, duration: result.duration, content: result.content)))
    }

    private func run(_ name: String) async throws -> PipelineResult {
        let result = try await ClipPipeline().run(url: try fixture(name, "mp4"), options: options, thumbnailsFolder: folder) { _ in }
        show(name, result)
        return result
    }

    @Test func speechWithMatchingSubtitles() async throws {
        try #require(AppleSpeechEngine.isAvailable)
        let content = try await run("captions-speech").content
        let text = content.paragraphs.map(\.text).joined(separator: " ").lowercased()
        // Apple Speech writes small numbers as digits; the subtitles spell them out.
        #expect(text.contains("every morning i wake up at"))
        #expect(text.contains("glass of water"))
        #expect(text.contains("goals for the day"))
        // Talking over quiet music is still speech.
        #expect(content.music.isEmpty)
        #expect(content.screenTitles == ["MY MORNING ROUTINE"])
        // The subtitles repeat the speech, so they appear once.
        let screen = content.screenMoments.flatMap(\.lines).joined(separator: "\n").lowercased()
        #expect(!screen.contains("glass of water"))
        #expect(!content.plainText.contains("morningwithme"))
        #expect(content.screenMoments.contains { $0.kind == .commentary && $0.lines.joined().contains("this changed my life") })
    }

    @Test func songWithCaptions() async throws {
        let result = try await run("captions-music")
        let content = result.content
        // The song plays from start to end.
        #expect(content.music.count == 1)
        #expect((content.music.first?.start ?? 99) < 0.5)
        #expect((content.music.first?.end ?? 0) > 15.5)
        let text = content.paragraphs.map(\.text).joined(separator: " ")
        // The song isn't transcribed; the captions are the note.
        #expect(!text.lowercased().contains("dream"))
        #expect(text.contains("Put your phone away by 10pm"))
        #expect(text.contains("Your body will thank you"))
        #expect(content.paragraphs.allSatisfy { $0.source == .subtitles })
        #expect(content.screenTitles == ["3 SLEEP TIPS"])
        #expect(result.title == "3 SLEEP TIPS")
        #expect(content.engine == "On-screen captions")
        #expect(!content.plainText.contains("sleepcoach"))
    }

    @Test func captionsWithoutSound() async throws {
        let content = try await run("captions-silent").content
        let text = content.paragraphs.map(\.text).joined(separator: " ")
        #expect(text.contains("Step one: open the Settings app."))
        #expect(text.contains("Step two: tap General, then About."))
        #expect(text.contains("Step three: check the version number."))
        #expect(content.screenMoments.isEmpty)
        #expect(content.engine == "On-screen captions")
        #expect(content.language == "en")
    }

    @Test func picturesMakeOneNote() async throws {
        let urls = [try fixture("picture-1", "png"), try fixture("picture-2", "png")]
        let result = try await ClipPipeline().run(pictures: urls, options: options, thumbnailsFolder: folder) { _ in }
        show("pictures", result)
        let content = result.content
        #expect(content.pictures.map(\.name) == ["picture-1.png", "picture-2.png"])
        #expect(content.pictures.allSatisfy { $0.thumbnail != nil })
        #expect(content.sections.map(\.picture) == [0, 1])
        let first = content.sections[0]
        let firstText = first.paragraphs.map(\.text).joined(separator: " ")
        #expect(first.heading == "Packing List")
        #expect(firstText.contains("Bring the blue tent and two sleeping bags."))
        #expect(firstText.contains("Maya is bringing the camping stove."))
        let second = content.sections[1]
        let secondText = ([second.heading] + second.paragraphs.map(\.text)).joined(separator: " ")
        #expect(secondText.contains("Sprint Goals"))
        #expect(secondText.contains("login timeout"))
        #expect(secondText.contains("Thursday"))
        #expect(content.paragraphs.allSatisfy { $0.source == .picture })
        #expect(content.language == "en")
        #expect(result.title == "Packing List")
    }
}
