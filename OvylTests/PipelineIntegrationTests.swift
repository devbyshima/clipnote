import AVFoundation
import Foundation
import Testing
@testable import Ovyl

/// Runs the real pipeline on Fixtures/sample.mp4 (made by
/// scripts/make-test-video.sh): three narrated slides, with a burned-in
/// caption on the last one.
@Suite(.serialized, .timeLimit(.minutes(10)))
struct PipelineIntegrationTests {
    private final class Token {}

    private var sampleURL: URL {
        get throws {
            try #require(
                Bundle(for: Token.self).url(forResource: "sample", withExtension: "mp4", subdirectory: "Fixtures"),
                "Run scripts/make-test-video.sh to make the test video"
            )
        }
    }

    private func run(_ options: PipelineOptions) async throws -> PipelineResult {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ovyl-tests-\(UUID().uuidString)")
        let result = try await ClipPipeline().run(url: try sampleURL, options: options, thumbnailsFolder: folder) { _ in }
        print("──── \(options.engine.rawValue) ────")
        print(NoteExporter.markdown(.init(title: result.title, date: .now, duration: result.duration, content: result.content)))
        return result
    }

    @Test func whisperTranscribesAndReadsTheScreen() async throws {
        try #require(WhisperEngine.isBundled, "Run scripts/fetch-models.sh")
        var options = PipelineOptions()
        options.engine = .whisper
        let result = try await run(options)
        let content = result.content
        let transcript = content.paragraphs.map(\.text).joined(separator: " ").lowercased()

        #expect(content.engine == WhisperEngine.displayName)
        #expect(content.language == "en")
        #expect(content.notice == nil)
        #expect(transcript.contains("quarterly planning review"))
        #expect(transcript.contains("two engineers"))
        #expect(transcript.contains("friday"))
        // Whisper likes to add "Thank you." in trailing silence.
        #expect(!transcript.contains("thank you"))
        #expect(result.duration > 20)

        let screen = content.screenMoments.flatMap(\.lines).joined(separator: "\n")
        #expect(screen.contains("Quarterly Planning Review"))
        #expect(screen.contains("Launch date: March 14"))
        #expect(screen.contains("Three Priorities"))
        #expect(screen.contains("Ship the mobile beta"))
        #expect(screen.contains("Owner: Priya Raman"))
        // The burned-in caption repeats the speech, so it's left out.
        #expect(!screen.contains("We meet again on Friday"))
        #expect(content.screenMoments.count == 3)
        #expect(content.screenMoments.allSatisfy { $0.thumbnail != nil })
        #expect(!result.title.isEmpty)
    }

    @Test func appleSpeechTranscribes() async throws {
        try #require(AppleSpeechEngine.isAvailable)
        var options = PipelineOptions()
        options.engine = .apple
        options.language = "en"
        options.readsScreenText = false
        options.smartFormatting = false
        let result = try await run(options)
        let transcript = result.content.paragraphs.map(\.text).joined(separator: " ").lowercased()
        // Apple Speech goes first; Whisper steps in if it can't run here.
        #expect(transcript.contains("quarterly planning"))
        #expect(transcript.contains("engineers"))
    }

    @Test func smartFormattingWhenAvailable() async throws {
        try #require(SmartFormatter.availability == .available, "Apple Intelligence isn't available on this Mac")
        var options = PipelineOptions()
        options.engine = .whisper
        let result = try await run(options)
        #expect(result.content.formattedWithAI)
        #expect(result.content.summary?.isEmpty == false)
        #expect(!result.content.keyPoints.isEmpty)
        #expect(result.content.sections.first?.heading.isEmpty == false)
    }
}
