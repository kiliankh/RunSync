import XCTest
import RunSyncDomain
import RunSyncPersistence
import RunSyncSimulation

/// Tests d'écriture réelle sur disque (répertoire temporaire) : c'est la partie
/// de RS-020 qui peut être vérifiée sans iPhone.
final class FileSystemTrackStorageTests: XCTestCase {

    private func makeTemporaryRoot() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("runsync-tests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeSourceFile(named name: String, sizeBytes: Int) throws -> URL {
        let url = makeTemporaryRoot().appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = Data(repeating: 0x41, count: sizeBytes)
        try data.write(to: url)
        return url
    }

    // MARK: - Copie et existence

    func test_copyStoresTheFileAndReportsItsRealSize() throws {
        let root = makeTemporaryRoot()
        let storage = FileSystemTrackStorage(rootDirectory: root)
        let source = try makeSourceFile(named: "tonalite-test.wav", sizeBytes: 4096)

        let reference = try storage.storeCopy(
            from: source,
            suggestedFileName: "\(UUID().uuidString).wav"
        )

        XCTAssertEqual(reference.sizeBytes, 4096)
        XCTAssertTrue(try storage.fileExists(relativePath: reference.relativePath))
        let onDisk = storage.importDirectory.appendingPathComponent(reference.relativePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: onDisk.path))
        XCTAssertEqual(try storage.sizeOfFile(at: onDisk), 4096)
        // Le fichier source reste intact : c'est une copie, pas un déplacement.
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func test_theImportDirectoryIsCreatedOnDemandAndReused() throws {
        let root = makeTemporaryRoot()
        let storage = FileSystemTrackStorage(rootDirectory: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.importDirectory.path))

        let first = try storage.storeCopy(
            from: try makeSourceFile(named: "a.wav", sizeBytes: 16),
            suggestedFileName: "a.wav"
        )
        let second = try storage.storeCopy(
            from: try makeSourceFile(named: "b.wav", sizeBytes: 32),
            suggestedFileName: "b.wav"
        )

