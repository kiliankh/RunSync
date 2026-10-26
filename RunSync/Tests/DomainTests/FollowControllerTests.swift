import XCTest
import RunSyncDomain
import RunSyncSimulation

/// Mode Follow : scénario D (cadence indisponible), scénario F (pas de pompage),
/// T007 (suivi soutenu borné), T009 (changement de morceau seulement si durable),
/// T010 (HOLD puis retour politique contrôlé).
final class FollowControllerTests: XCTestCase {

    private static let startDate = Date(timeIntervalSince1970: 1_700_000_000)
    private static let followTiming = FollowTimingConfiguration(
        rateSlewPerSecond: 0.01,
        sustainedOutOfRangeSeconds: 15,
        cadenceLossHoldSeconds: 5,
        returnToNeutralSeconds: 10
    )

    /// Rejoue un scénario déterministe dans le filtre puis le contrôleur Follow.
    private func run(
        scenario: CadenceScenario,
        track: TrackDescriptor? = DemoLibrary.testTrack,
        candidates: [TrackDescriptor] = DemoLibrary.tracks,
        tickInterval: TimeInterval = 1.0
    ) -> (decisions: [FollowDecision], assessments: [CadenceAssessment]) {
        var filter = CadenceFilter()
        var controller = FollowController(policy: .standard, timing: Self.followTiming)
        controller.start(at: Self.startDate)

        var decisions: [FollowDecision] = []
        var assessments: [CadenceAssessment] = []
        for sample in scenario.replay(tickInterval: tickInterval, startingAt: Self.startDate) {
            let assessment = filter.ingest(sample)
            assessments.append(assessment)
            decisions.append(
                controller.update(
                    cadence: assessment,
                    track: track,
                    candidates: candidates,
                    now: sample.timestamp
                )
            )
        }
        return (decisions, assessments)
    }

    // MARK: - Scénario A appliqué au contrôleur

    func test_followConvergesToTheRequiredRateOfScenarioA() {
        let result = run(scenario: .constant(170, durationSeconds: 10))
        let finalRate = result.decisions.last?.tempo.appliedRate ?? 0
        XCTAssertEqual(finalRate, 170.0 / 168.0, accuracy: 1e-9)
        XCTAssertEqual(result.decisions.last?.tempo.reason, .followingCadence)
        XCTAssertEqual(result.decisions.last?.tempo.stepsPerBeat, 1)
        XCTAssertEqual(result.decisions.last?.tempo.quality, .good)
    }

    // MARK: - T007

    func test_T007_sustainedCadenceIsFollowedAndStaysWithinAdjustmentBounds() {
        let result = run(scenario: .constant(176, durationSeconds: 60))
        let rates = result.decisions.map(\.tempo.appliedRate)

        XCTAssertTrue(rates.allSatisfy { $0 >= 0.95 && $0 <= 1.05 }, "Le bornage ±5 % est toujours respecté")
        XCTAssertTrue(rates.allSatisfy { $0 <= 176.0 / 168.0 + 1e-12 }, "Aucun dépassement de la cible")
        XCTAssertEqual(rates.last ?? 0, 176.0 / 168.0, accuracy: 0.01)
        XCTAssertEqual(result.decisions.last?.tempo.reason, .followingCadence)
        XCTAssertEqual(result.decisions.last?.tempo.isClamped, false)

        // Le rate ne fait que croître vers la cible : aucune oscillation.
        var previous = rates.first ?? 0
        for rate in rates.dropFirst() {
            XCTAssertGreaterThanOrEqual(rate + 1e-12, previous)
            previous = rate
        }
    }

    func test_theRateDerivativeIsLimitedToOnePointOfPercentPerSecond() {
        let result = run(scenario: .constant(170, durationSeconds: 5))
        let rates = result.decisions.map(\.tempo.appliedRate)
        // 1 s entre deux mises à jour : la dérivée maximale est de 0.01 par seconde.
        for (previous, next) in zip(rates, rates.dropFirst()) {
            XCTAssertLessThanOrEqual(abs(next - previous), 0.01 + 1e-12)
        }
    }

