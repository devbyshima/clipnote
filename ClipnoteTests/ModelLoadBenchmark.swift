import AVFoundation
import Foundation
import Testing
@testable import Clipnote

/// Measures Whisper's first (cold) load, a later (warm) load, and transcription
/// speed for each place the model can run. Each run copies the model to a new
/// folder, so Core ML has no compiled cache for it, like a first launch.
///
///   ./scripts/build.sh bench
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CLIPNOTE_BENCH"] == "1"), .timeLimit(.minutes(40)))
struct ModelLoadBenchmark {
    private final class Token {}

    @Test func compareComputeUnits() async throws {
        let source = try #require(WhisperEngine.bundledFolder)
        let sample = try #require(Bundle(for: Token.self).url(forResource: "sample", withExtension: "mp4", subdirectory: "Fixtures"))
        let clip = try await AudioLoader.loadSamples(from: AVURLAsset(url: sample), duration: 22) { _ in }
        // About three minutes of speech.
        let audio = Array(repeating: clip, count: 8).flatMap { $0 }
        let audioSeconds = Double(audio.count) / Double(AudioLoader.sampleRate)

        let root = FileManager.default.temporaryDirectory.appending(path: "whisper-bench-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: source, to: root)
        defer { try? FileManager.default.removeItem(at: root) }

        // GPU first (cold GPU compile), then the hybrid (cold Neural Engine
        // compile of the small decoder), then all Neural Engine (cold compile
        // of the large encoder).
        for compute in [WhisperEngine.Compute.gpu, .hybrid, .neuralEngine] {
            let engine = WhisperEngine(folder: root, compute: compute)
            let clock = ContinuousClock()

            let cold = try await clock.measure { try await engine.prepare() }
            await engine.unload()
            let warm = try await clock.measure { try await engine.prepare() }

            var transcript = ""
            let run = try await clock.measure {
                transcript = try await engine.transcribe(samples: audio, language: "en") { _ in }
                    .map(\.text).joined(separator: " ")
            }
            await engine.unload()

            let speed = audioSeconds / run.seconds
            print("BENCH \(compute.rawValue): cold load \(cold.seconds.formatted(.number.precision(.fractionLength(1))))s, warm load \(warm.seconds.formatted(.number.precision(.fractionLength(1))))s, transcribe \(Int(audioSeconds))s of audio in \(run.seconds.formatted(.number.precision(.fractionLength(1))))s (\(speed.formatted(.number.precision(.fractionLength(1))))x real time)")
            #expect(transcript.lowercased().contains("quarterly planning"))
        }
    }
}

extension ModelLoadBenchmark {
    /// A first launch on a Mac that has never compiled the model: the hybrid
    /// should be usable within about a minute, the Neural Engine should take
    /// over once compiled, and the next launch should load it in seconds.
    @Test func firstLaunchUsesHybridThenNeuralEngine() async throws {
        let source = try #require(WhisperEngine.bundledFolder)
        let sample = try #require(Bundle(for: Token.self).url(forResource: "sample", withExtension: "mp4", subdirectory: "Fixtures"))
        let clip = try await AudioLoader.loadSamples(from: AVURLAsset(url: sample), duration: 22) { _ in }

        let root = FileManager.default.temporaryDirectory.appending(path: "whisper-first-launch-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: source, to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "bench-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        let clock = ContinuousClock()
        let start = clock.now
        let service = WhisperService(folder: root, defaultsSuite: suite, idleTimeout: .seconds(3600))
        let phases = await service.phases()
        await service.prepare()

        let first = try await service.engine()
        let usable = clock.now - start
        #expect(first.compute == .hybrid)
        let text = try await service.transcribe(samples: clip, language: "en") { _ in }.map(\.text).joined(separator: " ")
        #expect(text.lowercased().contains("quarterly planning"))

        for await phase in phases where phase == .ready { break }
        let upgraded = clock.now - start
        #expect(try await service.engine().compute == .neuralEngine)
        await service.shutDown()

        // The next launch: same location, same OS.
        let nextStart = clock.now
        let next = WhisperService(folder: root, defaultsSuite: suite)
        await next.prepare()
        let engine = try await next.engine()
        let nextLaunch = clock.now - nextStart
        #expect(engine.compute == .neuralEngine)
        await next.shutDown()

        print("BENCH first launch: transcribing after \(usable.seconds.formatted(.number.precision(.fractionLength(1))))s (hybrid), Neural Engine after \(upgraded.seconds.formatted(.number.precision(.fractionLength(1))))s; next launch ready in \(nextLaunch.seconds.formatted(.number.precision(.fractionLength(1))))s")
    }
}

extension ModelLoadBenchmark {
    /// Transcription speed on the Neural Engine with 1, 2 and 4 chunks at a time.
    @Test func chunkConcurrency() async throws {
        let sample = try #require(Bundle(for: Token.self).url(forResource: "sample", withExtension: "mp4", subdirectory: "Fixtures"))
        let clip = try await AudioLoader.loadSamples(from: AVURLAsset(url: sample), duration: 22) { _ in }
        let audio = Array(repeating: clip, count: 8).flatMap { $0 }
        let audioSeconds = Double(audio.count) / Double(AudioLoader.sampleRate)
        let engine = WhisperEngine(compute: .neuralEngine)
        let clock = ContinuousClock()
        let load = try await clock.measure { try await engine.prepare() }
        print("BENCH bundled Neural Engine load: \(load.seconds.formatted(.number.precision(.fractionLength(1))))s")
        _ = try await engine.transcribe(samples: clip, language: "en") { _ in } // warm up

        var reference = ""
        for workers in [1, 2, 4] {
            var text = ""
            let run = try await clock.measure {
                text = try await engine.transcribe(samples: audio, language: "en", concurrency: workers) { _ in }
                    .map(\.text).joined(separator: " ")
            }
            if workers == 1 { reference = text }
            print("BENCH \(workers) at a time: \(run.seconds.formatted(.number.precision(.fractionLength(1))))s (\((audioSeconds / run.seconds).formatted(.number.precision(.fractionLength(1))))x real time), same text as 1: \(text == reference)")
            #expect(text.lowercased().contains("quarterly planning"))
        }
        await engine.unload()
    }
}

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
