import XCTest
import RunSyncDomain
import RunSyncSimulation

/// Oracles numériques du cahier des charges §05 (scénarios A, B, C) et cas
/// T004-T006, T011 de la stratégie de tests §11.
final class TempoMatchingOracleTests: XCTestCase {

    /// Morceau de 85 BPM utilisé pour le scénario B (ratio 2:1).
    private func track85BPM() -> TrackDescriptor {
        TrackDescriptor(
            id: DemoLibrary.bpmUnknownTrackID,
            title: "Test 85 BPM",
            nominalBPM: 85,
            bpmProvenance: .manual,
            bpmConfidence: 1.0,
            providerID: ProviderCatalog.localImportedFiles.id,
            canAlterTempo: true,
            isFileAvailable: true,
            isAdaptationRightsAttested: true
        )
    }

    // MARK: - Scénario A / T004

    func test_scenarioA_168BPM_with170SPM_requiresOnePointZeroOneOneNine() {
        let matcher = TempoMatcher()
        let evaluation = matcher.evaluate(
            track: DemoLibrary.testTrack,
            targetCadenceSPM: 170
        )
        XCTAssertEqual(evaluation.stepsPerBeat, 1)
        XCTAssertEqual(evaluation.requiredRateRaw ?? 0, 170.0 / 168.0, accuracy: 1e-12)
        XCTAssertEqual(evaluation.requiredRateRaw ?? 0, 1.0119047619047619, accuracy: 1e-12)
        XCTAssertTrue(evaluation.isAdmissible)
        XCTAssertEqual(evaluation.requiredRateLimited ?? 0, 170.0 / 168.0, accuracy: 1e-12)
        XCTAssertNil(evaluation.rejection)
    }

    // MARK: - Scénario B / T005

    func test_scenarioB_85BPM_with170SPM_atRatioTwo_isExactlyOne() {
        let matcher = TempoMatcher()
        let evaluation = matcher.evaluate(track: track85BPM(), targetCadenceSPM: 170)
        XCTAssertEqual(evaluation.stepsPerBeat, 2)
        XCTAssertEqual(evaluation.requiredRateRaw ?? 0, 1.0, accuracy: 1e-12)
        XCTAssertEqual(evaluation.targetTrackBPM ?? 0, 85, accuracy: 1e-12)
        XCTAssertTrue(evaluation.isAdmissible)
    }

    // MARK: - Scénario C / T006

    func test_scenarioC_168BPM_with150SPM_isClampedToPointNineFive() {
        let matcher = TempoMatcher()
        let evaluation = matcher.evaluate(track: DemoLibrary.testTrack, targetCadenceSPM: 150)
        XCTAssertEqual(evaluation.requiredRateRaw ?? 0, 150.0 / 168.0, accuracy: 1e-12)
        XCTAssertEqual(evaluation.requiredRateRaw ?? 0, 0.8928571428571428, accuracy: 1e-12)
        XCTAssertFalse(evaluation.isAdmissible)
        XCTAssertEqual(evaluation.requiredRateLimited ?? 0, 0.95, accuracy: 1e-12)
    }

    func test_scenarioC_anAdmissibleAlternativeIsAvailableForTheSameCadence() {
        // Le morceau à 150 BPM est admissible pour 150 SPM : c'est la suggestion
        // de changement de morceau attendue par le scénario C.
        let matcher = TempoMatcher()
        let best = matcher.bestMatch(tracks: DemoLibrary.tracks, targetCadenceSPM: 150)
        XCTAssertEqual(best?.trackID, DemoLibrary.slowTrackID)
        XCTAssertEqual(best?.requiredRateRaw ?? 0, 1.0, accuracy: 1e-12)
    }

    // MARK: - T011 : valeurs BPM invalides

