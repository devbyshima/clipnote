import AVFoundation
import Foundation

nonisolated enum EnginePreference: String, CaseIterable, Identifiable, Sendable {
    /// Whisper first for accuracy, Apple Speech if Whisper can't run.
    case automatic
    case whisper
    case apple

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: "Automatic"
        case .whisper: "Whisper only"
        case .apple: "Apple Speech first"
        }
    }
}

nonisolated struct PipelineOptions: Sendable {
    var engine: EnginePreference = .automatic
    /// ISO language code, or nil to detect it.
    var language: String?
    var readsScreenText = true
    var frameInterval: TimeInterval = 1
    var smartFormatting = true

    static let engineKey = "engine"
    static let languageKey = "language"
    static let readsScreenTextKey = "readsScreenText"
    static let frameIntervalKey = "frameInterval"
    static let smartFormattingKey = "smartFormatting"

    static func fromDefaults(_ defaults: UserDefaults = .standard) -> PipelineOptions {
        var options = PipelineOptions()
        options.engine = EnginePreference(rawValue: defaults.string(forKey: engineKey) ?? "") ?? .automatic
        let language = defaults.string(forKey: languageKey) ?? ""
        options.language = language.isEmpty ? nil : language
        options.readsScreenText = defaults.object(forKey: readsScreenTextKey) as? Bool ?? true
        let interval = defaults.double(forKey: frameIntervalKey)
        options.frameInterval = interval > 0 ? interval : 1
        options.smartFormatting = defaults.object(forKey: smartFormattingKey) as? Bool ?? true
        return options
    }
}

nonisolated struct PipelineUpdate: Sendable {
    var stage: String
    var fraction: Double
}

nonisolated struct PipelineResult: Sendable {
    var title: String
    var content: NoteContent
    var duration: TimeInterval
}

/// Runs a video through every step: audio, speech, on-screen text, formatting.
/// Speech and on-screen text are read at the same time.
actor ClipPipeline {
    func run(
        url: URL,
        options: PipelineOptions,
        thumbnailsFolder: URL,
        onUpdate: @escaping @Sendable (PipelineUpdate) -> Void
    ) async throws -> PipelineResult {
        let progress = ProgressBoard(handler: onUpdate)
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw ClipError.fileMissing }

        let asset = AVURLAsset(url: url)
        await progress.set(.preparing, 0)
        let duration = try await asset.load(.duration).seconds
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard !audioTracks.isEmpty || !videoTracks.isEmpty else { throw ClipError.notMedia }
        let safeDuration = duration.isFinite ? duration : 0
        await progress.set(.preparing, 1)
        let readsScreen = options.readsScreenText && !videoTracks.isEmpty
        await progress.configure(hasSpeech: !audioTracks.isEmpty, hasScreen: readsScreen)

        // Loads Apple Intelligence while speech and screen are read, so the
        // formatting step doesn't wait for it.
        let warmFormatter = options.smartFormatting ? SmartFormatter.prewarmedSession() : nil

        async let speech = transcribe(asset: asset, hasAudio: !audioTracks.isEmpty, duration: safeDuration, options: options, board: progress)
        async let screen = readScreen(asset: asset, enabled: readsScreen, duration: safeDuration, interval: options.frameInterval, folder: thumbnailsFolder, board: progress)
        let transcript = try await speech
        let moments = try await screen

        try Task.checkCancellation()
        await progress.set(.formatting, 0)
        let board = progress
        let composed = await NoteComposer.compose(
            .init(
                fileName: url.lastPathComponent,
                duration: safeDuration,
                segments: transcript.segments,
                moments: moments,
                language: transcript.language,
                engine: transcript.engine,
                useSmartFormatting: options.smartFormatting,
                notice: transcript.notice
            ),
            progress: { fraction in Task { await board.set(.formatting, fraction) } }
        )
        withExtendedLifetime(warmFormatter) {}
        Self.removeUnusedThumbnails(in: thumbnailsFolder, keeping: composed.content.screenMoments)
        return PipelineResult(title: composed.title, content: composed.content, duration: safeDuration)
    }

    struct Transcript: Sendable {
        var segments: [SpeechSegment] = []
        var language: String?
        var engine: String?
        var notice: String?
    }

    private func transcribe(asset: AVURLAsset, hasAudio: Bool, duration: TimeInterval, options: PipelineOptions, board: ProgressBoard) async throws -> Transcript {
        guard hasAudio else { return Transcript() }

        await board.set(.extractingAudio, 0)
        let samples = try await AudioLoader.loadSamples(from: asset, duration: duration) { fraction in
            Task { await board.set(.extractingAudio, fraction) }
        }
        guard !samples.isEmpty else { return Transcript() }

        let order: [EnginePreference] = switch options.engine {
        case .automatic: WhisperEngine.isBundled ? [.whisper, .apple] : [.apple]
        case .whisper: [.whisper]
        case .apple: [.apple, .whisper]
        }

        var language = options.language
        var failures: [String] = []
        for engine in order {
            do {
                try Task.checkCancellation()
                switch engine {
                case .whisper:
                    await board.set(.loadingModel, 0)
                    // More than a few seconds means the first-time setup; say so.
                    let slowNotice = Task {
                        try await Task.sleep(for: .seconds(5))
                        await board.markSlowModelLoad()
                    }
                    defer { slowNotice.cancel() }
                    _ = try await WhisperService.shared.engine()
                    slowNotice.cancel()
                    await board.set(.loadingModel, 1)
                    if language == nil {
                        language = try await WhisperService.shared.detectLanguage(samples: samples)
                    }
                    let detected = language ?? "en"
                    await board.set(.transcribing, 0)
                    let segments = try await WhisperService.shared.transcribe(samples: samples, language: detected) { fraction in
                        Task { await board.set(.transcribing, fraction) }
                    }
                    return Transcript(segments: segments, language: detected, engine: WhisperEngine.displayName)
                case .apple, .automatic:
                    await board.set(.transcribing, 0)
                    let segments = try await AppleSpeechEngine.transcribe(asset: asset, language: language, duration: duration) { fraction in
                        Task { await board.set(.transcribing, fraction) }
                    }
                    let code = language ?? Locale.current.language.languageCode?.identifier
                    return Transcript(segments: segments, language: code, engine: AppleSpeechEngine.displayName)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }
                failures.append(error.localizedDescription)
            }
        }
        let reason = failures.last ?? "No speech engine was available."
        return Transcript(language: language, notice: "The speech couldn't be transcribed. \(reason)")
    }

    private func readScreen(asset: AVURLAsset, enabled: Bool, duration: TimeInterval, interval: TimeInterval, folder: URL, board: ProgressBoard) async throws -> [TrackedMoment] {
        guard enabled else { return [] }
        do {
            return try await ScreenTextReader.read(
                asset: asset, duration: duration, interval: interval, thumbnailsFolder: folder
            ) { fraction in
                Task { await board.set(.readingScreen, fraction) }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // On-screen text is a bonus; a failure here shouldn't lose the transcript.
            return []
        }
    }

    private static func removeUnusedThumbnails(in folder: URL, keeping moments: [ScreenMoment]) {
        let used = Set(moments.compactMap(\.thumbnail))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for file in files where !used.contains(file) {
            try? FileManager.default.removeItem(at: folder.appending(path: file))
        }
    }
}

