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
    /// Off until turned on in Settings › Formatting.
    var smartFormatting = false
    /// Leaves songs and other music out of the transcript.
    var skipsMusic = true

    static let engineKey = "engine"
    static let languageKey = "language"
    static let readsScreenTextKey = "readsScreenText"
    static let frameIntervalKey = "frameInterval"
    static let smartFormattingKey = "smartFormatting"
    static let skipsMusicKey = "skipsMusic"

    static func fromDefaults(_ defaults: UserDefaults = .standard) -> PipelineOptions {
        var options = PipelineOptions()
        options.engine = EnginePreference(rawValue: defaults.string(forKey: engineKey) ?? "") ?? .automatic
        let language = defaults.string(forKey: languageKey) ?? ""
        options.language = language.isEmpty ? nil : language
        options.readsScreenText = defaults.object(forKey: readsScreenTextKey) as? Bool ?? true
        let interval = defaults.double(forKey: frameIntervalKey)
        options.frameInterval = interval > 0 ? interval : 1
        options.smartFormatting = defaults.object(forKey: smartFormattingKey) as? Bool ?? false
        options.skipsMusic = defaults.object(forKey: skipsMusicKey) as? Bool ?? true
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

/// Runs a video through every step: audio, music, speech, on-screen text,
/// formatting. Speech and on-screen text are read at the same time. Pictures
/// take a shorter path: their text is read and formatted.
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
        async let screen = readScreen(asset: asset, enabled: readsScreen, duration: safeDuration, interval: options.frameInterval, board: progress)
        let transcript = try await speech
        let reading = try await screen

        try Task.checkCancellation()
        await progress.set(.formatting, 0)
        // Sort the screen's text into titles, subtitles, slides and remarks,
        // and settle on one version where subtitles repeat the speech.
        let sorted = ScreenTextSorter.sort(.init(
            frames: reading.frames,
            interval: reading.interval,
            duration: safeDuration,
            transcript: transcript.segments,
            sound: transcript.sound,
            music: transcript.music
        ))
        let moments = await ScreenTextReader.saveThumbnails(for: sorted.moments, asset: asset, folder: thumbnailsFolder)
        let fromSpeech = sorted.transcript.contains { $0.source == .speech }
        let fromSubtitles = sorted.transcript.contains { $0.source == .subtitles }
        let engine: String? = switch (fromSpeech, fromSubtitles) {
        case (true, true): transcript.engine.map { "\($0) and subtitles" } ?? "Subtitles"
        case (false, true): "On-screen captions"
        default: transcript.engine
        }
        let language = transcript.language
            ?? TextLanguage.detect(sorted.transcript.map(\.text).joined(separator: " "))

        let board = progress
        let composed = await NoteComposer.compose(
            .init(
                fileName: url.lastPathComponent,
                duration: safeDuration,
                segments: sorted.transcript,
                moments: moments,
                screenTitles: sorted.titles,
                music: transcript.music,
                language: language,
                engine: engine,
                useSmartFormatting: options.smartFormatting,
                notice: transcript.notice
            ),
            progress: { fraction in Task { await board.set(.formatting, fraction) } }
        )
        withExtendedLifetime(warmFormatter) {}
        Self.removeUnusedThumbnails(in: thumbnailsFolder, keeping: Set(composed.content.screenMoments.compactMap(\.thumbnail)))
        return PipelineResult(title: composed.title, content: composed.content, duration: safeDuration)
    }

    /// Reads the text in each picture and makes one note from all of them.
    func run(
        pictures urls: [URL],
        options: PipelineOptions,
        thumbnailsFolder: URL,
        onUpdate: @escaping @Sendable (PipelineUpdate) -> Void
    ) async throws -> PipelineResult {
        let progress = ProgressBoard(handler: onUpdate)
        await progress.configure(hasSpeech: false, hasScreen: true, isPictures: true)
        let warmFormatter = options.smartFormatting ? SmartFormatter.prewarmedSession() : nil
        try? FileManager.default.createDirectory(at: thumbnailsFolder, withIntermediateDirectories: true)

        var pictures: [NoteComposer.Picture] = []
        var unreadable: [String] = []
        for (index, url) in urls.enumerated() {
            try Task.checkCancellation()
            await progress.set(.readingScreen, Double(index) / Double(urls.count))
            guard let image = PictureReader.image(at: url) else {
                unreadable.append(url.lastPathComponent)
                continue
            }
            let page = try await PictureReader.read(image)
            let thumbnail = ScreenTextReader.saveThumbnail(image, folder: thumbnailsFolder, name: "picture-\(index + 1).jpg", maxWidth: 1600)
            pictures.append(.init(name: url.lastPathComponent, thumbnail: thumbnail, page: page))
        }
        await progress.set(.readingScreen, 1)
        guard !pictures.isEmpty else { throw ClipError.notPicture }

        try Task.checkCancellation()
        await progress.set(.formatting, 0)
        let board = progress
        let notice = unreadable.isEmpty ? nil : "Some pictures couldn't be opened: \(unreadable.joined(separator: ", "))."
        let composed = await NoteComposer.compose(
            pictures: pictures,
            useSmartFormatting: options.smartFormatting,
            notice: notice,
            progress: { fraction in Task { await board.set(.formatting, fraction) } }
        )
        withExtendedLifetime(warmFormatter) {}
        Self.removeUnusedThumbnails(in: thumbnailsFolder, keeping: Set(composed.content.pictures.compactMap(\.thumbnail)))
        return PipelineResult(title: composed.title, content: composed.content, duration: 0)
    }

    struct Transcript: Sendable {
        var segments: [SpeechSegment] = []
        var language: String?
        var engine: String?
        var notice: String?
        var sound: SoundProfile?
        /// Songs and other music left out of the transcript.
        var music: [TimeSpan] = []
    }

    private func transcribe(asset: AVURLAsset, hasAudio: Bool, duration: TimeInterval, options: PipelineOptions, board: ProgressBoard) async throws -> Transcript {
        guard hasAudio else { return Transcript() }

        await board.set(.extractingAudio, 0)
        let samples = try await AudioLoader.loadSamples(from: asset, duration: duration) { fraction in
            Task { await board.set(.extractingAudio, fraction) }
        }
        guard !samples.isEmpty else { return Transcript() }

        // Hear where the music is, so songs aren't transcribed as speech.
        await board.set(.listening, 0)
        let sound = try? await SoundClassifier.profile(samples: samples)
        let music = options.skipsMusic ? sound?.musicSpans() ?? [] : []
        await board.set(.listening, 1)
        let speechSamples = SoundProfile.silencing(music, in: samples)
        let soundFrames = AudioChunker.frameEnergies(speechSamples, frame: AudioLoader.sampleRate / 20).filter { $0 >= 0.004 }
        if soundFrames.count < 20 {
            // Under a second of sound outside the music: no need for a speech engine.
            await board.set(.transcribing, 1)
            return Transcript(sound: sound, music: music)
        }
        func outsideMusic(_ segments: [SpeechSegment]) -> [SpeechSegment] {
            segments.filter { TimeSpan.share(from: $0.start, to: $0.end, in: music) < 0.5 }
        }

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
                        language = try await WhisperService.shared.detectLanguage(samples: speechSamples)
                    }
                    let detected = language ?? "en"
                    await board.set(.transcribing, 0)
                    let segments = try await WhisperService.shared.transcribe(samples: speechSamples, language: detected) { fraction in
                        Task { await board.set(.transcribing, fraction) }
                    }
                    return Transcript(segments: outsideMusic(segments), language: detected, engine: WhisperEngine.displayName, sound: sound, music: music)
                case .apple, .automatic:
                    await board.set(.transcribing, 0)
                    let segments = try await AppleSpeechEngine.transcribe(asset: asset, language: language, duration: duration) { fraction in
                        Task { await board.set(.transcribing, fraction) }
                    }
                    let code = language ?? Locale.current.language.languageCode?.identifier
                    return Transcript(segments: outsideMusic(segments), language: code, engine: AppleSpeechEngine.displayName, sound: sound, music: music)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }
                failures.append(error.localizedDescription)
            }
        }
        let reason = failures.last ?? "No speech engine was available."
        return Transcript(language: language, notice: "The speech couldn't be transcribed. \(reason)", sound: sound, music: music)
    }

    private func readScreen(asset: AVURLAsset, enabled: Bool, duration: TimeInterval, interval: TimeInterval, board: ProgressBoard) async throws -> ScreenReading {
        guard enabled else { return ScreenReading() }
        do {
            return try await ScreenTextReader.read(asset: asset, duration: duration, interval: interval) { fraction in
                Task { await board.set(.readingScreen, fraction) }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // On-screen text is a bonus; a failure here shouldn't lose the transcript.
            return ScreenReading()
        }
    }

    private static func removeUnusedThumbnails(in folder: URL, keeping used: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for file in files where !used.contains(file) {
            try? FileManager.default.removeItem(at: folder.appending(path: file))
        }
    }
}