    // MARK: - Scénario F / T004-like

    func test_scenarioF_stableCadenceProducesASingleConstantRate() {
        var filter = CadenceFilter()
        var controller = FollowController(policy: .standard, timing: Self.followTiming)
        controller.start(at: Self.startDate)

        var rates: [Double] = []
        for (index, value) in [169.0, 170.0, 169.0, 171.0, 170.0, 170.0, 169.0, 171.0].enumerated() {
            let now = Self.startDate.addingTimeInterval(Double(index + 1))
            let assessment = filter.ingest(
                CadenceSample(
                    timestamp: now,
                    stepsPerMinute: value,
                    quality: .good,
                    sourceIdentifier: "test"
                )
            )
            let decision = controller.update(
                cadence: assessment,
                track: DemoLibrary.testTrack,
                candidates: DemoLibrary.tracks,
                now: now
            )
            rates.append(decision.tempo.appliedRate)
        }
        XCTAssertEqual(Set(rates).count, 1, "Aucun pompage : le rate reste strictement constant")
        XCTAssertEqual(rates.first ?? 0, 169.0 / 168.0, accuracy: 1e-12)
    }

    // MARK: - Scénario C appliqué au contrôleur

    func test_anOutOfRangeCadenceIsClampedAndKeepsPlayingTheCurrentTrack() {
        let result = run(scenario: .constant(150, durationSeconds: 20))
        let decision = result.decisions[10]
        XCTAssertEqual(decision.tempo.reason, .clampedToMaximumAdjustment)
        XCTAssertEqual(decision.tempo.appliedRate, 0.95, accuracy: 1e-12)
        XCTAssertEqual(decision.tempo.requiredRate ?? 0, 150.0 / 168.0, accuracy: 1e-12)
        XCTAssertEqual(decision.tempo.isClamped, true)
        // Le morceau courant n'est pas coupé : la suggestion arrive seulement après.
        XCTAssertNil(decision.recommendedTrackID)
    }

    // MARK: - T009

    func test_T009_trackChangeIsProposedOnlyAfterASustainedDeviation() {
        let result = run(scenario: .constant(150, durationSeconds: 60))

        // Avant le seuil de 15 s : aucune suggestion, le morceau courant continue.
        XCTAssertTrue(result.decisions.prefix(15).allSatisfy { $0.recommendedTrackID == nil })
        // Après le seuil : suggestion d'un morceau admissible (150 BPM pour 150 SPM).
        XCTAssertEqual(result.decisions[20].recommendedTrackID, DemoLibrary.slowTrackID)
        XCTAssertEqual(result.decisions[20].tempo.reason, .noAdmissibleTrack)
        // La suggestion n'est jamais une coupure : le tempo appliqué reste borné.
        XCTAssertEqual(result.decisions[20].tempo.appliedRate, 0.95, accuracy: 1e-12)
    }

    // MARK: - Scénario D / T010

