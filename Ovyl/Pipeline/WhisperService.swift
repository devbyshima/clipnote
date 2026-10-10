import Foundation

/// Gets Whisper ready as fast as possible and keeps it efficient.
///
/// The Neural Engine is the fastest and most power-efficient place to run
/// Whisper (about 11x real time on the dev Mac), but the first time a Mac
/// loads it, Core ML compiles it for that Mac's Neural Engine, which takes
/// about 5 minutes. The hybrid engine (encoder on the GPU, decoder on the
/// Neural Engine) compiles in under a minute and runs about 4.5x real time.
///
/// So on a first launch the hybrid loads first and transcribes right away
/// while the Neural Engine compiles in the background; once that's done,
/// every video uses the Neural Engine and the hybrid is unloaded. Once the
/// Neural Engine has loaded on this Mac, later launches load it directly
/// in seconds, with the hybrid as a fallback if Core ML has evicted its cache
/// (after an OS update, for example).
actor WhisperService {
    static let shared = WhisperService()

    enum Phase: Equatable, Sendable {
        case idle
        /// Nothing can transcribe yet.
        case loading(firstTime: Bool)
        /// The hybrid transcribes while the Neural Engine compiles.
        case optimizing
        case ready
        case failed(String)
    }

    private let folder: URL?
    private var neuralEngine: WhisperEngine
    private let hybrid: WhisperEngine
    private let defaults: UserDefaults
    private let compiledKey: String
    private let compiledStamp: String

    private var neuralReady = false
    private var hybridReady = false
    private var neuralFailed: String?
    private var hybridFailed: String?
    private var warmUp: Task<Void, Never>?
    /// Counts each round of getting ready, so a load that finishes after
    /// its round was called off can tell, and put itself away.
    private var generation = 0
    private var waiters: [UUID: CheckedContinuation<WhisperEngine, any Error>] = [:]
    private var inUse: [WhisperEngine.Compute: Int] = [:]
    private var idleUnload: Task<Void, Never>?
    private var phaseObservers: [UUID: AsyncStream<Phase>.Continuation] = [:]
    private(set) var phase: Phase = .idle {
        didSet {
            guard phase != oldValue else { return }
            for observer in phaseObservers.values { observer.yield(phase) }
        }
    }

    /// How long the model stays loaded with no videos to transcribe.
    private let idleTimeout: Duration

    init(
        folder: URL? = WhisperEngine.bundledFolder,
        defaultsSuite: String? = nil,
        idleTimeout: Duration = .seconds(15 * 60)
    ) {
        self.folder = folder
        let defaults = defaultsSuite.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        self.defaults = defaults
        self.idleTimeout = idleTimeout
        compiledKey = "whisperNeuralEngineCompiled"
        // Core ML's compiled cache is tied to the model's location and the OS.
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        compiledStamp = "\(folder?.path ?? "none")|\(os)"
        let expectCached = defaults.string(forKey: compiledKey) == compiledStamp
        neuralEngine = WhisperEngine(
            folder: folder,
            compute: .neuralEngine,
            prewarm: !expectCached,
            priority: expectCached ? .userInitiated : .utility
        )
        hybrid = WhisperEngine(folder: folder, compute: .hybrid, priority: .userInitiated)
    }

    /// True when the Neural Engine has loaded at this location on this OS
    /// before, so its compiled form is most likely cached.
    var neuralEngineLikelyCached: Bool { defaults.string(forKey: compiledKey) == compiledStamp }

    func phases() -> AsyncStream<Phase> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Phase>.makeStream()
        continuation.yield(phase)
        phaseObservers[id] = continuation
        continuation.onTermination = { _ in Task { await self.removeObserver(id) } }
        return stream
    }

    private func removeObserver(_ id: UUID) {
        phaseObservers[id] = nil
    }

    /// Starts loading in the background, if it hasn't started.
    func prepare() {
        guard warmUp == nil else { return }
        neuralFailed = nil
        hybridFailed = nil
        generation += 1
        let round = generation
        let expectCached = neuralEngineLikelyCached
        phase = .loading(firstTime: !expectCached)
        warmUp = Task {
            if expectCached {
                // Usually ready in seconds. If not, Core ML lost its cache:
                // bring up the hybrid so videos don't wait for the compile.
                let fallback = Task {
                    try await Task.sleep(for: .seconds(8))
                    await self.loadHybrid(round)
                }
                await loadNeuralEngine(round)
                fallback.cancel()
            } else {
                await loadHybrid(round)
                guard !Task.isCancelled else { return }
                await loadNeuralEngine(round)
            }
        }
    }

    /// The fastest engine that's ready, waiting for the first one if needed.
    /// Waiting ends as soon as the caller is cancelled, as when a note is
    /// stopped while the model is still getting ready.
    func engine() async throws -> WhisperEngine {
        cancelIdleUnload()
        if neuralReady { return neuralEngine }
        if hybridReady { return hybrid }
        if warmUp == nil { prepare() }
        if let error = bothFailedError() { throw error }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Cancelled before this point, the handler below found nothing to end.
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters[id] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    /// Stops getting the model ready when nothing is waiting for it, so
    /// stopping a note stops its model activation too. A load under way
    /// can't be interrupted; it finishes out of sight, keeps Core ML's
    /// compiled cache for next time, and is put away.
    func standDown() {
        guard warmUp != nil, waiters.isEmpty, !neuralReady else { return }
        warmUp?.cancel()
        warmUp = nil
        generation += 1
        if hybridReady, inUse[.hybrid, default: 0] == 0 {
            hybridReady = false
            Task { await hybrid.unload() }
        }
        phase = .idle
    }

    /// Detects the spoken language from the first stretch of speech.
    func detectLanguage(samples: [Float]) async throws -> String {
        let engine = try await engine()
        begin(engine)
        defer { end(engine) }
        return try await engine.detectLanguage(samples: samples)
    }

    func transcribe(
        samples: [Float],
        language: String,
        progress: @Sendable (Double) -> Void
    ) async throws -> [SpeechSegment] {
        let engine = try await engine()
        begin(engine)
        defer { end(engine) }
        // Four chunks at a time measured 23% faster than one on the Neural
        // Engine, with identical text.
        return try await engine.transcribe(samples: samples, language: language, concurrency: 4, progress: progress)
    }

    /// Unloads everything now. For tests and benchmarks.
    func shutDown() async {
        cancelIdleUnload()
        warmUp?.cancel()
        neuralReady = false
        hybridReady = false
        await neuralEngine.unload()
        await hybrid.unload()
        phase = .idle
    }

    // MARK: Loading

    private func loadNeuralEngine(_ round: Int) async {
        guard round == generation else { return }
        do {
            try await neuralEngine.prepare()
            guard round == generation else {
                // Called off while it loaded: keep the compile, free the memory.
                defaults.set(compiledStamp, forKey: compiledKey)
                if warmUp == nil { await neuralEngine.unload() }
                return
            }
            neuralReady = true
            defaults.set(compiledStamp, forKey: compiledKey)
            phase = .ready
            resumeWaiters(with: neuralEngine)
            await unloadHybridIfIdle()
        } catch {
            guard round == generation else { return }
            neuralFailed = error.localizedDescription
            if hybridReady {
                // The hybrid keeps working; try the Neural Engine again next launch.
                phase = .ready
            } else if hybridFailed == nil {
                await loadHybrid(round)
            } else {
                failAll()
            }
        }
    }

    private func loadHybrid(_ round: Int) async {
        guard round == generation, !neuralReady, !hybridReady else { return }
        do {
            try await hybrid.prepare()
            guard round == generation else {
                if warmUp == nil { await hybrid.unload() }
                return
            }
            hybridReady = true
            if neuralReady {
                await unloadHybridIfIdle()
            } else {
                phase = neuralFailed == nil ? .optimizing : .ready
                resumeWaiters(with: hybrid)
            }
        } catch {
            guard round == generation else { return }
            hybridFailed = error.localizedDescription
            if neuralFailed != nil { failAll() }
        }
    }

    private func resumeWaiters(with engine: WhisperEngine) {
        let pending = waiters.values
        waiters = [:]
        for waiter in pending { waiter.resume(returning: engine) }
    }

    private func bothFailedError() -> (any Error)? {
        guard let neuralFailed, hybridFailed != nil else { return nil }
        return WhisperServiceError.unavailable(neuralFailed)
    }

    private func failAll() {
        let message = neuralFailed ?? hybridFailed ?? "Whisper couldn't load."
        phase = .failed(message)
        let pending = waiters.values
        waiters = [:]
        for waiter in pending { waiter.resume(throwing: WhisperServiceError.unavailable(message)) }
        warmUp = nil
    }

    // MARK: Memory

    private func begin(_ engine: WhisperEngine) {
        inUse[engine.compute, default: 0] += 1
    }

    private func end(_ engine: WhisperEngine) {
        inUse[engine.compute, default: 1] -= 1
        if engine.compute == .hybrid, neuralReady {
            Task { await unloadHybridIfIdle() }
        }
        scheduleIdleUnload()
    }

    /// Once the Neural Engine is ready the hybrid only costs memory.
    private func unloadHybridIfIdle() async {
        let loaded = await hybrid.isReady
        guard hybridReady || loaded, inUse[.hybrid, default: 0] == 0 else { return }
        hybridReady = false
        await hybrid.unload()
    }

    /// Frees the model's memory after a long idle stretch. Reloading from
    /// Core ML's cache takes a few seconds.
    private func scheduleIdleUnload() {
        idleUnload?.cancel()
        let timeout = idleTimeout
        idleUnload = Task {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            await self.unloadIfIdle()
        }
    }

    private func cancelIdleUnload() {
        idleUnload?.cancel()
        idleUnload = nil
    }

    private func unloadIfIdle() async {
        guard inUse.values.allSatisfy({ $0 == 0 }), waiters.isEmpty, neuralReady || hybridReady else { return }
        // Only after warm-up has finished, so a compile in progress isn't lost.
        guard neuralReady || neuralFailed != nil else { return }
        neuralReady = false
        hybridReady = false
        warmUp = nil
        await neuralEngine.unload()
        await hybrid.unload()
        // The compiled model is cached now, so the next load skips prewarming.
        neuralEngine = WhisperEngine(folder: folder, compute: .neuralEngine, prewarm: false, priority: .userInitiated)
        phase = .idle
    }
}

nonisolated enum WhisperServiceError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): "Whisper couldn't load. \(reason)"
        }
    }
}
