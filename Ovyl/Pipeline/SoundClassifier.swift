import AVFoundation
import SoundAnalysis

/// What a soundtrack sounds like over time, from Apple's built-in sound
/// classifier: where people talk, and where there's a song or other music.
nonisolated struct SoundProfile: Sendable, Equatable {
    struct Window: Sendable, Equatable {
        var start: TimeInterval
        var end: TimeInterval
        var speech: Double
        /// Singing, rapping, a choir or humming.
        var vocals: Double
        var music: Double

        /// Singing or music with little talking, or singing stronger than the
        /// talking. Speech over background music is not music: the
        /// classifier rates clear speech well above 0.5 even with music.
        var isMusic: Bool {
            (speech < 0.5 && (vocals >= 0.35 || music >= 0.6)) || (vocals >= 0.5 && vocals > speech)
        }
    }

    var windows: [Window] = []
    /// Length of the audio; the last window can end a little before it.
    var duration: TimeInterval = 0

    /// Stretches of music, joined across short breaks. Stings shorter than
    /// `minimumLength` are left alone.
    func musicSpans(minimumLength: TimeInterval = 4, bridging gap: TimeInterval = 1) -> [TimeSpan] {
        var spans: [TimeSpan] = []
        for window in windows where window.isMusic {
            if let last = spans.last, window.start - last.end <= gap {
                spans[spans.count - 1].end = max(last.end, window.end)
            } else {
                spans.append(TimeSpan(start: window.start, end: window.end))
            }
        }
        // Music in the last window runs to the end of the audio.
        if let last = spans.last, let final = windows.last, last.end >= final.end, duration > last.end {
            spans[spans.count - 1].end = duration
        }
        return spans.filter { $0.length >= minimumLength }
    }

    /// The highest speech confidence between two times.
    func speech(from start: TimeInterval, to end: TimeInterval) -> Double {
        windows.filter { $0.end > start && $0.start < end }.map(\.speech).max() ?? 0
    }

    /// The samples with music turned to silence, so a speech engine skips it.
    /// Each span is trimmed a little so words at its edges survive.
    static func silencing(_ spans: [TimeSpan], in samples: [Float], sampleRate: Int = AudioLoader.sampleRate) -> [Float] {
        guard !spans.isEmpty else { return samples }
        var quiet = samples
        for span in spans {
            let lower = max(0, Int((span.start + 0.3) * Double(sampleRate)))
            let upper = min(quiet.count, Int((span.end - 0.3) * Double(sampleRate)))
            if lower < upper { quiet.replaceSubrange(lower..<upper, with: repeatElement(0, count: upper - lower)) }
        }
        return quiet
    }
}

/// Runs Apple's sound classifier over decoded audio.
nonisolated enum SoundClassifier {
    static let speechLabels = ["speech"]
    static let vocalLabels = ["singing", "choir_singing", "rapping", "humming", "yodeling"]
    static let musicLabels = ["music"]

    @concurrent static func profile(samples: [Float], sampleRate: Int = AudioLoader.sampleRate) async throws -> SoundProfile {
        guard !samples.isEmpty,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 1, interleaved: false)
        else { return SoundProfile() }

        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        // Three seconds is enough to hear a melody; half overlap gives a
        // result every 1.5 seconds.
        request.windowDuration = CMTime(seconds: 3, preferredTimescale: 1000)
        request.overlapFactor = 0.5

        let analyzer = SNAudioStreamAnalyzer(format: format)
        let observer = Observer()
        try analyzer.add(request, withObserver: observer)

        // Results arrive during each `analyze` call, on this thread.
        let block = sampleRate * 4
        var position = 0
        while position < samples.count {
            try Task.checkCancellation()
            let count = min(block, samples.count - position)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                  let channel = buffer.floatChannelData?[0]
            else { break }
            buffer.frameLength = AVAudioFrameCount(count)
            samples.withUnsafeBufferPointer { source in
                channel.update(from: source.baseAddress! + position, count: count)
            }
            analyzer.analyze(buffer, atAudioFramePosition: AVAudioFramePosition(position))
            position += count
        }
        analyzer.completeAnalysis()
        if let error = observer.error { throw error }
        return SoundProfile(
            windows: observer.windows.sorted { $0.start < $1.start },
            duration: Double(samples.count) / Double(sampleRate)
        )
    }

    private final class Observer: NSObject, SNResultsObserving, @unchecked Sendable {
        private let lock = NSLock()
        private var collected: [SoundProfile.Window] = []
        private var failure: (any Error)?

        var windows: [SoundProfile.Window] { lock.withLock { collected } }
        var error: (any Error)? { lock.withLock { failure } }

        func request(_ request: any SNRequest, didProduce result: any SNResult) {
            guard let result = result as? SNClassificationResult else { return }
            func strongest(_ labels: [String]) -> Double {
                labels.compactMap { result.classification(forIdentifier: $0)?.confidence }.max() ?? 0
            }
            let window = SoundProfile.Window(
                start: result.timeRange.start.seconds,
                end: CMTimeRangeGetEnd(result.timeRange).seconds,
                speech: strongest(SoundClassifier.speechLabels),
                vocals: strongest(SoundClassifier.vocalLabels),
                music: strongest(SoundClassifier.musicLabels)
            )
            lock.withLock { collected.append(window) }
        }

        func request(_ request: any SNRequest, didFailWithError error: any Error) {
            lock.withLock { failure = error }
        }
    }
}
