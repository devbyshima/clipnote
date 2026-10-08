import AVFoundation
import Speech

/// Apple's on-device speech model (SpeechAnalyzer). Fast, and used as the
/// fallback when Whisper can't run, or first when chosen in Settings.
nonisolated enum AppleSpeechEngine {
    static let displayName = "Apple Speech"

    static var isAvailable: Bool { SpeechTranscriber.isAvailable }

    @concurrent static func transcribe(
        asset: AVURLAsset,
        language: String?,
        duration: TimeInterval,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [SpeechSegment] {
        guard SpeechTranscriber.isAvailable else { throw ClipError.appleSpeechUnavailable }

        let wanted = language.map { Locale(identifier: $0) } ?? Locale.current
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: wanted) else {
            let name = Locale.current.localizedString(forIdentifier: wanted.identifier) ?? wanted.identifier
            throw ClipError.appleSpeechLocaleUnsupported(name)
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange, .transcriptionConfidence]
        )

        // The language model is part of macOS; it's fetched once per language.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let provider = try await AssetInputSequenceProvider.provider(from: asset, compatibleWith: [transcriber])
        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .lingering)
        )

        let collector = Task {
            var segments: [SpeechSegment] = []
            for try await result in transcriber.results where result.isFinal {
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                let start = result.range.start.seconds
                let end = result.range.end.seconds
                if duration > 0, end.isFinite { progress(min(1, end / duration)) }
                guard !text.isEmpty, start.isFinite else { continue }
                let confidences = result.text.runs.compactMap(\.transcriptionConfidence)
                let confidence = confidences.isEmpty ? nil : confidences.reduce(0, +) / Double(confidences.count)
                segments.append(SpeechSegment(start: start, end: end.isFinite ? end : start, text: text, confidence: confidence))
            }
            return segments
        }

        do {
            if let last = try await analyzer.analyzeSequence(provider.analyzerInputs) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            collector.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }

        let segments = try await withTaskCancellationHandler {
            try await collector.value
        } onCancel: {
            collector.cancel()
        }
        progress(1)
        return segments.sorted { $0.start < $1.start }
    }
}
