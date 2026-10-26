import XCTest
import RunSyncDomain
import RunSyncSimulation

/// Filtrage de cadence : T001 (conversion CoreMotion), T002 (rejets invalides),
/// T003 (outlier isolé) et §05 exemple F (pas de pompage).
final class CadenceFilterTests: XCTestCase {

    private static let startDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(_ stepsPerMinute: Double?, at seconds: Double) -> CadenceSample {
        CadenceSample(
            timestamp: Self.startDate.addingTimeInterval(seconds),
            stepsPerMinute: stepsPerMinute,
            quality: stepsPerMinute == nil ? .unavailable : .good,
            sourceIdentifier: "test"
        )
    }

    // MARK: - T001

    func test_T001_coreMotionStepsPerSecondIsConvertedToSPM() {
        XCTAssertEqual(CadenceUnits.stepsPerSecondToSPM(2.833333) ?? 0, 170, accuracy: 0.001)
        XCTAssertEqual(CadenceSample.fromStepsPerSecond(
            2.833333,
            timestamp: Self.startDate,
            sourceIdentifier: "coreMotion"
        ).stepsPerMinute ?? 0, 170, accuracy: 0.001)
    }

    func test_T001_invalidSensorValuesProduceUnavailableSamplesNotZero() {
        for invalidValue in [nil, 0.0, -3.0, Double.nan, Double.infinity] as [Double?] {
            let sample = CadenceSample.fromStepsPerSecond(
                invalidValue,
                timestamp: Self.startDate,
                sourceIdentifier: "coreMotion"
            )
            XCTAssertNil(sample.stepsPerMinute)
            XCTAssertEqual(sample.quality, .unavailable)
        }
    }

    // MARK: - T002

    func test_T002_invalidMeasurementsAreRejectedAndNeverBecomeACadence() {
        var filter = CadenceFilter()
        let invalidValues: [Double?] = [nil, .nan, .infinity, -12, 0, 45, 320]

        for (index, value) in invalidValues.enumerated() {
            let assessment = filter.ingest(sample(value, at: Double(index)))
            XCTAssertNil(assessment.setpointSPM, "Aucune cadence ne doit être inventée")
            XCTAssertNil(assessment.rawSPM)
            XCTAssertEqual(assessment.quality, .unavailable)
            XCTAssertNotNil(assessment.lastRejection)
        }
        XCTAssertEqual(filter.rejectionCount, invalidValues.count)
    }

    func test_T002_rejectionReasonsAreDistinguishedForDiagnostics() {
        var filter = CadenceFilter()
        XCTAssertEqual(filter.ingest(sample(nil, at: 0)).lastRejection, .sensorReportedNoValue)
        XCTAssertEqual(filter.ingest(sample(.nan, at: 1)).lastRejection, .notANumber)
        XCTAssertEqual(filter.ingest(sample(.infinity, at: 2)).lastRejection, .notFinite)
        XCTAssertEqual(filter.ingest(sample(0, at: 3)).lastRejection, .nonPositive(0))
        XCTAssertEqual(filter.ingest(sample(-5, at: 4)).lastRejection, .nonPositive(-5))
        XCTAssertEqual(filter.ingest(sample(45, at: 5)).lastRejection, .implausibleRange(45))
        XCTAssertEqual(filter.ingest(sample(320, at: 6)).lastRejection, .implausibleRange(320))
    }

    func test_aValidIntervalAfterRejectionsLowersTheQualityExplicitly() {
        var filter = CadenceFilter()
        XCTAssertEqual(filter.ingest(sample(170, at: 0)).quality, .good)
        // 2 s sans mesure : état dégradé, mais la dernière consigne connue est conservée.
        let degraded = filter.ingest(sample(nil, at: 2))
        XCTAssertEqual(degraded.quality, .degraded)
        XCTAssertEqual(degraded.setpointSPM, 170)
        // Au-delà du délai de péremption : indisponible.
        XCTAssertEqual(filter.ingest(sample(nil, at: 20)).quality, .unavailable)
        // Une mesure valide restaure un état exploitable.
        XCTAssertEqual(filter.ingest(sample(172, at: 21)).quality, .good)
    }

