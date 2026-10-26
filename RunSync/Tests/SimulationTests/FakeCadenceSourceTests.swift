import XCTest
import RunSyncDomain
import RunSyncSimulation

/// Source simulée (FR-004, §16.E) : reproduction déterministe du script imposé
/// 170 -> 176 -> 160 -> indisponible -> 170, sans capteur physique ni horloge murale.
final class FakeCadenceSourceTests: XCTestCase {

    private static let startDate = Date(timeIntervalSince1970: 1_700_000_000)

    func test_replayIsDeterministicAndFollowsTheScriptedValues() {
        let source = FakeCadenceSource(scenario: .demoFollow, tickInterval: 1.0, startDate: Self.startDate)
        let first = source.replay()
        let second = source.replay()

        XCTAssertEqual(first, second, "Le simulateur doit être strictement reproductible")
        XCTAssertEqual(first.count, 61)
        XCTAssertEqual(first[0].stepsPerMinute, 170)
        XCTAssertEqual(first[15].stepsPerMinute, 176)
        XCTAssertEqual(first[25].stepsPerMinute, 160)
        XCTAssertNil(first[35].stepsPerMinute)
        XCTAssertEqual(first[35].quality, .unavailable)
        XCTAssertEqual(first[55].stepsPerMinute, 170)
        XCTAssertFalse(first.contains { $0.stepsPerMinute == 0 }, "Aucun 0 inventé")
    }

    func test_timestampsAreAlignedWithTheTickInterval() {
        let source = FakeCadenceSource(scenario: .demoFollow, tickInterval: 2.0, startDate: Self.startDate)
        let samples = source.replay()
        XCTAssertEqual(samples.first?.timestamp, Self.startDate)
        for (index, sample) in samples.enumerated() {
            XCTAssertEqual(sample.timestamp, Self.startDate.addingTimeInterval(Double(index) * 2))
        }
    }

    func test_theAsyncStreamDeliversExactlyTheReplayedSamples() async throws {
        let source = FakeCadenceSource(
            scenario: .demoFollow,
            tickInterval: 1.0,
            startDate: Self.startDate,
            advance: { _ in } // aucun minuteur réel : test sans attente
        )
        var received: [CadenceSample] = []
        for try await sample in source.samples() {
            received.append(sample)
        }
        XCTAssertEqual(received, source.replay())
    }

    /// Démonstration déterministe du noyau M1 : script simulé -> filtre -> décision
    /// tempo, sans capteur ni audio (§16.F, scénarios A-G « démontrables »).
    func test_theDemoScriptDrivesEveryExpectedFollowState() {
        let source = FakeCadenceSource(scenario: .demoFollow, tickInterval: 1.0, startDate: Self.startDate)
        var filter = CadenceFilter()
        var controller = FollowController(policy: .standard)
        controller.start(at: Self.startDate)

        var reasons: [TempoDecisionReason] = []
        var rates: [Double] = []
        for sample in source.replay() {
            let assessment = filter.ingest(sample)
            let decision = controller.update(
                cadence: assessment,
                track: DemoLibrary.testTrack,
                candidates: DemoLibrary.tracks,
                now: sample.timestamp
            )
            reasons.append(decision.tempo.reason)
            rates.append(decision.tempo.appliedRate)
        }

        XCTAssertTrue(reasons.contains(.followingCadence))
        XCTAssertTrue(reasons.contains(.cadenceUnavailableHolding))
        XCTAssertTrue(reasons.contains(.returningToNeutral))
        XCTAssertTrue(rates.allSatisfy { $0 >= 0.95 && $0 <= 1.05 }, "Bornage ±5 % respecté sur tout le script")
        XCTAssertFalse(rates.contains(0), "Aucune cadence ni aucun tempo inventé")
        XCTAssertEqual(Set(rates).count > 1, true, "Le tempo a effectivement suivi la cadence")
    }

    func test_theDemoScriptOnlyEverReportsTheExpectedSensorGap() {
        let source = FakeCadenceSource(scenario: .demoFollow, tickInterval: 1.0, startDate: Self.startDate)
        var filter = CadenceFilter()
        for sample in source.replay() {
            let assessment = filter.ingest(sample)
            // Le script contient volontairement une plage « capteur indisponible » :
            // c'est le seul rejet attendu. Aucune valeur aberrante, non finie ou négative.
            XCTAssertTrue(
                assessment.lastRejection == nil || assessment.lastRejection == .sensorReportedNoValue,
                "Rejet inattendu : \(String(describing: assessment.lastRejection))"
            )
            if let value = assessment.rawSPM {
                XCTAssertTrue(CadenceUnits.isPlausibleSPM(value))
            }
        }
    }

    func test_aConstantScenarioProducesStableDecisions() {
        let source = FakeCadenceSource(
            scenario: .constant(170, durationSeconds: 20),
            tickInterval: 1.0,
            startDate: Self.startDate
        )
        var filter = CadenceFilter()
        var controller = FollowController(policy: .standard)
        // La session démarre avant le premier échantillon : la première mise à jour
        // dispose donc d'un intervalle réel (le rate ne saute pas instantanément).
        controller.start(at: Self.startDate.addingTimeInterval(-1))

        var rates: [Double] = []
        for sample in source.replay() {
            let assessment = filter.ingest(sample)
            rates.append(
                controller.update(
                    cadence: assessment,
                    track: DemoLibrary.testTrack,
                    candidates: DemoLibrary.tracks,
                    now: sample.timestamp
                ).tempo.appliedRate
            )
        }
        // La première mise à jour ne saute pas à la cible : la dérivée est limitée
        // à 0,01 par seconde (elle atteint donc 1,01 avant 1,01190476).
        XCTAssertEqual(rates.first ?? .nan, 1.01, accuracy: 1e-12)
        // Ensuite la cible est atteinte et ne bouge plus du tout : aucune oscillation.
        XCTAssertEqual(Set(rates.dropFirst()).count, 1)
        XCTAssertTrue(rates.dropFirst().allSatisfy { abs($0 - 170.0 / 168.0) < 1e-12 })
        XCTAssertEqual(rates.count, 21)
    }
}
