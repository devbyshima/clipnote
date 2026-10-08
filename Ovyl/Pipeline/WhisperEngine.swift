import Foundation
@preconcurrency import WhisperKit

/// Whisper large-v3 turbo, bundled in the app, loaded for one set of compute
/// units. `WhisperService` decides which engine transcribes.
actor WhisperEngine {
    static let displayName = "Whisper large-v3 turbo"

    enum State: Equatable, Sendable {
        case idle, loading, ready
        case failed(String)
    }

    private final class Box: @unchecked Sendable {
        let kit: WhisperKit
        init(_ kit: WhisperKit) { self.kit = kit }
    }

    /// Where each part of the model runs.
    enum Compute: String, Sendable, CaseIterable {
        /// Most power-efficient, but the first load compiles for minutes.
        case neuralEngine
        /// Compiles in seconds; uses more power while transcribing.
        case gpu
        /// Encoder on the GPU, decoder on the Neural Engine.
        case hybrid

        var options: ModelComputeOptions {
            switch self {
            case .neuralEngine: ModelComputeOptions(audioEncoderCompute: .cpuAndNeuralEngine, textDecoderCompute: .cpuAndNeuralEngine)
            case .gpu: ModelComputeOptions(audioEncoderCompute: .cpuAndGPU, textDecoderCompute: .cpuAndGPU)
            case .hybrid: ModelComputeOptions(audioEncoderCompute: .cpuAndGPU, textDecoderCompute: .cpuAndNeuralEngine)
            }
        }
    }

    nonisolated let compute: Compute
    private let folder: URL?
    private let prewarm: Bool
    private let priority: TaskPriority
    private var box: Box?
    private var loadTask: Task<Box, any Error>?
    private(set) var state: State = .idle

    var isReady: Bool { box != nil }

    /// `prewarm` loads one model at a time during a Neural Engine compile,
    /// which keeps peak memory down; it costs about a second when the
    /// compiled model is already cached.
    init(
        folder: URL? = WhisperEngine.bundledFolder,
        compute: Compute = .neuralEngine,
        prewarm: Bool? = nil,
        priority: TaskPriority = .userInitiated
    ) {
        self.folder = folder
        self.compute = compute
        self.prewarm = prewarm ?? (compute == .neuralEngine)
        self.priority = priority
    }

    nonisolated static var bundledFolder: URL? {
        guard let base = Bundle.main.url(forResource: "Whisper", withExtension: nil) else { return nil }
        let encoder = base.appending(path: "model/AudioEncoder.mlmodelc")
        return FileManager.default.fileExists(atPath: encoder.path) ? base : nil
    }

    nonisolated static var isBundled: Bool { bundledFolder != nil }

    /// Loads the model. The first Neural Engine load on a Mac compiles it,
    /// which takes minutes; later loads take seconds.
    func prepare() async throws {
        _ = try await loadedKit()
    }

    /// Releases the model's memory; the next use loads it again.
    func unload() async {
        if let kit = box?.kit { await kit.unloadModels() }
        box = nil
        loadTask = nil
        state = .idle
    }

    private func loadedKit() async throws -> WhisperKit {
        if let box { return box.kit }
        if loadTask == nil {
            guard let folder else { throw ClipError.whisperModelMissing }
            state = .loading
            let compute = compute, prewarm = prewarm
            loadTask = Task.detached(priority: priority) {
                let config = WhisperKitConfig(
                    modelFolder: folder.appending(path: "model").path,
                    tokenizerFolder: folder.appending(path: "tokenizer"),
                    computeOptions: compute.options,
                    verbose: false,
                    logLevel: .error,
                    prewarm: prewarm,
                    load: true,
                    download: false
                )
                return Box(try await WhisperKit(config))
            }
        }
        do {
            let loaded = try await loadTask!.value
            box = loaded
            state = .ready
            return loaded.kit
        } catch {
            loadTask = nil
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    /// Detects the spoken language from the first stretch of speech.
    func detectLanguage(samples: [Float]) async throws -> String {
        let kit = try await loadedKit()
        let window = Array(AudioChunker.firstSpeech(in: samples))
        guard !window.isEmpty else { return "en" }
        return try await kit.detectLangauge(audioArray: window).language
    }

    /// Transcribes in 30-second chunks, `concurrency` chunks at a time, which
    /// keeps the encoder and decoder busy at once.
    func transcribe(
        samples: [Float],
        language: String,
        concurrency: Int = 1,
        progress: @Sendable (Double) -> Void
    ) async throws -> [SpeechSegment] {
        let kit = try await loadedKit()
        let workers = max(1, concurrency)
        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0,
            temperatureFallbackCount: 4,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: false,
            suppressBlank: true,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            noSpeechThreshold: 0.6,
            concurrentWorkerCount: workers
        )

        let chunks = AudioChunker.chunks(for: samples)
        let total = max(1, chunks.last?.range.upperBound ?? 1)
        let energies = AudioChunker.frameEnergies(samples, frame: AudioLoader.sampleRate / 20)
        var segments: [SpeechSegment] = []

        let speechChunks = chunks.filter { !$0.isSilent }
        for start in stride(from: 0, to: speechChunks.count, by: workers) {
            try Task.checkCancellation()
            let batch = Array(speechChunks[start..<min(start + workers, speechChunks.count)])
            let results = await kit.transcribeWithResults(
                audioArrays: batch.map { Array(samples[$0.speech]) },
                decodeOptions: options
            )
            for (chunk, result) in zip(batch, results) {
                let offset = Double(chunk.speech.lowerBound) / Double(AudioLoader.sampleRate)
                let chunkEnd = Double(chunk.speech.upperBound) / Double(AudioLoader.sampleRate)
                for transcription in try result.get() {
                    for segment in transcription.segments {
                        guard !WhisperCleanup.isHallucination(segment) else { continue }
                        let text = WhisperCleanup.clean(segment.text)
                        guard !text.isEmpty else { continue }
                        let start = offset + Double(segment.start)
                        let end = min(chunkEnd, offset + Double(max(segment.end, segment.start)))
                        let voiced = WhisperCleanup.voicedShare(energies, from: start, to: end)
                        if WhisperCleanup.isPhantomPhrase(text) && voiced < 0.4 { continue }
                        segments.append(SpeechSegment(start: start, end: end, text: text))
                    }
                }
            }
            if let last = batch.last { progress(Double(last.range.upperBound) / Double(total)) }
        }
        progress(1)
        segments.sort { $0.start < $1.start }
        return WhisperCleanup.removeRepeats(segments)
    }
}

/// Filters the well-known ways Whisper invents text in silence or music.
nonisolated enum WhisperCleanup {
    static let phantomPhrases: Set<String> = [
        "thank you", "thanks", "thank you for watching", "thanks for watching",
        "thank you so much for watching", "please subscribe", "subscribe",
        "like and subscribe", "bye", "you",
        "subtitles by the amaraorg community", "amaraorg",
    ]

    static func isHallucination(_ segment: TranscriptionSegment) -> Bool {
        isHallucination(text: segment.text, noSpeechProb: segment.noSpeechProb, avgLogprob: segment.avgLogprob)
    }

    static func isHallucination(text: String, noSpeechProb: Float, avgLogprob: Float) -> Bool {
        let cleaned = clean(text)
        if cleaned.isEmpty { return true }
        // Sound descriptions such as [Music] or (applause), or only music notes.
        if cleaned.wholeMatch(of: /[\[\(][^\]\)]*[\]\)]/) != nil { return true }
        if cleaned.allSatisfy({ "♪♫🎵🎶 .,-".contains($0) }) { return true }
        if noSpeechProb > 0.6 && avgLogprob < -1.0 { return true }
        return isPhantomPhrase(cleaned) && (noSpeechProb > 0.2 || avgLogprob < -0.6)
    }

    static func isPhantomPhrase(_ text: String) -> Bool {
        phantomPhrases.contains(text.lowercased().filter { $0.isLetter || $0 == " " }.trimmingCharacters(in: .whitespaces))
    }

    /// Share of 50 ms frames between two times that carry sound.
    static func voicedShare(_ energies: [Float], from start: TimeInterval, to end: TimeInterval, threshold: Float = 0.006) -> Double {
        let lower = max(0, Int(start * 20)), upper = min(energies.count, Int((end * 20).rounded(.up)))
        guard lower < upper else { return 0 }
        return Double(energies[lower..<upper].filter { $0 >= threshold }.count) / Double(upper - lower)
    }

    /// Removes Whisper's special tokens and tidies whitespace.
    static func clean(_ text: String) -> String {
        text.replacing(/<\|[^|]*\|>/, with: "")
            .replacing(/\s+/, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Drops consecutive identical segments, which Whisper emits when it loops.
    static func removeRepeats(_ segments: [SpeechSegment]) -> [SpeechSegment] {
        var out: [SpeechSegment] = []
        for segment in segments {
            if let last = out.last, last.text.lowercased() == segment.text.lowercased(),
               segment.start - last.end < 5 {
                out[out.count - 1].end = segment.end
                continue
            }
            out.append(segment)
        }
        return out
    }
}
