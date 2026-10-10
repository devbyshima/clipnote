import Foundation
import Testing
@testable import Ovyl

/// Stopping a note while the speech model is still getting ready ends the
/// note's wait at once, instead of after the load, and stands the model down.
struct SpeechModelStopTests {
    @Test(.timeLimit(.minutes(1)))
    func stoppingEndsTheWaitForTheModel() async throws {
        let folder = try #require(WhisperEngine.bundledFolder)
        // A fresh record, so the service expects nothing cached and loads for a while.
        let suite = "stop-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let service = WhisperService(folder: folder, defaultsSuite: suite)

        let waiting = Task { try await service.engine() }
        try await Task.sleep(for: .milliseconds(400))
        #expect(await service.phase != .ready, "The model loaded too fast to test stopping")

        let clock = ContinuousClock()
        let stopped = clock.now
        waiting.cancel()
        await #expect(throws: CancellationError.self) { try await waiting.value }
        #expect(clock.now - stopped < .seconds(1))

        await service.standDown()
        #expect(await service.phase == .idle)
    }
}
