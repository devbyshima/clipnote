import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Vision

/// One line of text Vision read in a frame.
nonisolated struct ScreenLine: Sendable, Equatable {
    var text: String
    /// Vertical centre, 0 at the bottom of the frame and 1 at the top.
    var midY: Double
    /// Line height as a fraction of the frame height.
    var height: Double
    var isTitle: Bool
    /// Normalized text used for matching.
    let key: String

    init(text: String, midY: Double, height: Double, isTitle: Bool = false) {
        self.text = text
        self.midY = midY
        self.height = height
        self.isTitle = isTitle
        self.key = Similarity.normalize(text)
    }
}

/// A stretch of video where roughly the same text stayed on screen.
nonisolated struct TrackedMoment: Sendable, Equatable {
    var start: TimeInterval
    var end: TimeInterval
    var lines: [ScreenLine]
    var thumbnail: String?
}

/// Samples frames, reads their text with Vision, and groups what it reads
/// into moments (a slide, a title card, a code listing).
nonisolated enum ScreenTextReader {
    @concurrent static func read(
        asset: AVURLAsset,
        duration: TimeInterval,
        interval baseInterval: TimeInterval,
        thumbnailsFolder: URL,
        progress: @Sendable (Double) -> Void
    ) async throws -> [TrackedMoment] {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard duration > 0, !videoTracks.isEmpty else { return [] }

        // Longer videos are sampled less often so a two-hour talk stays quick,
        // and less often again when the Mac is saving power or running hot.
        var interval = duration > 3600 ? max(baseInterval, 3) : duration > 1200 ? max(baseInterval, 2) : baseInterval
        let info = ProcessInfo.processInfo
        if info.isLowPowerModeEnabled || info.thermalState == .serious || info.thermalState == .critical {
            interval = max(interval * 2, 2)
        }
        let times = stride(from: min(0.5, duration / 2), to: duration, by: interval).map {
            CMTime(seconds: $0, preferredTimescale: 600)
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1920)
        let tolerance = CMTime(seconds: min(0.25, interval / 4), preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        try? FileManager.default.createDirectory(at: thumbnailsFolder, withIntermediateDirectories: true)

        var tracker = MomentTracker()
        var lastSignature: [Float]?
        var lastReadTime = -TimeInterval.infinity
        var lastLines: [ScreenLine] = []
        var pendingImage: CGImage?
        var done = 0

        for await element in generator.images(for: times) {
            try Task.checkCancellation()
            done += 1
            if done % 4 == 0 { progress(Double(done) / Double(times.count)) }
            guard case .success(let requested, let image, _) = element else { continue }
            let time = requested.seconds

            // Skip OCR when the frame looks the same as the last one read,
            // but re-read every few seconds in case a small change slipped by.
            let signature = FrameSignature.make(image)
            if let lastSignature, let signature, time - lastReadTime < 6,
               FrameSignature.difference(lastSignature, signature) < 0.002 {
                if tracker.observe(lines: lastLines, at: time) == .continued { pendingImage = image }
                continue
            }
            lastSignature = signature
            lastReadTime = time

            let lines = try await recognize(image)
            lastLines = lines
            switch tracker.observe(lines: lines, at: time) {
            case .started(let closed):
                if let closed { saveThumbnail(of: closed, image: pendingImage, folder: thumbnailsFolder, tracker: &tracker) }
                pendingImage = image
            case .continued:
                pendingImage = image
            case .ended(let closed):
                saveThumbnail(of: closed, image: pendingImage, folder: thumbnailsFolder, tracker: &tracker)
                pendingImage = nil
            case .none:
                break
            }
        }

        if let closed = tracker.finish(at: duration) {
            saveThumbnail(of: closed, image: pendingImage, folder: thumbnailsFolder, tracker: &tracker)
        }
        progress(1)
        return MomentTracker.removeRepeats(tracker.moments)
    }

    static func recognize(_ image: CGImage) async throws -> [ScreenLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.minimumTextHeightFraction = 0.018

        let observations = try await request.perform(on: image)
        let lines = observations.compactMap { observation -> ScreenLine? in
            guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.4 else { return nil }
            let text = candidate.string
                .replacing(/\s+/, with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.filter({ $0.isLetter || $0.isNumber }).count >= 2 else { return nil }
            let box = observation.boundingBox.cgRect
            return ScreenLine(text: text, midY: box.midY, height: box.height, isTitle: observation.isTitle)
        }
        // Reading order: top to bottom.
        return lines.sorted { $0.midY > $1.midY }
    }

    private static func saveThumbnail(of index: Int, image: CGImage?, folder: URL, tracker: inout MomentTracker) {
        guard let image, tracker.moments.indices.contains(index) else { return }
        let name = "\(UUID().uuidString).jpg"
        let url = folder.appending(path: name)
        guard let small = downscale(image, maxWidth: 640),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, small, [kCGImageDestinationLossyCompressionQuality: 0.78] as CFDictionary)
        if CGImageDestinationFinalize(destination) { tracker.moments[index].thumbnail = name }
    }

    private static func downscale(_ image: CGImage, maxWidth: Int) -> CGImage? {
        guard image.width > maxWidth else { return image }
        let width = maxWidth
        let height = max(1, Int(Double(image.height) * Double(maxWidth) / Double(image.width)))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

/// Groups per-frame text into moments as frames come in.
nonisolated struct MomentTracker {
    enum Event: Equatable {
        /// A new moment began; `closed` is the index of the moment it replaced.
        case started(closed: Int?)
        case continued
        /// Text left the screen; `closed` is the index of the finished moment.
        case ended(closed: Int)
    }

    var moments: [TrackedMoment] = []
    private var current: TrackedMoment?

    /// Fraction of a frame's lines that must match the current moment to
    /// count as the same moment (slide builds add lines and still match).
    static let sameMomentThreshold = 0.5
    /// A moment that keeps growing (scrolling text) is split at this size.
    static let maxLinesPerMoment = 120

    mutating func observe(lines: [ScreenLine], at time: TimeInterval) -> Event? {
        if lines.isEmpty {
            guard let finished = current else { return nil }
            moments.append(finished)
            current = nil
            return .ended(closed: moments.count - 1)
        }
        if var moment = current, moment.lines.count < Self.maxLinesPerMoment,
           Self.overlap(lines, moment.lines) >= Self.sameMomentThreshold {
            for line in lines where !moment.lines.contains(where: { Similarity.isSameKey($0.key, line.key) }) {
                moment.lines.append(line)
            }
            moment.end = time
            current = moment
            return .continued
        }
        var closed: Int?
        if let finished = current {
            moments.append(finished)
            closed = moments.count - 1
        }
        current = TrackedMoment(start: time, end: time, lines: lines)
        return .started(closed: closed)
    }

    mutating func finish(at time: TimeInterval) -> Int? {
        guard var finished = current else { return nil }
        finished.end = max(finished.end, min(time, finished.end + 1))
        moments.append(finished)
        current = nil
        return moments.count - 1
    }

    static func overlap(_ lines: [ScreenLine], _ existing: [ScreenLine]) -> Double {
        guard !lines.isEmpty else { return 0 }
        let matched = lines.filter { line in existing.contains { Similarity.isSameKey($0.key, line.key) } }
        return Double(matched.count) / Double(lines.count)
    }

    /// Keeps each line only the first time it appears, so a watermark or a
    /// slide revisited later is not repeated, and drops moments left empty.
    static func removeRepeats(_ moments: [TrackedMoment]) -> [TrackedMoment] {
        var seen: [String] = []
        var seenKeys = Set<String>()
        var result: [TrackedMoment] = []
        for var moment in moments {
            moment.lines = moment.lines.filter { line in
                let key = line.key
                if seenKeys.contains(key) { return false }
                // Fuzzy-compare against recent lines only, to stay fast on long videos.
                if seen.suffix(400).contains(where: { Similarity.ratio($0, key) >= 0.88 }) { return false }
                seen.append(key)
                seenKeys.insert(key)
                return true
            }
            if !moment.lines.isEmpty { result.append(moment) }
        }
        return result
    }
}

/// A small grayscale fingerprint of a frame, to spot frames that haven't changed.
nonisolated enum FrameSignature {
    static let width = 96, height = 54

    static func make(_ image: CGImage) -> [Float]? {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels.map { Float($0) / 255 } : nil
    }

    /// Share of pixels that changed noticeably, 0 (identical) to 1. Counting
    /// changed pixels, rather than averaging, catches a new line of text on
    /// an otherwise identical slide while ignoring compression noise.
    static func difference(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 1 }
        var changed = 0
        for i in a.indices where abs(a[i] - b[i]) > 0.12 { changed += 1 }
        return Float(changed) / Float(a.count)
    }
}

nonisolated enum Similarity {
    /// Lowercased letters and digits with single spaces.
    static func normalize(_ text: String) -> String {
        String(text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " })
            .split(separator: " ")
            .joined(separator: " ")
    }

    static func isSame(_ a: String, _ b: String) -> Bool {
        isSameKey(normalize(a), normalize(b))
    }

    static func isSameKey(_ a: String, _ b: String) -> Bool {
        a == b || ratio(a, b) >= 0.85
    }

    /// 1 minus normalized edit distance, on already-normalized strings.
    static func ratio(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let x = Array(a), y = Array(b)
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        // Lengths far apart can't be similar enough; skip the work.
        if Double(min(x.count, y.count)) / Double(max(x.count, y.count)) < 0.7 { return 0 }
        var previous = Array(0...y.count)
        var current = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            current[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return 1 - Double(previous[y.count]) / Double(max(x.count, y.count))
    }

    /// Share of `text`'s words that also appear in `reference`.
    static func wordCoverage(of text: String, in reference: Set<String>) -> Double {
        let words = normalize(text).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return 0 }
        return Double(words.filter { reference.contains($0) }.count) / Double(words.count)
    }
}