/// Combines the progress of steps that run side by side into one bar.
actor ProgressBoard {
    enum Step: Hashable, CaseIterable {
        case preparing, extractingAudio, listening, loadingModel, transcribing, readingScreen, formatting

        /// How the step is worded on a note.
        func label(isPictures: Bool = false, isSlowModelLoad: Bool = false) -> String {
            switch self {
            case .preparing: "Opening video"
            case .extractingAudio: "Reading audio"
            case .listening: "Listening for music"
            case .loadingModel: isSlowModelLoad
                ? "Getting the speech model ready (first time only, about a minute)"
                : "Loading the speech model"
            case .transcribing: "Transcribing speech"
            case .readingScreen: isPictures ? "Reading the pictures" : "Reading on-screen text"
            case .formatting: "Writing the note"
            }
        }

        /// The step a note's stage line names first, in any of its wordings.
        /// Steps that run side by side are joined with " · ".
        static func first(in stage: String) -> Step? {
            let first = stage.components(separatedBy: " · ").first ?? stage
            return allCases.first { step in
                [false, true].contains { pictures in
                    [false, true].contains { slow in step.label(isPictures: pictures, isSlowModelLoad: slow) == first }
                }
            }
        }
    }

    /// The stage line while no step is running, between one and the next.
    static let between = "Working"

    private let handler: @Sendable (PipelineUpdate) -> Void
    private var fractions: [Step: Double] = [:]
    private var active: [Step] = []
    private var hasSpeech = true
    private var hasScreen = true
    private var isPictures = false
    private var lastSent = -1.0
    private var isSlowModelLoad = false

    init(handler: @escaping @Sendable (PipelineUpdate) -> Void) {
        self.handler = handler
    }

    func markSlowModelLoad() {
        isSlowModelLoad = true
        handler(PipelineUpdate(stage: stageText(), fraction: overallFraction()))
    }

    func configure(hasSpeech: Bool, hasScreen: Bool, isPictures: Bool = false) {
        self.hasSpeech = hasSpeech
        self.hasScreen = hasScreen
        self.isPictures = isPictures
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
        if hasSpeech { weights += [(.extractingAudio, 0.05), (.listening, 0.03), (.transcribing, 0.52)] }
        if hasScreen { weights.append((.readingScreen, hasSpeech ? 0.25 : 0.7)) }
        weights.append((.formatting, 0.15))
        let total = weights.reduce(0) { $0 + $1.1 }
        let done = weights.reduce(0) { $0 + (fractions[$1.0] ?? 0) * $1.1 }
        return total > 0 ? done / total : 0
    }

    private func stageText() -> String {
        let current = active.map { $0.label(isPictures: isPictures, isSlowModelLoad: isSlowModelLoad) }
        return current.isEmpty ? Self.between : current.joined(separator: " · ")
    }
}
