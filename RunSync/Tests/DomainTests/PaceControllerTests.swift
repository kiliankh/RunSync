import XCTest
import RunSyncDomain
import RunSyncSimulation

/// Mode Pace : scénario E (cible musicale indépendante de la cadence observée)
/// et T008 (la variation observée ne déplace pas la cible).
final class PaceControllerTests: XCTestCase {

    private static let startDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// Morceau à 172 BPM : ratio 1.0 pour une cadence cible de 172 SPM.
    private func track172BPM() -> TrackDescriptor {
        TrackDescriptor(
            id: DemoLibrary.slowTrackID,
            title: "Test 172 BPM",
            nominalBPM: 172,
            bpmProvenance: .manual,
            bpmConfidence: 1.0,
            providerID: ProviderCatalog.localImportedFiles.id,
            canAlterTempo: true,
            isFileAvailable: true,
            isAdaptationRightsAttested: true
        )
    }

    private func assessment(_ stepsPerMinute: Double, at seconds: Double) -> CadenceAssessment {
        var filter = CadenceFilter()
        return filter.ingest(
            CadenceSample(
                timestamp: Self.startDate.addingTimeInterval(seconds),
                stepsPerMinute: stepsPerMinute,
                quality: .good,
                sourceIdentifier: "test"
            )
        )
    }

    // MARK: - Scénario E

    func test_scenarioE_paceFiveMinutesPerKilometerWithTarget172AndObserved160() {
        let track = track172BPM()
        var controller = PaceController(
            policy: .standard,
            configuration: PaceControllerConfiguration(
                targetCadenceSPM: 172,
                targetPaceSecondsPerKilometer: 300
            )
        )
        controller.start(at: Self.startDate)

        var last: PaceDecision?
        for second in 1...10 {
            let now = Self.startDate.addingTimeInterval(Double(second))
            last = controller.update(
                observedCadence: assessment(160, at: Double(second)),
                pace: PaceSample(
                    timestamp: now,
                    secondsPerKilometer: 315,
                    distanceMeters: Double(second) * 5.3,
                    quality: .good
                ),
                track: track,
                candidates: [track],
                now: now
            )
        }

        // La cible musicale reste la cadence cible déclarée, pas la cadence observée.
        XCTAssertEqual(last?.tempo.targetTrackBPM ?? 0, 172, accuracy: 1e-12)
        XCTAssertEqual(last?.tempo.reason, .paceTargetMaintained)
        XCTAssertNotEqual(last?.tempo.reason, .followingCadence)
        XCTAssertEqual(last?.tempo.appliedRate ?? 0, 1.0, accuracy: 1e-12)
        // L'écart réel est affiché séparément : 160 observé vs 172 cible.
        XCTAssertEqual(last?.cadenceDeltaSPM ?? 0, -12, accuracy: 1e-12)
        XCTAssertEqual(last?.paceDeltaSecondsPerKilometer ?? 0, 15, accuracy: 1e-12)
        XCTAssertEqual(last?.audibleGuidanceEnabled, false, "Signaux sonores désactivés par défaut")
    }

    // MARK: - T008

    func test_T008_observedCadenceVariationsNeverMoveThePaceTarget() {
        let track = track172BPM()
        var controller = PaceController(
            policy: .standard,
            configuration: PaceControllerConfiguration(targetCadenceSPM: 172)
        )
        controller.start(at: Self.startDate)

        var targetBPMs: [Double] = []
        var appliedRates: [Double] = []
        var deltas: [Double] = []
        for (index, observed) in [140.0, 150.0, 160.0, 170.0, 180.0, 145.0, 172.0, 200.0].enumerated() {
            let now = Self.startDate.addingTimeInterval(Double(index + 1))
            let decision = controller.update(
                observedCadence: assessment(observed, at: Double(index + 1)),
                track: track,
                candidates: [track],
                now: now
            )
            targetBPMs.append(decision.tempo.targetTrackBPM ?? .nan)
            appliedRates.append(decision.tempo.appliedRate)
            deltas.append(decision.cadenceDeltaSPM ?? .nan)
        }

        XCTAssertTrue(targetBPMs.allSatisfy { $0 == 172 }, "La cible ne dépend jamais de la cadence observée")
        XCTAssertEqual(Set(appliedRates).count, 1, "Aucune accélération automatique quand l'utilisateur ralentit")
        XCTAssertEqual(deltas.first ?? 0, -32, accuracy: 1e-12)
        XCTAssertEqual(deltas.last ?? 0, 28, accuracy: 1e-12)
    }

    // MARK: - Garde-fous

    func test_anImplausibleTargetCadenceIsNotUsedToGuideTheTempo() {
        var controller = PaceController(
            policy: .standard,
            configuration: PaceControllerConfiguration(targetCadenceSPM: 20)
        )
        controller.start(at: Self.startDate)
        let now = Self.startDate.addingTimeInterval(1)
        let decision = controller.update(
            observedCadence: assessment(170, at: 1),
            track: track172BPM(),
            candidates: [],
            now: now
        )
        XCTAssertEqual(controller.configuration.hasUsableTargetCadence, false)
        XCTAssertEqual(decision.tempo.reason, .cadenceUnavailableHolding)
        XCTAssertEqual(decision.tempo.quality, .unavailable)
        XCTAssertEqual(decision.tempo.appliedRate, 1.0, accuracy: 1e-12)
    }

    func test_aTrackWithoutBPMDoesNotStopTheGuidanceAndSuggestsAnotherTrack() {
        var controller = PaceController(
            policy: .standard,
            configuration: PaceControllerConfiguration(targetCadenceSPM: 172)
        )
        controller.start(at: Self.startDate)
        let now = Self.startDate.addingTimeInterval(1)
        let decision = controller.update(
            observedCadence: assessment(160, at: 1),
            track: DemoLibrary.bpmUnknownTrack,
            candidates: [DemoLibrary.bpmUnknownTrack, track172BPM()],
            now: now
        )
        XCTAssertEqual(decision.tempo.reason, .bpmUnknown)
        XCTAssertNil(decision.tempo.requiredRate)
        XCTAssertEqual(decision.recommendedTrackID, DemoLibrary.slowTrackID)
        XCTAssertEqual(decision.cadenceDeltaSPM ?? 0, -12, accuracy: 1e-12)
    }

    func test_anUnavailableObservedCadenceIsReportedAsUnknownAndNotAsZero() {
        var controller = PaceController(
            policy: .standard,
            configuration: PaceControllerConfiguration(targetCadenceSPM: 172)
        )
        controller.start(at: Self.startDate)
        var filter = CadenceFilter()
        let now = Self.startDate.addingTimeInterval(1)
        let unavailable = filter.ingest(.sensorUnavailable(timestamp: now, sourceIdentifier: "test"))
        let decision = controller.update(
            observedCadence: unavailable,
            track: track172BPM(),
            candidates: [track172BPM()],
            now: now
        )
        XCTAssertNil(decision.observedCadenceSPM)
        XCTAssertNil(decision.cadenceDeltaSPM)
        XCTAssertEqual(decision.tempo.appliedRate, 1.0, accuracy: 1e-12)
    }
}
