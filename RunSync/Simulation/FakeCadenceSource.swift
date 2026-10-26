import Foundation
import RunSyncDomain

/// Source de cadence simulée, déterministe (FR-004, RS-004, §16.E).
///
/// Deux usages :
/// - `replay()` : suite d'échantillons pure, sans horloge, pour les tests ;
/// - `samples()` : flux asynchrone pour l'écran de démonstration, avec une
///   fonction d'attente injectable — les tests passent une attente nulle et
///   s'exécutent sans minuteur réel.
public struct FakeCadenceSource: CadenceSource {
    public let scenario: CadenceScenario
    public let tickInterval: TimeInterval
    public let startDate: Date
    private let advance: @Sendable (TimeInterval) async throws -> Void

    public init(
        scenario: CadenceScenario = .demoFollow,
        tickInterval: TimeInterval = 1.0,
        startDate: Date = Date(timeIntervalSince1970: 1_700_000_000),
        advance: (@Sendable (TimeInterval) async throws -> Void)? = nil
    ) {
        self.scenario = scenario
        self.tickInterval = tickInterval.isFinite && tickInterval > 0 ? tickInterval : 1.0
        self.startDate = startDate
        self.advance = advance ?? { seconds in
            let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    }

    /// Suite complète d'échantillons, sans temporisation ni horloge murale.
    public func replay() -> [CadenceSample] {
        scenario.replay(
            tickInterval: tickInterval,
            startingAt: startDate,
            sourceIdentifier: "simulation.cadence"
        )
    }

    public func samples() -> AsyncThrowingStream<CadenceSample, Error> {
        let samples = replay()
        let advance = self.advance
        let tick = self.tickInterval
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for sample in samples {
                        try Task.checkCancellation()
                        continuation.yield(sample)
                        try await advance(tick)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
