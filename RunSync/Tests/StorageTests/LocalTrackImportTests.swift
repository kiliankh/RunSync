import XCTest
import RunSyncDomain
import RunSyncPersistence
import RunSyncSimulation

/// Import local (RS-020, FR-006, T014) : validation avant copie, erreurs typées,
/// règle de conformité sur l'attestation de droits, BPM manuel.
final class LocalTrackImportTests: XCTestCase {

    private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeImporter(
        storage: RecordingTrackFileStorage,
        policy: LocalImportPolicy = .standard
    ) -> LocalTrackImporter {
        LocalTrackImporter(storage: storage, policy: policy, now: { Self.fixedDate })
    }

    private func request(
        fileName: String = "morceau.wav",
        attested: Bool = true,
        identifier: UUID = UUID()
    ) -> LocalImportRequest {
        LocalImportRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/source/\(fileName)"),
            userAttestsAdaptationRights: attested,
            identifier: identifier
        )
    }

    // MARK: - Import nominal

    func test_aValidImportProducesAnAttestedTrackWithoutInventingABPM() throws {
        let storage = RecordingTrackFileStorage()
        let sourceURL = URL(fileURLWithPath: "/tmp/source/morceau.wav")
        storage.registerSource(sourceURL, sizeBytes: 2048)
        let identifier = UUID()

        let track = try makeImporter(storage: storage).importTrack(
            LocalImportRequest(sourceURL: sourceURL, userAttestsAdaptationRights: true, identifier: identifier)
        )

        XCTAssertEqual(track.id, identifier)
        XCTAssertEqual(track.title, "morceau")
        XCTAssertEqual(track.providerID, ProviderCatalog.localImportedFiles.id)
        // Le BPM n'est jamais deviné à l'import (FR-007).
        XCTAssertNil(track.nominalBPM)
        XCTAssertEqual(track.bpmProvenance, .unknown)
        XCTAssertFalse(track.hasUsableNominalBPM)
        // Droits attestés => adaptation autorisée ; fichier présent.
        XCTAssertTrue(track.canAlterTempo)
        XCTAssertTrue(track.isAdaptationRightsAttested)
        XCTAssertTrue(track.isFileAvailable)
        XCTAssertEqual(track.fileSizeBytes, 2048)
        XCTAssertEqual(track.importedAt, Self.fixedDate)
        XCTAssertEqual(track.relativePath, "\(identifier.uuidString).wav")
        XCTAssertEqual(storage.storeCopyCallCount, 1)
    }

    func test_anImportWithoutAttestationIsStoredButNeverPresentedAsAdjustable() throws {
        let storage = RecordingTrackFileStorage()
        let sourceURL = URL(fileURLWithPath: "/tmp/source/morceau.mp3")
        storage.registerSource(sourceURL, sizeBytes: 4096)

        let track = try makeImporter(storage: storage).importTrack(
            LocalImportRequest(sourceURL: sourceURL, userAttestsAdaptationRights: false)
        )

        XCTAssertFalse(track.canAlterTempo)
        XCTAssertFalse(track.isAdaptationRightsAttested)
        XCTAssertFalse(track.isTempoAdjustable)

        // Le matcher refuse explicitement ce morceau, même après saisie d'un BPM.
        let withBPM = try track.settingManualBPM(168)
        let evaluation = TempoMatcher().evaluate(track: withBPM, targetCadenceSPM: 170)
        XCTAssertEqual(evaluation.rejection, .adaptationRightsNotAttested)
        XCTAssertNil(evaluation.requiredRateRaw)
    }

    func test_theStoredPathIsRelativeAndNeverLeaksAnAbsoluteLocation() throws {
        let storage = RecordingTrackFileStorage()
        let sourceURL = URL(fileURLWithPath: "/tmp/source/morceau.wav")
        storage.registerSource(sourceURL, sizeBytes: 1024)

        let track = try makeImporter(storage: storage).importTrack(
            LocalImportRequest(sourceURL: sourceURL, userAttestsAdaptationRights: true)
        )

        let path = try XCTUnwrap(track.relativePath)
        XCTAssertFalse(path.contains("/"), "Aucun chemin absolu ni sous-dossier")
        XCTAssertFalse(path.contains("\\"))
        XCTAssertFalse(path.contains(":"))
        XCTAssertNotEqual(path, sourceURL.path)
    }

    // MARK: - Refus avant toute copie

    func test_anUnsupportedFormatIsRefusedBeforeAnyCopy() {
        let storage = RecordingTrackFileStorage()
        let sourceURL = URL(fileURLWithPath: "/tmp/source/morceau.ogg")
        storage.registerSource(sourceURL, sizeBytes: 1024)

        XCTAssertThrowsError(
            try makeImporter(storage: storage).importTrack(
                LocalImportRequest(sourceURL: sourceURL, userAttestsAdaptationRights: true)
            )
        ) { error in
            XCTAssertEqual(error as? TrackImportError, .unsupportedFormat("ogg"))
        }
        XCTAssertEqual(storage.storeCopyCallCount, 0, "Aucune écriture pour un format refusé")
    }

    func test_aFileWithoutExtensionIsRefused() {
        let storage = RecordingTrackFileStorage()
        let sourceURL = URL(fileURLWithPath: "/tmp/source/sans_extension")
        storage.registerSource(sourceURL, sizeBytes: 1024)

        XCTAssertThrowsError(
            try makeImporter(storage: storage).importTrack(
                LocalImportRequest(sourceURL: sourceURL, userAttestsAdaptationRights: true)
            )
        ) { error in
            XCTAssertEqual(error as? TrackImportError, .unsupportedFormat("sans extension"))
        }
        XCTAssertEqual(storage.storeCopyCallCount, 0)
    }

    func test_aMissingOrUnreadableSourceFileIsRefused() {
        let storage = RecordingTrackFileStorage() // aucune source enregistrée : fichier absent

        XCTAssertThrowsError(
            try makeImporter(storage: storage).importTrack(
                LocalImportRequest(
                    sourceURL: URL(fileURLWithPath: "/tmp/source/absent.wav"),
                    userAttestsAdaptationRights: true
                )
            )
        ) { error in
            XCTAssertEqual(error as? TrackImportError, .sourceFileUnreadable)
        }
        XCTAssertEqual(storage.storeCopyCallCount, 0)
    }

    func test_anOversizedFileIsRefused() {
        let storage = RecordingTrackFileStorage()
        let sourceURL = URL(fileURLWithPath: "/tmp/source/gros.wav")
        storage.registerSource(sourceURL, sizeBytes: 2_000)
        let policy = LocalImportPolicy(maximumFileSizeBytes: 1_000, freeSpaceMarginBytes: 0)

        XCTAssertThrowsError(
            try makeImporter(storage: storage, policy: policy).importTrack(
                LocalImportRequest(sourceURL: sourceURL, userAttestsAdaptationRights: true)
            )
        ) { error in
            XCTAssertEqual(
                error as? TrackImportError,
                .fileTooLarge(sizeBytes: 2_000, maximumBytes: 1_000)
            )
        }
        XCTAssertEqual(storage.storeCopyCallCount, 0)
    }

    func test_insufficientStorageIsRefusedWithTheRequiredAmount() {
        let storage = RecordingTrackFileStorage()
        storage.capacityBytes = 100
        let sourceURL = URL(fileURLWithPath: "/tmp/source/morceau.wav")
        storage.registerSource(sourceURL, sizeBytes: 80)
        let policy = LocalImportPolicy(maximumFileSizeBytes: 10_000, freeSpaceMarginBytes: 50)

        XCTAssertThrowsError(
            try makeImporter(storage: storage, policy: policy).importTrack(
                LocalImportRequest(sourceURL: sourceURL, userAttestsAdaptationRights: true)
            )
        ) { error in
            XCTAssertEqual(
                error as? TrackImportError,
                .insufficientStorage(requiredBytes: 130, availableBytes: 100)
            )
        }
        XCTAssertEqual(storage.storeCopyCallCount, 0)
    }

    func test_anUnknownRemainingCapacityDoesNotBlockTheImport() throws {
        let storage = RecordingTrackFileStorage()
        storage.capacityBytes = nil
        let sourceURL = URL(fileURLWithPath: "/tmp/source/morceau.wav")
        storage.registerSource(sourceURL, sizeBytes: 1024)

        let track = try makeImporter(storage: storage).importTrack(
            LocalImportRequest(sourceURL: sourceURL, userAttestsAdaptationRights: true)
        )
        XCTAssertTrue(track.isFileAvailable)
    }

    func test_aStorageFailureIsPropagatedAsATypedError() {
        let storage = RecordingTrackFileStorage()
        storage.copyError = .accessDenied
        let sourceURL = URL(fileURLWithPath: "/tmp/source/morceau.wav")
        storage.registerSource(sourceURL, sizeBytes: 1024)

        XCTAssertThrowsError(
            try makeImporter(storage: storage).importTrack(
                LocalImportRequest(sourceURL: sourceURL, userAttestsAdaptationRights: true)
            )
        ) { error in
            XCTAssertEqual(error as? TrackImportError, .accessDenied)
        }
    }

    // MARK: - Catalogue et BPM manuel

    func test_anUnattestedImportIsStoredButNeverAdjustable() throws {
        let storage = RecordingTrackFileStorage()
        let sourceURL = URL(fileURLWithPath: "/tmp/source/morceau.wav")
        storage.registerSource(sourceURL, sizeBytes: 1024)
        var catalog = LocalLibraryCatalog(storage: storage)

        let track = try catalog.importTrack(
            LocalImportRequest(sourceURL: sourceURL, userAttestsAdaptationRights: false)
        )

        XCTAssertFalse(track.canAlterTempo, "Un import sans attestation explicite reste non ajustable")
        XCTAssertEqual(catalog.storedTracks.map(\.id), [track.id], "Le morceau reste visible dans la bibliothèque")
        XCTAssertEqual(storage.storeCopyCallCount, 1)
    }

    func test_manualBPMMakesTheTrackSynchronisable() throws {
        let storage = RecordingTrackFileStorage()
        let sourceURL = URL(fileURLWithPath: "/tmp/source/morceau.wav")
        storage.registerSource(sourceURL, sizeBytes: 1024)
        var catalog = LocalLibraryCatalog(storage: storage)
        let track = try catalog.importTrack(
            LocalImportRequest(sourceURL: sourceURL, userAttestsAdaptationRights: true)
        )

        try catalog.setManualBPM(168, forTrackID: track.id)

        let updated = try XCTUnwrap(catalog.storedTracks.first)
        XCTAssertEqual(updated.nominalBPM, 168)
        XCTAssertEqual(updated.bpmProvenance, .manual)
        XCTAssertEqual(updated.bpmConfidence, 1.0)
        XCTAssertTrue(updated.isTempoAdjustable)

        let evaluation = TempoMatcher().evaluate(track: updated, targetCadenceSPM: 170)
        XCTAssertEqual(evaluation.requiredRateRaw ?? 0, 170.0 / 168.0, accuracy: 1e-12)
        XCTAssertTrue(evaluation.isAdmissible)
    }

    func test_anInvalidManualBPMIsRefusedAndLeavesTheTrackUntouched() throws {
        let storage = RecordingTrackFileStorage()
        let sourceURL = URL(fileURLWithPath: "/tmp/source/morceau.wav")
        storage.registerSource(sourceURL, sizeBytes: 1024)
        var catalog = LocalLibraryCatalog(storage: storage)
        let track = try catalog.importTrack(
            LocalImportRequest(sourceURL: sourceURL, userAttestsAdaptationRights: true)
        )

        // Appel mutateur : on l'écrit explicitement pour que l'intention soit claire
        // (l'appel ne doit modifier ni le catalogue ni le descripteur).
        for invalidValue in [0.0, -120.0, Double.nan, Double.infinity] {
            var working = catalog
            do {
                try working.setManualBPM(invalidValue, forTrackID: track.id)
                XCTFail("Un BPM invalide (\(invalidValue)) doit être refusé")
            } catch let error as TrackMetadataError {
                guard case .invalidBPM = error else {
                    return XCTFail("Erreur inattendue : \(error)")
                }
            } catch {
                return XCTFail("Erreur inattendue : \(error)")
            }
        }

        let unchanged = try XCTUnwrap(catalog.storedTracks.first)
        XCTAssertNil(unchanged.nominalBPM)
        XCTAssertEqual(unchanged.bpmProvenance, .unknown)
        XCTAssertFalse(unchanged.hasUsableNominalBPM)
    }

    func test_removingATrackDeletesItsFileAndItsLibraryEntry() throws {
        let storage = RecordingTrackFileStorage()
        let sourceURL = URL(fileURLWithPath: "/tmp/source/morceau.wav")
        storage.registerSource(sourceURL, sizeBytes: 1024)
        var catalog = LocalLibraryCatalog(storage: storage)
        let track = try catalog.importTrack(
            LocalImportRequest(sourceURL: sourceURL, userAttestsAdaptationRights: true)
        )
        let relativePath = try XCTUnwrap(track.relativePath)
        XCTAssertTrue(storage.storedFiles[relativePath] != nil)

        try catalog.removeTrack(id: track.id)

        XCTAssertTrue(catalog.storedTracks.isEmpty)
        XCTAssertNil(storage.storedFiles[relativePath], "Le fichier importé est bien supprimé")
        XCTAssertEqual(storage.removeCallCount, 1)

        // Suppression idempotente : aucune erreur si le morceau n'existe plus.
        try catalog.removeTrack(id: track.id)
        XCTAssertTrue(catalog.storedTracks.isEmpty)
    }

    func test_theDefaultPolicyAcceptsTheExpectedExtensionsAndRejectsTheRest() {
        let policy = LocalImportPolicy.standard
        XCTAssertTrue(policy.isValid)
        for accepted in ["m4a", "mp3", "wav", "aif", "aiff", "caf", "aac", "mp4"] {
            XCTAssertTrue(policy.acceptedExtensions.contains(accepted), "\(accepted) devrait être accepté")
        }
        for rejected in ["ogg", "flac", "opus", "wma"] {
            XCTAssertFalse(policy.acceptedExtensions.contains(rejected), "\(rejected) ne doit pas être accepté sans vérification")
        }
    }
}