    // MARK: - T003

    func test_T003_anIsolatedOutlierDoesNotCauseABrutalJump() {
        var filter = CadenceFilter()
        var setpoints: [Double] = []
        for index in 0..<5 {
            setpoints.append(filter.ingest(sample(170, at: Double(index))).setpointSPM ?? .nan)
        }
        XCTAssertTrue(setpoints.allSatisfy { $0 == 170 })
        XCTAssertEqual(filter.ingest(sample(200, at: 5)).setpointSPM, 170)
        XCTAssertEqual(filter.ingest(sample(170, at: 6)).setpointSPM, 170)
        XCTAssertEqual(filter.ingest(sample(170, at: 7)).setpointSPM, 170)
    }

    func test_sustainedDeviationMovesTheSetpointOnlyAfterConfirmation() {
        var filter = CadenceFilter()
        let values = Array(repeating: 170.0, count: 5) + Array(repeating: 176.0, count: 10)
        var setpoints: [Double] = []
        for (index, value) in values.enumerated() {
            setpoints.append(filter.ingest(sample(value, at: Double(index))).setpointSPM ?? .nan)
        }
        // Les 8 premières mesures ne bougent pas : l'écart n'est pas encore confirmé.
        XCTAssertTrue(setpoints.prefix(8).allSatisfy { $0 == 170 })
        // Après confirmation (écart > 1.5 SPM maintenu 2 s), la consigne suit.
        XCTAssertGreaterThan(setpoints[10], 170)
        XCTAssertLessThan(setpoints[10], 176, "La consigne rejoint la cadence progressivement")
    }

    /// §05 exemple F : 169, 170, 169, 171 => aucune pompe audible.
    func test_scenarioF_oneSPMJitterNeverMovesTheSetpoint() {
        var filter = CadenceFilter()
        var setpoints: [Double?] = []
        for (index, value) in [169.0, 170.0, 169.0, 171.0].enumerated() {
            setpoints.append(filter.ingest(sample(value, at: Double(index))).setpointSPM)
        }
        XCTAssertEqual(setpoints, [169, 169, 169, 169])
    }

    func test_configurationIsNormalizedSoInjectedValuesCannotBreakTheFilter() {
        let broken = CadenceFilterConfiguration(
            plausibleRangeSPM: 80...80,
            medianWindowSize: 0,
            exponentialSmoothingAlpha: Double.nan,
            hysteresisSPM: -1,
            hysteresisConfirmationSeconds: -2,
            staleSampleTimeoutSeconds: Double.infinity
        ).normalized

        XCTAssertEqual(broken.plausibleRangeSPM, CadenceUnits.plausibleRangeSPM)
        XCTAssertEqual(broken.medianWindowSize, 1)
        XCTAssertEqual(broken.exponentialSmoothingAlpha, 0.25, accuracy: 1e-12)
        XCTAssertEqual(broken.hysteresisSPM, 0, accuracy: 1e-12, "Une hystérésis négative est neutralisée")
        XCTAssertEqual(broken.hysteresisConfirmationSeconds, 0, accuracy: 1e-12)
        XCTAssertEqual(broken.staleSampleTimeoutSeconds, 5.0, accuracy: 1e-12)
    }

    func test_resetClearsEveryDiagnosticAndConsigneState() {
        var filter = CadenceFilter()
        _ = filter.ingest(sample(170, at: 0))
        _ = filter.ingest(sample(nil, at: 1))
        XCTAssertGreaterThan(filter.rejectionCount, 0)
        filter.reset()
        XCTAssertEqual(filter.currentAssessment, .initial)
        XCTAssertEqual(filter.rejectionCount, 0)
    }

    func test_plausibleRangeIsConfigurable() {
        var filter = CadenceFilter(
            configuration: CadenceFilterConfiguration(plausibleRangeSPM: 100...200)
        )
        XCTAssertEqual(filter.ingest(sample(95, at: 0)).lastRejection, .implausibleRange(95))
        XCTAssertEqual(filter.ingest(sample(150, at: 1)).quality, .good)
    }
}
