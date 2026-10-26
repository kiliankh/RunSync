import XCTest
import RunSyncDomain
import RunSyncSimulation

/// Garde de conformité (RS-040, §02) : T013 « provider sans canTempo => setRate
/// impossible / explicite ».
final class TempoAdjustmentGateTests: XCTestCase {

    private let gate = TempoAdjustmentGate()

    private func provider(
        id: String = "vendor.unverified",
        canAdjustTempo: Bool,
        status: ComplianceStatus
    ) -> MusicProviderCapabilities {
        MusicProviderCapabilities(
            id: id,
            displayName: "Fournisseur de test",
            canBrowseCatalog: true,
            canControlPlayback: true,
            canAdjustTempo: canAdjustTempo,
            canAccessPCM: canAdjustTempo,
            requiresNetwork: true,
            compliance: ProviderComplianceRecord(status: status, notes: "test")
        )
    }

    // MARK: - T013

    func test_T013_aProviderWithoutTempoCapabilityIsRefusedExplicitly() {
        XCTAssertThrowsError(
            try gate.validatedRate(
                requestedRate: 1.02,
                track: DemoLibrary.testTrack,
                provider: ProviderCatalog.spotify
            )
        ) { error in
            XCTAssertEqual(error as? TempoAdjustmentError, .providerNotPermitted(providerID: "spotify"))
        }
        XCTAssertFalse(ProviderCatalog.spotify.isTempoAdjustmentPermitted)
    }

    func test_T013_aTechnicalCapabilityWithoutAConfirmedComplianceReviewIsNotEnough() {
        let unverified = provider(canAdjustTempo: true, status: .underReview)
        XCTAssertFalse(unverified.isTempoAdjustmentPermitted)
        XCTAssertThrowsError(
            try gate.validatedRate(
                requestedRate: 1.0,
                track: DemoLibrary.testTrack,
                provider: unverified
            )
        )
        XCTAssertFalse(
            gate.isPermitted(track: DemoLibrary.testTrack, provider: unverified),
            "La capacité technique seule n'autorise jamais l'altération d'un flux"
        )
    }

    func test_T013_aProhibitedProviderIsRefused() {
        XCTAssertFalse(ProviderCatalog.youTube.isTempoAdjustmentPermitted)
        XCTAssertEqual(ProviderCatalog.youTube.compliance.status, .prohibited)
        XCTAssertThrowsError(
            try gate.validatedRate(
                requestedRate: 1.0,
                track: DemoLibrary.testTrack,
                provider: ProviderCatalog.youTube
            )
        )
    }

    func test_theLocalImportedFilesPathIsPermittedAndClamped() {
        let local = ProviderCatalog.localImportedFiles
        XCTAssertTrue(local.isTempoAdjustmentPermitted)
        XCTAssertTrue(gate.isPermitted(track: DemoLibrary.testTrack, provider: local))
        XCTAssertEqual(
            try gate.validatedRate(
                requestedRate: 1.09,
                track: DemoLibrary.testTrack,
                provider: local
            ),
            1.05,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            try gate.validatedRate(
                requestedRate: 0.80,
                track: DemoLibrary.testTrack,
                provider: local
            ),
            0.95,
            accuracy: 1e-12
        )
    }

    func test_invalidRequestsAreRefusedWithTypedErrors() {
        let local = ProviderCatalog.localImportedFiles

        let deleted = TrackDescriptor(
            title: "Fichier supprimé",
            nominalBPM: 168,
            bpmProvenance: .manual,
            providerID: local.id,
            canAlterTempo: true,
            isFileAvailable: false,
            isAdaptationRightsAttested: true
        )
        XCTAssertThrowsError(
            try gate.validatedRate(requestedRate: 1.0, track: deleted, provider: local)
        ) { error in
            XCTAssertEqual(error as? TempoAdjustmentError, .trackFileUnavailable(trackID: deleted.id))
        }

        let unattested = TrackDescriptor(
            title: "Sans attestation",
            nominalBPM: 168,
            bpmProvenance: .provided,
            providerID: local.id,
            canAlterTempo: true,
            isFileAvailable: true,
            isAdaptationRightsAttested: false
        )
        XCTAssertThrowsError(
            try gate.validatedRate(requestedRate: 1.0, track: unattested, provider: local)
        ) { error in
            XCTAssertEqual(
                error as? TempoAdjustmentError,
                .adaptationRightsNotAttested(trackID: unattested.id)
            )
        }

        XCTAssertThrowsError(
            try gate.validatedRate(
                requestedRate: 1.0,
                track: DemoLibrary.bpmUnknownTrack,
                provider: local
            )
        ) { error in
            XCTAssertEqual(
                error as? TempoAdjustmentError,
                .nominalBPMUnavailable(trackID: DemoLibrary.bpmUnknownTrackID)
            )
        }

        for invalidRate in [0.0, -1.0] {
            XCTAssertThrowsError(
                try gate.validatedRate(
                    requestedRate: invalidRate,
                    track: DemoLibrary.testTrack,
                    provider: local
                )
            ) { error in
                XCTAssertEqual(error as? TempoAdjustmentError, .invalidRequestedRate(invalidRate))
            }
        }

        // NaN et l'infini ne se comparent pas par égalité : on vérifie la forme de l'erreur.
        for nonFiniteRate in [Double.nan, Double.infinity] {
            XCTAssertThrowsError(
                try gate.validatedRate(
                    requestedRate: nonFiniteRate,
                    track: DemoLibrary.testTrack,
                    provider: local
                )
            ) { error in
                guard case .invalidRequestedRate(let value)? = error as? TempoAdjustmentError else {
                    return XCTFail("Attendu .invalidRequestedRate pour \(nonFiniteRate)")
                }
                XCTAssertEqual(value.isNaN, nonFiniteRate.isNaN)
                XCTAssertEqual(value.isFinite, nonFiniteRate.isFinite)
            }
        }
    }

    func test_providerCatalogKeepsThirdPartySourcesOutOfTheMvp() {
        XCTAssertEqual(ProviderCatalog.all.first?.id, ProviderCatalog.localImportedFiles.id)
        // Aucun fournisseur tiers n'est confirmé : le mode local est le seul chemin MVP.
        let confirmed = ProviderCatalog.all.filter { $0.compliance.status == .confirmed }
        XCTAssertEqual(confirmed.map(\.id), [ProviderCatalog.localImportedFiles.id])
        // Aucun fournisseur tiers ne prétend pouvoir ajuster le tempo.
        for provider in ProviderCatalog.all where provider.id != ProviderCatalog.localImportedFiles.id {
            XCTAssertFalse(provider.isTempoAdjustmentPermitted, "\(provider.id) ne doit rien promettre")
        }
    }
}