/// Combines the progress of steps that run side by side into one bar.
actor ProgressBoard {
    enum Step: Hashable {
        case preparing, extractingAudio, loadingModel, transcribing, readingScreen, formatting
    }

    private let handler: @Sendable (PipelineUpdate) -> Void
    private var fractions: [Step: Double] = [:]
    private var active: [Step] = []
    private var hasSpeech = true
    private var hasScreen = true
    private var lastSent = -1.0
    private var isSlowModelLoad = false

    init(handler: @escaping @Sendable (PipelineUpdate) -> Void) {
        self.handler = handler
    }

    func markSlowModelLoad() {
        isSlowModelLoad = true
        handler(PipelineUpdate(stage: stageText(), fraction: overallFraction()))
    }

    func configure(hasSpeech: Bool, hasScreen: Bool) {
        self.hasSpeech = hasSpeech
        self.hasScreen = hasScreen
    }

    func set(_ step: Step, _ fraction: Double) {
        fractions[step] = max(fractions[step] ?? 0, min(1, fraction))
        if fraction < 1 {
            if !active.contains(step) { active.append(step) }
        } else {
            active.removeAll { $0 == step }
        }
        let overall = overallFraction()
        guard abs(overall - lastSent) >= 0.004 || fraction == 0 || fraction >= 1 else { return }
        lastSent = overall
        handler(PipelineUpdate(stage: stageText(), fraction: overall))
    }

    private func overallFraction() -> Double {
        // Weights reflect typical time spent in each step.
        var weights: [(Step, Double)] = []
        if hasSpeech { weights += [(.extractingAudio, 0.06), (.transcribing, 0.54)] }
        if hasScreen { weights.append((.readingScreen, hasSpeech ? 0.25 : 0.7)) }
        weights.append((.formatting, 0.15))
        let total = weights.reduce(0) { $0 + $1.1 }
        let done = weights.reduce(0) { $0 + (fractions[$1.0] ?? 0) * $1.1 }
        return total > 0 ? done / total : 0
    }

    private func stageText() -> String {
        let labels: [Step: String] = [
            .preparing: "Opening video",
            .extractingAudio: "Reading audio",
            .loadingModel: isSlowModelLoad
                ? "Getting the speech model ready (first time only, about a minute)"
                : "Loading the speech model",
            .transcribing: "Transcribing speech",
            .readingScreen: "Reading on-screen text",
            .formatting: "Writing the note",
        ]
        let current = active.compactMap { labels[$0] }
        return current.isEmpty ? "Working" : current.joined(separator: " · ")
    }
}