    func test_scenarioDAndT010_cadenceLossHoldsTheRateThenReturnsToNeutral() {
        var filter = CadenceFilter()
        var controller = FollowController(policy: .standard, timing: Self.followTiming)
        controller.start(at: Self.startDate)

        func step(_ sample: CadenceSample) -> (CadenceAssessment, FollowDecision) {
            let assessment = filter.ingest(sample)
            let decision = controller.update(
                cadence: assessment,
                track: DemoLibrary.testTrack,
                candidates: DemoLibrary.tracks,
                now: sample.timestamp
            )
            return (assessment, decision)
        }

        // 1) Suivi établi à 170 SPM.
        var syncedRate: Double = 0
        for second in 1...10 {
            let (_, decision) = step(
                CadenceSample(
                    timestamp: Self.startDate.addingTimeInterval(Double(second)),
                    stepsPerMinute: 170,
                    quality: .good,
                    sourceIdentifier: "test"
                )
            )
            syncedRate = decision.tempo.appliedRate
        }
        XCTAssertEqual(syncedRate, 170.0 / 168.0, accuracy: 1e-9)

        // 2) Capteur indisponible : dégradation explicite, rate maintenu, jamais 0.
        var lastAssessment: CadenceAssessment?
        var lastDecision: FollowDecision?
        for second in 11...21 {
            let now = Self.startDate.addingTimeInterval(Double(second))
            let (assessment, decision) = step(.sensorUnavailable(timestamp: now, sourceIdentifier: "test"))
            lastAssessment = assessment
            lastDecision = decision
            XCTAssertNil(assessment.rawSPM, "Aucune valeur de cadence n'est fabriquée")
            XCTAssertNotEqual(decision.tempo.appliedRate, 0)
            XCTAssertEqual(decision.tempo.appliedRate, syncedRate, accuracy: 1e-9)
        }
        XCTAssertEqual(lastAssessment?.quality, .unavailable)
        XCTAssertEqual(lastDecision?.tempo.reason, .cadenceUnavailableHolding)
        XCTAssertTrue(lastDecision?.isCadenceUnavailable == true)

        // 3) Après le maintien, retour doux vers le tempo original en 10 s.
        var finalRate: Double = 0
        for second in 22...32 {
            let now = Self.startDate.addingTimeInterval(Double(second))
            let (_, decision) = step(.sensorUnavailable(timestamp: now, sourceIdentifier: "test"))
            finalRate = decision.tempo.appliedRate
            if second >= 23 {
                XCTAssertEqual(decision.tempo.reason, .returningToNeutral)
            }
        }
        XCTAssertEqual(finalRate, 1.0, accuracy: 1e-9)

        // 4) La cadence revient : le suivi reprend sans état fantôme.
        let now = Self.startDate.addingTimeInterval(33)
        let (_, resumed) = step(
            CadenceSample(timestamp: now, stepsPerMinute: 170, quality: .good, sourceIdentifier: "test")
        )
        XCTAssertEqual(resumed.tempo.reason, .followingCadence)
        XCTAssertFalse(resumed.isCadenceUnavailable)
    }

    func test_aTrackWithoutBPMIsNeverPresentedAsSynchronisable() {
        let result = run(
            scenario: .constant(170, durationSeconds: 5),
            track: DemoLibrary.bpmUnknownTrack
        )
        let decision = result.decisions.last
        XCTAssertEqual(decision?.tempo.reason, .bpmUnknown)
        XCTAssertNil(decision?.tempo.requiredRate)
        XCTAssertEqual(decision?.tempo.appliedRate ?? .nan, 1.0, accuracy: 1e-12)
        XCTAssertEqual(decision?.recommendedTrackID, DemoLibrary.testTrackID)
    }

    func test_startingTheControllerTwiceDoesNotAccumulateState() {
        var controller = FollowController(policy: .standard, timing: Self.followTiming)
        controller.start(at: Self.startDate)
        var filter = CadenceFilter()
        let assessment = filter.ingest(
            CadenceSample(
                timestamp: Self.startDate.addingTimeInterval(1),
                stepsPerMinute: 170,
                quality: .good,
                sourceIdentifier: "test"
            )
        )
        _ = controller.update(
            cadence: assessment,
            track: DemoLibrary.testTrack,
            candidates: DemoLibrary.tracks,
            now: assessment.timestamp
        )
        XCTAssertGreaterThan(controller.currentAppliedRate, 1.0)

        controller.start(at: Self.startDate.addingTimeInterval(2))
        XCTAssertEqual(controller.currentAppliedRate, 1.0, "Un redémarrage remet le tempo original")
    }

    func test_withoutAnActiveTrackTheTempoStaysAtTheOriginalRate() {
        let result = run(scenario: .constant(170, durationSeconds: 5), track: nil)
        let decision = result.decisions.last
        XCTAssertEqual(decision?.tempo.appliedRate ?? .nan, 1.0, accuracy: 1e-12)
        XCTAssertEqual(decision?.tempo.reason, .bpmUnknown)
        XCTAssertEqual(decision?.recommendedTrackID, DemoLibrary.testTrackID)
    }
}