    func test_T011_invalidBPMNeverProducesADivisionByZeroOrASilentMatch() {
        let matcher = TempoMatcher()
        let policy = TempoMatchingPolicy.standard

        let missing = matcher.evaluate(track: DemoLibrary.bpmUnknownTrack, targetCadenceSPM: 170)
        XCTAssertEqual(missing.rejection, .bpmUnknown)
        XCTAssertNil(missing.requiredRateRaw)
        XCTAssertFalse(missing.isAdmissible)

        for invalidValue in [0.0, -120.0, Double.nan, Double.infinity] {
            let track = TrackDescriptor(
                title: "BPM invalide",
                nominalBPM: invalidValue,
                bpmProvenance: .provided,
                providerID: ProviderCatalog.localImportedFiles.id,
                canAlterTempo: true,
                isAdaptationRightsAttested: true
            )
            let evaluation = matcher.evaluate(track: track, targetCadenceSPM: 170)
            XCTAssertNil(evaluation.requiredRateRaw, "Aucun ratio ne doit être calculé")
            XCTAssertNil(evaluation.requiredRateLimited, "Aucun ratio borné n'est inventé pour un morceau rejeté")
            XCTAssertFalse(evaluation.isAdmissible)
            // Le repli sur le tempo original est appliqué par la politique, pas par
            // l'évaluation : aucune valeur de ratio n'est fabriquée pour un rejet.
            XCTAssertEqual(policy.limitedRate(evaluation.requiredRateRaw), 1.0, accuracy: 1e-12)
            guard case .bpmInvalid? = evaluation.rejection else {
                return XCTFail("Attendu .bpmInvalid, obtenu \(String(describing: evaluation.rejection))")
            }
        }
    }

    func test_missingTargetCadenceProducesAnExplicitRejection() {
        let matcher = TempoMatcher()
        let evaluation = matcher.evaluate(track: DemoLibrary.testTrack, targetCadenceSPM: nil)
        XCTAssertEqual(evaluation.rejection, .targetCadenceUnavailable)
        XCTAssertNil(evaluation.requiredRateRaw)
    }

    // MARK: - Rejets de conformité (RS-040, §02)

    func test_tracksThatCannotBeAlteredAreRejectedWithAnExplicitReason() {
        let matcher = TempoMatcher()
        let provider = ProviderCatalog.spotify
        let spotifyLikeTrack = TrackDescriptor(
            title: "Flux fournisseur",
            nominalBPM: 120,
            bpmProvenance: .provided,
            providerID: provider.id,
            canAlterTempo: false,
            isFileAvailable: true,
            isAdaptationRightsAttested: false
        )
        let evaluation = matcher.evaluate(track: spotifyLikeTrack, targetCadenceSPM: 170)
        XCTAssertEqual(evaluation.rejection, .tempoAdjustmentNotPermitted(providerID: "spotify"))
        XCTAssertNil(evaluation.requiredRateRaw)
        XCTAssertEqual(evaluation.rejection?.decisionReason, .tempoAdjustmentNotPermitted)
    }

    func test_missingFileAndMissingAttestationAreRejected() {
        let matcher = TempoMatcher()
        let deletedFile = TrackDescriptor(
            title: "Fichier supprimé",
            nominalBPM: 168,
            bpmProvenance: .manual,
            providerID: ProviderCatalog.localImportedFiles.id,
            canAlterTempo: true,
            isFileAvailable: false,
            isAdaptationRightsAttested: true
        )
        XCTAssertEqual(
            matcher.evaluate(track: deletedFile, targetCadenceSPM: 170).rejection,
            .fileUnavailable
        )

        let unattested = TrackDescriptor(
            title: "Sans attestation de droits",
            nominalBPM: 168,
            bpmProvenance: .provided,
            providerID: ProviderCatalog.localImportedFiles.id,
            canAlterTempo: true,
            isFileAvailable: true,
            isAdaptationRightsAttested: false
        )
        XCTAssertEqual(
            matcher.evaluate(track: unattested, targetCadenceSPM: 170).rejection,
            .adaptationRightsNotAttested
        )
    }

    // MARK: - Classement et coût de sélection

    func test_rankingPrefersTheTrackWithTheSmallestRequiredAdjustment() {
        let matcher = TempoMatcher()
        let ranked = matcher.ranked(tracks: DemoLibrary.tracks, targetCadenceSPM: 170)
        XCTAssertEqual(ranked.first?.trackID, DemoLibrary.testTrackID, "168 BPM est le plus proche de 170 SPM")
        XCTAssertTrue(ranked.first?.isAdmissible == true)
        XCTAssertFalse(ranked.last?.isAdmissible == true, "Le morceau sans BPM termine en dernier")
    }