        XCTAssertTrue(try storage.fileExists(relativePath: first.relativePath))
        XCTAssertTrue(try storage.fileExists(relativePath: second.relativePath))
        XCTAssertEqual(second.sizeBytes, 32)
    }

    func test_missingSourceFileIsReportedAsNilSize() throws {
        let storage = FileSystemTrackStorage(rootDirectory: makeTemporaryRoot())
        XCTAssertNil(try storage.sizeOfFile(at: URL(fileURLWithPath: "/tmp/absent-\(UUID().uuidString).wav")))
    }

    func test_removingAFileIsIdempotent() throws {
        let storage = FileSystemTrackStorage(rootDirectory: makeTemporaryRoot())
        let reference = try storage.storeCopy(
            from: try makeSourceFile(named: "c.wav", sizeBytes: 16),
            suggestedFileName: "c.wav"
        )

        try storage.removeFile(relativePath: reference.relativePath)
        XCTAssertFalse(try storage.fileExists(relativePath: reference.relativePath))
        // Deuxième suppression : aucune erreur, aucun état incohérent.
        try storage.removeFile(relativePath: reference.relativePath)
    }

    // MARK: - Sécurité des chemins

    func test_aPathTraversalAttemptIsRefused() throws {
        let storage = FileSystemTrackStorage(rootDirectory: makeTemporaryRoot())
        let source = try makeSourceFile(named: "d.wav", sizeBytes: 16)

        for unsafeName in ["../evasion.wav", "sous/dossier.wav", "..", "", "   ", "C:\\evil.wav"] {
            XCTAssertThrowsError(try storage.storeCopy(from: source, suggestedFileName: unsafeName)) { error in
                XCTAssertEqual(error as? TrackImportError, .invalidFileName)
            }
        }

        XCTAssertThrowsError(try storage.fileExists(relativePath: "../evasion.wav")) { error in
            XCTAssertEqual(error as? TrackImportError, .invalidFileName)
        }
        // Aucun fichier n'a été créé hors du répertoire d'import.
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: storage.rootDirectory.appendingPathComponent("evasion.wav").path
        ))
    }

    // MARK: - Import de bout en bout et réconciliation (T014)

    func test_anUnsupportedExtensionIsRefusedWithoutCreatingAnyFile() throws {
        let root = makeTemporaryRoot()
        let storage = FileSystemTrackStorage(rootDirectory: root)
        var catalog = LocalLibraryCatalog(storage: storage)
        let source = try makeSourceFile(named: "musique.ogg", sizeBytes: 1024)

        do {
            _ = try catalog.importTrack(
                LocalImportRequest(sourceURL: source, userAttestsAdaptationRights: true)
            )
            XCTFail("Un format non pris en charge doit être refusé")
        } catch let error as TrackImportError {
            XCTAssertEqual(error, .unsupportedFormat("ogg"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.importDirectory.path))
        XCTAssertTrue(catalog.storedTracks.isEmpty)
    }

    func test_aRealImportIsUsableByTheTempoEngine() throws {
        let root = makeTemporaryRoot()
        let storage = FileSystemTrackStorage(rootDirectory: root)
        var catalog = LocalLibraryCatalog(storage: storage)
        let source = try makeSourceFile(named: "tonalite-168.wav", sizeBytes: 2048)

        let imported = try catalog.importTrack(
            LocalImportRequest(sourceURL: source, userAttestsAdaptationRights: true)
        )
        try catalog.setManualBPM(168, forTrackID: imported.id)
        let track = try XCTUnwrap(catalog.storedTracks.first)

        XCTAssertTrue(track.isTempoAdjustable)
        let evaluation = TempoMatcher().evaluate(track: track, targetCadenceSPM: 170)
        XCTAssertTrue(evaluation.isAdmissible)
        XCTAssertEqual(evaluation.requiredRateRaw ?? 0, 170.0 / 168.0, accuracy: 1e-12)
    }

    func test_aDeletedImportedFileNeverStaysFalselyPlayable() throws {
        let root = makeTemporaryRoot()
        let storage = FileSystemTrackStorage(rootDirectory: root)
        var catalog = LocalLibraryCatalog(storage: storage)
        let source = try makeSourceFile(named: "ephemere.wav", sizeBytes: 512)

        let imported = try catalog.importTrack(
            LocalImportRequest(sourceURL: source, userAttestsAdaptationRights: true)
        )
        try catalog.setManualBPM(170, forTrackID: imported.id)
        XCTAssertTrue(try XCTUnwrap(catalog.storedTracks.first).isFileAvailable)

        // Le fichier disparaît (nettoyage système, suppression manuelle, iCloud…).
        try storage.removeFile(relativePath: try XCTUnwrap(imported.relativePath))

        let result = catalog.refreshAvailability()

        XCTAssertEqual(result.missingTrackIDs, [imported.id])
        let after = try XCTUnwrap(catalog.storedTracks.first)
        XCTAssertFalse(after.isFileAvailable)
        XCTAssertFalse(after.isTempoAdjustable)
        // Le morceau reste identifiable : l'utilisateur voit ce qui a disparu.
        XCTAssertEqual(after.title, imported.title)
        XCTAssertEqual(after.nominalBPM, 170)

        // Et le moteur de synchronisation le refuse explicitement.
        let evaluation = TempoMatcher().evaluate(track: after, targetCadenceSPM: 170)
        XCTAssertEqual(evaluation.rejection, .fileUnavailable)
        XCTAssertNil(evaluation.requiredRateRaw)

        // La garde d'ajustement le refuse aussi.
        let gate = TempoAdjustmentGate()
        XCTAssertFalse(
            gate.isPermitted(track: after, provider: ProviderCatalog.localImportedFiles)
        )
    }

    func test_reconciliationLeavesTracksWithoutALocalFileUntouched() {
        let storage = FileSystemTrackStorage(rootDirectory: makeTemporaryRoot())
        let reconciler = LocalLibraryReconciler(storage: storage)

        let result = reconciler.reconcile(DemoLibrary.tracks)

        XCTAssertTrue(result.missingTrackIDs.isEmpty)
        XCTAssertEqual(result.tracks.map(\.isFileAvailable), DemoLibrary.tracks.map(\.isFileAvailable))
        XCTAssertEqual(result.tracks.map(\.id), DemoLibrary.tracks.map(\.id))
    }

    func test_remainingCapacityIsReportedOrUnknownButNeverBlocks() throws {
        let storage = FileSystemTrackStorage(rootDirectory: makeTemporaryRoot())
        // Un volume réel répond en général ; `nil` est accepté (import non bloqué).
        let capacity = try storage.availableCapacityBytes()
        if let capacity {
            XCTAssertGreaterThan(capacity, 0)
        }
    }
}
