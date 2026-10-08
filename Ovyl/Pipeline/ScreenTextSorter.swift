import Foundation

/// Works out what the text read from a video's frames is.
///
/// - **Titles:** text on screen through most of the video, such as a
///   headline banner. Watermarks and account handles are dropped.
/// - **Subtitles:** short text that changes along with the speech. The note
///   keeps one version: the transcript, except where the speech engine was
///   unsure or missed words, or heard nothing while someone was talking;
///   there the subtitles are used. In a video without speech (music only,
///   or silent), the running captions carry the message, so they become the
///   note's text.
/// - **Slides and remarks:** everything else, grouped into moments. A short
///   line or two that isn't said aloud is a remark (commentary).
nonisolated enum ScreenTextSorter {
    struct Input: Sendable {
        var frames: [FrameText]
        /// Seconds between sampled frames.
        var interval: TimeInterval
        var duration: TimeInterval
        var transcript: [SpeechSegment]
        var sound: SoundProfile?
        var music: [TimeSpan] = []
    }

    struct Output: Sendable {
        var titles: [String] = []
        var transcript: [SpeechSegment] = []
        var moments: [TrackedMoment] = []
    }

    /// Text on screen in at least this share of sampled frames stays put.
    static let staticShare = 0.6
    /// Below this, a speech engine was unsure of what it heard.
    static let unsureConfidence = 0.5

    static func sort(_ input: Input) -> Output {
        let identified = identify(input.frames)
        let fixed = staticLines(identified, frameCount: input.frames.count, duration: input.duration)
        let frames = zip(input.frames, identified.ids).map { frame, ids in
            FrameText(time: frame.time, lines: zip(frame.lines, ids).filter { !fixed.ids.contains($0.1) }.map(\.0))
        }
        let cues = Self.cues(in: frames)

        var transcript: [SpeechSegment]
        var used: [Cue]
        if input.transcript.isEmpty {
            used = captions(in: cues)
            transcript = segments(from: used, interval: input.interval)
        } else {
            (transcript, used) = pick(cues, transcript: input.transcript, sound: input.sound, music: input.music, interval: input.interval)
        }

        // Everything not accounted for becomes slides and remarks. Frames and
        // cues are both in time order, so only the cues showing are checked.
        let usedInOrder = used.sorted { $0.start < $1.start }
        var next = 0
        var showing: [Cue] = []
        var tracker = MomentTracker()
        for frame in frames {
            while next < usedInOrder.count, usedInOrder[next].start <= frame.time {
                showing.append(usedInOrder[next])
                next += 1
            }
            showing.removeAll { $0.end < frame.time }
            let lines = frame.lines.filter { line in !showing.contains { $0.covers(line, at: frame.time) } }
            _ = tracker.observe(lines: lines, at: frame.time)
        }
        _ = tracker.finish(at: input.duration)
        let moments = MomentTracker.removeRepeats(tracker.moments).map(classified)
        transcript.sort { $0.start < $1.start }
        return Output(titles: fixed.titles, transcript: transcript, moments: moments)
    }

    // MARK: Static text

    struct LineStats: Sendable {
        var text: String
        var key: String
        var frames = 0
        var heights: [Double] = []
        var midYs: [Double] = []
    }

    struct Identified: Sendable {
        /// For each frame, an id per line; the same text has the same id.
        var ids: [[Int]]
        var stats: [LineStats]
    }

    /// Gives each distinct line an id, matching misreads of the same text.
    static func identify(_ frames: [FrameText]) -> Identified {
        var stats: [LineStats] = []
        var exact: [String: Int] = [:]
        var previous: [Int] = []
        var ids: [[Int]] = []
        for frame in frames {
            var frameIDs: [Int] = []
            var counted = Set<Int>()
            for line in frame.lines {
                let id: Int
                if let known = exact[line.key] ?? previous.first(where: { Similarity.isSameKey(stats[$0].key, line.key) }) {
                    id = known
                } else {
                    stats.append(LineStats(text: line.text, key: line.key))
                    id = stats.count - 1
                }
                exact[line.key] = id
                if counted.insert(id).inserted {
                    stats[id].frames += 1
                    stats[id].heights.append(line.height)
                    stats[id].midYs.append(line.midY)
                }
                frameIDs.append(id)
            }
            ids.append(frameIDs)
            previous = frameIDs
        }
        return Identified(ids: ids, stats: stats)
    }

    /// Lines that stay on screen, and the ones among them that read as a
    /// title, joined when a title runs over more than one line.
    static func staticLines(_ identified: Identified, frameCount: Int, duration: TimeInterval) -> (ids: Set<Int>, titles: [String]) {
        guard frameCount >= 5, duration >= 6 else { return ([], []) }
        let stats = identified.stats
        let ids = Set(stats.indices.filter { Double(stats[$0].frames) / Double(frameCount) >= staticShare })
        let content = ids.filter { !isWatermark(stats[$0].text, height: median(stats[$0].heights)) }
        // A headline is a line or two. More text that never changes is the
        // video's content (one slide, a document on screen), so it stays.
        guard content.count <= 2 else { return (ids.subtracting(content), []) }
        let lines = content.map { stats[$0] }.sorted { median($0.midYs) > median($1.midYs) }
        var titles: [[LineStats]] = []
        for line in lines {
            if let last = titles.last?.last,
               median(last.midYs) - median(line.midYs) <= 2.2 * max(median(last.heights), median(line.heights)) {
                titles[titles.count - 1].append(line)
            } else {
                titles.append([line])
            }
        }
        return (ids, titles.map { $0.map(\.text).joined(separator: " ") })
    }

    /// An account handle, a platform's or editing app's mark, a web address,
    /// or tiny print.
    static func isWatermark(_ text: String, height: Double) -> Bool {
        let lower = text.lowercased()
        if lower.contains("@") || height < 0.022 { return true }
        let marks = ["tiktok", "capcut", "instagram", "youtube", "reels", "shorts", "snapchat", "facebook"]
        if marks.contains(where: lower.contains) { return true }
        return lower.contains(/[a-z0-9-]+\.(com|net|org|io|co|app|tv|me|ly)\b/)
    }

    // MARK: Cues

    /// A block of text that stayed the same (or grew word by word) in one
    /// place on screen: a subtitle, a caption, a remark, or part of a slide.
    struct Cue: Sendable, Equatable {
        var start: TimeInterval
        /// The last sampled frame that showed it.
        var end: TimeInterval
        var text: String
        var key: String
        var midY: Double
        var lineCount: Int
        /// The most lines of other text on screen at the same time.
        var neighbours: Int
        /// Tallest line over shortest line; subtitle lines share one size.
        var sizeSpread: Double = 1

        var words: [String] { key.split(separator: " ").map(String.init) }
        var length: TimeInterval { end - start }

        /// Shaped like a subtitle: a few short lines of one size that change soon.
        var isCaptionShaped: Bool {
            lineCount <= 4 && length <= 10 && (1...40).contains(words.count) && sizeSpread <= 1.35
        }

        func covers(_ line: ScreenLine, at time: TimeInterval) -> Bool {
            time >= start && time <= end && abs(line.midY - midY) <= 0.15 && key.contains(line.key)
        }

        /// When it was likely on screen, given frames `interval` apart.
        func shown(_ interval: TimeInterval) -> (start: TimeInterval, end: TimeInterval) {
            (max(0, start - interval / 2), end + interval / 2)
        }
    }

    /// Lines close together vertically, top to bottom. The gap is measured
    /// against the smaller line, so a big title stays apart from body text.
    static func blocks(_ lines: [ScreenLine]) -> [[ScreenLine]] {
        var blocks: [[ScreenLine]] = []
        for line in lines.sorted(by: { $0.midY > $1.midY }) {
            if let last = blocks.last?.last, last.midY - line.midY <= 1.9 * min(last.height, line.height) {
                blocks[blocks.count - 1].append(line)
            } else {
                blocks.append([line])
            }
        }
        return blocks
    }

    static func cues(in frames: [FrameText]) -> [Cue] {
        var open: [Cue] = []
        var closed: [Cue] = []
        for frame in frames {
            var next: [Cue] = []
            for block in blocks(frame.lines) {
                let text = block.map(\.text).joined(separator: " ")
                let key = Similarity.normalize(text)
                guard !key.isEmpty else { continue }
                let midY = block.map(\.midY).reduce(0, +) / Double(block.count)
                let others = frame.lines.count - block.count
                let heights = block.map(\.height)
                let spread = (heights.max() ?? 1) / max(heights.min() ?? 1, 0.001)
                let grows = { (cue: Cue) in key.hasPrefix(cue.key + " ") }
                if let index = open.firstIndex(where: { abs($0.midY - midY) < 0.12 && (Similarity.isSameKey($0.key, key) || grows($0)) }) {
                    var cue = open.remove(at: index)
                    if grows(cue) {
                        cue.text = text
                        cue.key = key
                    }
                    cue.end = frame.time
                    cue.lineCount = max(cue.lineCount, block.count)
                    cue.neighbours = max(cue.neighbours, others)
                    cue.sizeSpread = max(cue.sizeSpread, spread)
                    next.append(cue)
                } else {
                    next.append(Cue(
                        start: frame.time, end: frame.time, text: text, key: key, midY: midY,
                        lineCount: block.count, neighbours: others, sizeSpread: spread
                    ))
                }
            }
            closed += open
            open = next
        }
        // Top to bottom among cues that appear together.
        return (closed + open).sorted { ($0.start, -$0.midY) < ($1.start, -$1.midY) }
    }

    // MARK: Subtitles with speech

    /// What was said, for matching against what was shown.
    struct Speech {
        let segments: [SpeechSegment]
        let words: [[String]]

        init(_ segments: [SpeechSegment]) {
            self.segments = segments
            words = segments.map { Similarity.words($0.text) }
        }

        /// The words of every segment that overlaps the window, in order.
        func saidWords(from start: TimeInterval, to end: TimeInterval) -> [String] {
            segments.indices.filter { segments[$0].end >= start && segments[$0].start <= end }.flatMap { words[$0] }
        }

        /// About how many words were said between two times.
        func wordCount(from start: TimeInterval, to end: TimeInterval) -> Double {
            segments.indices.reduce(0) { total, i in
                let segment = segments[i]
                let overlap = max(0, min(end, segment.end) - max(start, segment.start))
                return total + Double(words[i].count) * min(1, overlap / max(segment.end - segment.start, 0.1))
            }
        }

        /// How much of the cue was said nearby (coverage), and how much of
        /// what was said while it showed it accounts for (density). A
        /// subtitle scores high on both; a slide title read aloud covers
        /// little of the talk around it.
        func match(_ cue: Cue, interval: TimeInterval) -> (coverage: Double, density: Double) {
            let shown = cue.words
            guard !shown.isEmpty else { return (0, 0) }
            let common = Double(Similarity.commonWords(shown, saidWords(from: cue.start - 2.5, to: cue.end + 2.5)))
            let window = cue.shown(interval)
            let said = wordCount(from: window.start - 0.5, to: window.end + 0.5)
            return (common / Double(shown.count), said > 0 ? min(1, common / said) : 0)
        }
    }

    /// Where on screen subtitles sit: the height most cues share.
    struct Band: Equatable {
        var center: Double

        func contains(_ midY: Double) -> Bool { abs(midY - center) <= 0.1 }

        static func find(_ heights: [Double], minimumCount: Int) -> Band? {
            let best = heights.map { y in heights.filter { abs($0 - y) <= 0.1 } }.max { $0.count < $1.count }
            guard let best, best.count >= minimumCount else { return nil }
            return Band(center: ScreenTextSorter.median(best))
        }
    }

    /// Finds the subtitles that repeat the speech and decides, for each
    /// stretch, whether the transcript or the subtitles go in the note.
    /// Returns the transcript to use and the cues it accounts for.
    static func pick(
        _ cues: [Cue],
        transcript: [SpeechSegment],
        sound: SoundProfile?,
        music: [TimeSpan],
        interval: TimeInterval
    ) -> (transcript: [SpeechSegment], used: [Cue]) {
        let speech = Speech(transcript)
        let candidates = cues.filter(\.isCaptionShaped)
        let matches = candidates.map { speech.match($0, interval: interval) }
        // Most of it was said, or it holds most of what was said (when the
        // speech engine missed words, less of the subtitle matches).
        let strong = Set(candidates.indices.filter {
            let match = matches[$0]
            return candidates[$0].words.count >= 3
                && ((match.coverage >= 0.7 && match.density >= 0.4) || (match.coverage >= 0.5 && match.density >= 0.7))
        })
        // Word-by-word captions are too short to match on their own; they
        // count once enough of them sit where the subtitles are.
        let whole = Set(candidates.indices.filter { matches[$0].coverage >= 0.99 && candidates[$0].length <= 4 })
        let band = Band.find(strong.union(whole).map { candidates[$0].midY }, minimumCount: 3)

        func overlaps(_ cue: Cue, _ segment: SpeechSegment) -> Bool {
            let shown = cue.shown(interval)
            return shown.start < segment.end && shown.end > segment.start
        }
        var spoken: [Cue] = []
        var unmatched: [Cue] = []
        for (i, cue) in candidates.enumerated() {
            let inBand = band?.contains(cue.midY) == true
            let isSpoken = strong.contains(i)
                || (inBand && (whole.contains(i) || (matches[i].coverage >= 0.7 && matches[i].density >= 0.25)))
                || (inBand && transcript.contains { ($0.confidence ?? 1) < unsureConfidence && overlaps(cue, $0) })
            if isSpoken { spoken.append(cue) } else if inBand { unmatched.append(cue) }
        }

        // Each subtitle goes with the stretch of speech it overlaps most.
        var result = transcript
        var assigned: [Int: [Cue]] = [:]
        for cue in spoken {
            let shown = cue.shown(interval)
            let best = result.indices.max { a, b in
                overlap(shown, result[a]) < overlap(shown, result[b])
            }
            if let best, overlap(shown, result[best]) > 0 || distance(shown, result[best]) <= 2 {
                assigned[best, default: []].append(cue)
            }
        }
        for (index, cues) in assigned {
            let segment = result[index]
            let ordered = cues.sorted { $0.start < $1.start }
            let subtitle = merged(ordered.map(\.text))
            let heard = Similarity.words(segment.text), shown = Similarity.words(subtitle)
            let common = Similarity.commonWords(heard, shown)
            let unsure = (segment.confidence ?? 1) < unsureConfidence
            let shownTime = ordered.reduce(0) { $0 + overlap($1.shown(interval), segment) }
            let covered = shownTime >= 0.6 * max(segment.end - segment.start, 0.1)
            let missedWords = shown.count >= heard.count + 2 && Double(common) >= 0.8 * Double(heard.count)
            if (unsure && covered && shown.count >= 2 && common < shown.count) || missedWords {
                result[index].text = subtitle
                result[index].source = .subtitles
            }
        }

        // Subtitles while someone talks but the speech engine heard nothing.
        var used = spoken
        if let sound {
            for cue in unmatched {
                let shown = cue.shown(interval)
                guard !transcript.contains(where: { overlaps(cue, $0) }),
                      TimeSpan.share(from: shown.start, to: shown.end, in: music) < 0.5,
                      sound.speech(from: shown.start, to: shown.end) >= 0.5
                else { continue }
                result.append(SpeechSegment(start: shown.start, end: shown.end, text: cue.text, source: .subtitles))
                used.append(cue)
            }
        }
        return (result, used)
    }

    private static func overlap(_ shown: (start: TimeInterval, end: TimeInterval), _ segment: SpeechSegment) -> TimeInterval {
        max(0, min(shown.end, segment.end) - max(shown.start, segment.start))
    }

    private static func distance(_ shown: (start: TimeInterval, end: TimeInterval), _ segment: SpeechSegment) -> TimeInterval {
        max(segment.start - shown.end, shown.start - segment.end, 0)
    }

    // MARK: Captions without speech

    /// The running captions of a video with no speech: caption-shaped text
    /// that keeps changing in one place, with little else on screen.
    static func captions(in cues: [Cue]) -> [Cue] {
        let candidates = cues.filter { $0.lineCount <= 4 && $0.length <= 15 && $0.key.count <= 220 && $0.lineCount + $0.neighbours <= 5 }
        guard let band = Band.find(candidates.map(\.midY), minimumCount: 2) else { return [] }
        let captions = candidates.filter { band.contains($0.midY) }
        let lengths = captions.map(\.length).sorted()
        guard lengths[lengths.count / 2] <= 10 else { return [] }
        return captions
    }

    static func segments(from cues: [Cue], interval: TimeInterval) -> [SpeechSegment] {
        var segments: [SpeechSegment] = []
        for (index, cue) in cues.enumerated() {
            var text = index > 0 ? trimmingOverlap(cue.text, after: cues[index - 1].text) : cue.text
            guard !text.isEmpty else { continue }
            if index + 1 < cues.count, needsFullStop(text, before: cues[index + 1].text) { text += "." }
            let shown = cue.shown(interval)
            segments.append(SpeechSegment(start: shown.start, end: shown.end, text: text, source: .subtitles))
        }
        return segments
    }

    /// Captions often end without a full stop, then the next one starts a
    /// new sentence with a capital.
    static func needsFullStop(_ text: String, before next: String) -> Bool {
        guard let last = text.last, !".!?…:;,。！？".contains(last), let first = next.first, first.isUppercase else { return false }
        let firstWord = next.split(separator: " ").first.map(String.init) ?? ""
        return !["I", "I'm", "I've", "I'll", "I'd", "I’m", "I’ve", "I’ll", "I’d"].contains(firstWord)
    }

    /// Subtitles joined into one text, without the words that roll over
    /// from one to the next.
    static func merged(_ texts: [String]) -> String {
        var result = ""
        for text in texts {
            let next = result.isEmpty ? text : trimmingOverlap(text, after: result)
            if !next.isEmpty { result += result.isEmpty ? next : " " + next }
        }
        return result
    }

    /// `text` without its opening words when `previous` ends with them.
    static func trimmingOverlap(_ text: String, after previous: String) -> String {
        let tokens = text.split(separator: " ").map(String.init)
        let before = Similarity.words(previous)
        // Normalized words, and how many tokens make up the first n of them.
        var words: [String] = []
        var tokensFor: [Int: Int] = [:]
        for (index, token) in tokens.enumerated() {
            words += Similarity.words(token)
            tokensFor[words.count] = index + 1
        }
        for count in stride(from: min(words.count, before.count), through: 1, by: -1) {
            // One shared word is often chance ("the", "and"); two or more is a roll-over.
            guard count >= 2 || count == words.count,
                  let used = tokensFor[count],
                  Array(before.suffix(count)) == Array(words.prefix(count))
            else { continue }
            return tokens.dropFirst(used).joined(separator: " ")
        }
        return text
    }

    // MARK: Moments

    /// A short line or two with nothing that reads as a heading is a remark.
    static func classified(_ moment: TrackedMoment) -> TrackedMoment {
        var moment = moment
        let characters = moment.lines.reduce(0) { $0 + $1.text.count }
        if NoteComposer.titleLine(of: moment) == nil, moment.lines.count <= 3, characters <= 160 {
            moment.kind = .commentary
        }
        return moment
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.sorted()[values.count / 2]
    }
}