    func test_ratioTwoIsPreferredWhenItIsCloserToOne() {
        let matcher = TempoMatcher()
        let ranked = matcher.ranked(tracks: [track85BPM()], targetCadenceSPM: 170)
        XCTAssertEqual(ranked.first?.stepsPerBeat, 2)
        XCTAssertEqual(ranked.first?.requiredRateRaw ?? 0, 1.0, accuracy: 1e-12)
    }

    func test_selectionCostMatchesTheSpecifiedWeighting() {
        let matcher = TempoMatcher()
        let track = DemoLibrary.testTrack
        let rate = 170.0 / 168.0
        let withoutPenalty = matcher.selectionCost(
            requiredRate: rate,
            trackID: track.id,
            recentlyPlayedTrackIDs: []
        )
        let withPenalty = matcher.selectionCost(
            requiredRate: rate,
            trackID: track.id,
            recentlyPlayedTrackIDs: [track.id]
        )
        XCTAssertEqual(
            withoutPenalty,
            TempoMatcher.Weights.requiredRateDeviation * (abs(log(rate)) / log(1.05)),
            accuracy: 1e-12
        )
        XCTAssertEqual(
            withPenalty - withoutPenalty,
            TempoMatcher.Weights.frequentTrackChange,
            accuracy: 1e-12
        )
    }

    func test_theUserPreferenceTermIsZeroBecauseNoLicitePreferenceExistsYet() {
        // Aucune caractéristique musicale n'est inventée : le terme de préférence
        // reste neutre tant qu'aucune donnée licite n'est disponible (§05).
        XCTAssertEqual(TempoMatcher.Weights.userPreferenceUnavailable, 0.0)
    }

    // MARK: - Politique

    func test_defaultPolicyIsFivePercentAndSupportsBothRatios() {
        XCTAssertEqual(TempoMatchingPolicy.standard.maxAdjustment, 0.05, accuracy: 1e-12)
        XCTAssertEqual(TempoMatchingPolicy.standard.stepsPerBeatCandidates, [1, 2])
        XCTAssertEqual(TempoMatchingPolicy.conservative.maxAdjustment, 0.03, accuracy: 1e-12)
        XCTAssertEqual(TempoMatchingPolicy.standard.lowerBoundRate, 0.95, accuracy: 1e-12)
        XCTAssertEqual(TempoMatchingPolicy.standard.upperBoundRate, 1.05, accuracy: 1e-12)
    }

    func test_invalidPolicyConfigurationsAreRejectedAtConstruction() {
        XCTAssertThrowsError(try TempoMatchingPolicy(maxAdjustment: 0.5)) { error in
            XCTAssertEqual(error as? TempoPolicyError, .maxAdjustmentOutOfRange(0.5))
        }
        XCTAssertThrowsError(try TempoMatchingPolicy(maxAdjustment: 0)) { error in
            XCTAssertEqual(error as? TempoPolicyError, .maxAdjustmentOutOfRange(0))
        }
        XCTAssertThrowsError(try TempoMatchingPolicy(stepsPerBeatCandidates: [1, 3])) { error in
            XCTAssertEqual(error as? TempoPolicyError, .unsupportedStepsPerBeat([1, 3]))
        }
        XCTAssertNoThrow(try TempoMatchingPolicy(maxAdjustment: 0.05, stepsPerBeatCandidates: [1, 2]))
    }

    func test_limitedRateNeverReturnsAnInventedValue() {
        let policy = TempoMatchingPolicy.standard
        XCTAssertEqual(policy.limitedRate(nil), 1.0)
        XCTAssertEqual(policy.limitedRate(.nan), 1.0)
        XCTAssertEqual(policy.limitedRate(Double.infinity), 1.0)
        XCTAssertEqual(policy.limitedRate(-2), 1.0)
        XCTAssertEqual(policy.limitedRate(0.5), 0.95, accuracy: 1e-12)
        XCTAssertEqual(policy.limitedRate(2.0), 1.05, accuracy: 1e-12)
        XCTAssertEqual(policy.limitedRate(1.01), 1.01, accuracy: 1e-12)
    }
}
