import AVFoundation

/// Decodes a video's soundtrack to 16 kHz mono samples, the format Whisper reads.
nonisolated enum AudioLoader {
    static let sampleRate = 16_000

    @concurrent static func loadSamples(
        from asset: AVURLAsset,
        duration: TimeInterval,
        progress: @Sendable (Double) -> Void
    ) async throws -> [Float] {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { return [] }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        let provider = reader.outputProvider(for: output)
        try reader.start()

        var samples: [Float] = []
        samples.reserveCapacity(Int(max(duration, 1) * Double(sampleRate)) + sampleRate)
        var lastReport = 0.0

        while let ready = try await provider.next() {
            try Task.checkCancellation()
            ready.withUnsafeSampleBuffer { buffer in
                guard let block = CMSampleBufferGetDataBuffer(buffer) else { return }
                let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
                guard count > 0 else { return }
                let start = samples.count
                samples.append(contentsOf: repeatElement(0, count: count))
                let status = samples.withUnsafeMutableBytes { raw in
                    CMBlockBufferCopyDataBytes(
                        block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size,
                        destination: raw.baseAddress!.advanced(by: start * MemoryLayout<Float>.size)
                    )
                }
                if status != kCMBlockBufferNoErr { samples.removeLast(count) }
            }

            if duration > 0 {
                let fraction = min(1, Double(samples.count) / (duration * Double(sampleRate)))
                if fraction - lastReport >= 0.02 {
                    lastReport = fraction
                    progress(fraction)
                }
            }
        }

        if reader.status == .failed { throw reader.error ?? ClipError.unreadableAudio }
        if reader.status == .cancelled { throw CancellationError() }
        progress(1)
        return samples
    }
}

/// Splits audio into windows of at most 30 seconds, cutting in the quietest
/// spot near each boundary so words are not split, and marking windows with
/// no speech-level sound so they can be skipped.
nonisolated enum AudioChunker {
    struct Chunk: Equatable, Sendable {
        var range: Range<Int>
        var isSilent: Bool
        /// The part of `range` with sound, plus a little margin. Whisper tends
        /// to invent words in silence, so only this part is transcribed.
        var speech: Range<Int>
    }

    static func chunks(
        for samples: [Float],
        sampleRate: Int = AudioLoader.sampleRate,
        maxSeconds: Double = 29,
        minSeconds: Double = 8,
        searchSeconds: Double = 8,
        silenceRMS: Float = 0.004
    ) -> [Chunk] {
        guard !samples.isEmpty else { return [] }
        let frame = sampleRate / 20 // 50 ms
        let energies = frameEnergies(samples, frame: frame)
        let maxFrames = Int(maxSeconds * Double(sampleRate)) / frame
        let searchFrames = Int(searchSeconds * Double(sampleRate)) / frame
        let minFrames = Int(minSeconds * Double(sampleRate)) / frame

        var chunks: [Chunk] = []
        var startFrame = 0
        while startFrame < energies.count {
            var endFrame = min(energies.count, startFrame + maxFrames)
            if endFrame < energies.count {
                endFrame = cutPoint(in: energies, from: startFrame + minFrames, to: endFrame,
                                    searchFrames: searchFrames, silenceRMS: silenceRMS)
            }
            let peak = energies[startFrame..<endFrame].max() ?? 0
            let range = (startFrame * frame)..<min(samples.count, endFrame * frame)
            if !range.isEmpty {
                var speech = range
                let voiced = (startFrame..<endFrame).filter { energies[$0] >= silenceRMS }
                if let first = voiced.first, let last = voiced.last {
                    let lower = max(range.lowerBound, (first - 5) * frame)   // 250 ms before
                    let upper = min(range.upperBound, (last + 11) * frame)   // 550 ms after
                    if lower < upper { speech = lower..<upper }
                }
                chunks.append(Chunk(range: range, isSilent: peak < silenceRMS, speech: speech))
            }
            startFrame = endFrame
        }
        return chunks
    }

    /// Where to end a chunk: at the last pause in the allowed range, so the
    /// chunk is long but ends between words; failing that, at the quietest
    /// 250 ms near the limit.
    static func cutPoint(in energies: [Float], from lower: Int, to upper: Int, searchFrames: Int, silenceRMS: Float) -> Int {
        func smoothed(_ f: Int) -> Float {
            let window = energies[max(0, f - 2)...min(energies.count - 1, f + 2)]
            return window.reduce(0, +) / Float(window.count)
        }
        let lower = min(max(1, lower), upper - 1)
        if let pause = (lower..<upper).last(where: { smoothed($0) < silenceRMS }) {
            return pause
        }
        var best = upper, bestEnergy = Float.greatestFiniteMagnitude
        for f in max(lower, upper - searchFrames)..<upper {
            let e = smoothed(f)
            if e < bestEnergy { bestEnergy = e; best = f }
        }
        return best
    }

    /// The window of `seconds` that starts at the first chunk with sound,
    /// used to detect the spoken language.
    static func firstSpeech(in samples: [Float], seconds: Double = 30) -> ArraySlice<Float> {
        let chunk = chunks(for: samples).first { !$0.isSilent }
        let start = chunk?.range.lowerBound ?? 0
        let end = min(samples.count, start + Int(seconds * Double(AudioLoader.sampleRate)))
        return samples[start..<end]
    }

    static func frameEnergies(_ samples: [Float], frame: Int) -> [Float] {
        stride(from: 0, to: samples.count, by: frame).map { start in
            let end = min(samples.count, start + frame)
            var sum: Float = 0
            for i in start..<end { sum += samples[i] * samples[i] }
            return (sum / Float(end - start)).squareRoot()
        }
    }
}
