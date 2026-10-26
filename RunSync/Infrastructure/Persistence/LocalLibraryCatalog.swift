import Foundation
import RunSyncDomain

/// Bibliothèque locale alimentée par l'import de fichiers (§07, RS-020).
///
/// Elle reste volontairement en mémoire : la persistance SwiftData est l'étape
/// RS-033. Sa logique (import, réconciliation, BPM manuel, suppression) est
/// entièrement testable sans appareil.
///
/// Elle n'est délibérément **pas** un `TrackCatalog` : le protocole expose un
/// import non mutant et sans attestation, alors que cette bibliothèque exige une
/// attestation explicite de droits et enregistre ce qu'elle importe. Un import
/// qui aurait silencieusement échoué à s'enregistrer serait un piège.
public struct LocalLibraryCatalog {
    public private(set) var storedTracks: [TrackDescriptor]
    public let policy: LocalImportPolicy

    private let importer: LocalTrackImporter
    private let reconciler: LocalLibraryReconciler

    public init(
        storedTracks: [TrackDescriptor] = [],
        storage: TrackFileStorage,
        policy: LocalImportPolicy = .standard,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.storedTracks = storedTracks
        self.policy = policy
        self.importer = LocalTrackImporter(storage: storage, policy: policy, now: now)
        self.reconciler = LocalLibraryReconciler(storage: storage)
    }

    // MARK: - Import et gestion

    /// Importe et enregistre un fichier. Sans `userAttestsAdaptationRights`, le
    /// morceau est bien rangé dans la bibliothèque mais reste **non ajustable**, et
    /// le moteur de synchronisation le refuse explicitement (§02).
    public mutating func importTrack(_ request: LocalImportRequest) throws -> TrackDescriptor {
        let descriptor = try importer.importTrack(request)
        storedTracks.removeAll { $0.id == descriptor.id }
        storedTracks.append(descriptor)
        return descriptor
    }

    /// Validation sans effet de bord, pour l'interface (refuser avant de copier).
    public func validateImport(_ request: LocalImportRequest) throws {
        try importer.validate(request)
    }

    /// Vérifie que chaque fichier est toujours présent ; retourne les morceaux disparus.
    @discardableResult
    public mutating func refreshAvailability() -> LibraryReconciliationResult {
        let result = reconciler.reconcile(storedTracks)
        storedTracks = result.tracks
        return result
    }

    /// Supprime un morceau de la bibliothèque et son fichier importé.
    public mutating func removeTrack(id: UUID) throws {
        guard let index = storedTracks.firstIndex(where: { $0.id == id }) else { return }
        if let relativePath = storedTracks[index].relativePath {
            try importer.storage.removeFile(relativePath: relativePath)
        }
        storedTracks.remove(at: index)
    }

    /// Renseigne un BPM saisi par l'utilisateur (FR-007) ; lève une erreur si la
    /// valeur est inexploitable, plutôt que d'enregistrer un BPM faux.
    public mutating func setManualBPM(_ bpm: Double?, forTrackID id: UUID) throws {
        guard let index = storedTracks.firstIndex(where: { $0.id == id }) else { return }
        storedTracks[index] = try storedTracks[index].settingManualBPM(bpm)
    }
}
