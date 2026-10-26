import Foundation
import Observation
import RunSyncDomain
import RunSyncPersistence
import UniformTypeIdentifiers

/// Bibliothèque locale de l'application (RS-020).
///
/// Cette classe est l'**adaptateur** : elle ouvre l'accès aux fichiers choisis
/// hors de la sandbox (security-scoped URL, API propre à iOS/macOS) puis délègue
/// toute la logique d'import, de validation et de réconciliation au noyau
/// portable testé (`LocalTrackImporter`, `LocalLibraryReconciler`,
/// `FileSystemTrackStorage`).
///
/// La persistance entre lancements reste à faire (RS-033) : la bibliothèque est
/// rechargée à chaque démarrage, elle ne survit pas à la fermeture de l'application.
/// L'écran le dit explicitement.
@Observable
final class LocalLibraryStore {

    private(set) var tracks: [TrackDescriptor] = []
    private(set) var lastErrorMessage: String?
    private(set) var lastImportSummary: String?
    /// Types de fichiers proposés par le sélecteur système. La validation fine des
    /// formats reste faite par le noyau (`LocalImportPolicy`).
    let importableContentTypes: [UTType]

    private var catalog: LocalLibraryCatalog
    private let storage: FileSystemTrackStorage

    init(storage: FileSystemTrackStorage) {
        self.storage = storage
        self.catalog = LocalLibraryCatalog(storage: storage)
        var types: [UTType] = [.audio]
        types.append(contentsOf: [.mp3, .wav, .mpeg4Audio, .aiff].filter { $0 != .audio })
        self.importableContentTypes = types
    }

    /// Stockage par défaut : un sous-répertoire privé de l'application.
    static func makeDefaultStore() -> LocalLibraryStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return LocalLibraryStore(
            storage: FileSystemTrackStorage(
                rootDirectory: base.appendingPathComponent("RunSync", isDirectory: true)
            )
        )
    }

    /// Import d'un fichier choisi par l'utilisateur.
    ///
    /// - Parameter userAttestsAdaptationRights: déclaration explicite de l'utilisateur.
    ///   Sans elle, le morceau est importé mais reste **non tempo-ajustable** (§02).
    @discardableResult
    func importFile(
        at url: URL,
        userAttestsAdaptationRights: Bool,
        declaredTitle: String? = nil
    ) -> Bool {
        lastErrorMessage = nil
        lastImportSummary = nil

        // Un fichier choisi hors sandbox nécessite l'ouverture explicite de l'accès.
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            let track = try catalog.importTrack(
                LocalImportRequest(
                    sourceURL: url,
                    declaredTitle: declaredTitle,
                    userAttestsAdaptationRights: userAttestsAdaptationRights
                )
            )
            tracks = catalog.storedTracks
            lastImportSummary = userAttestsAdaptationRights
                ? "« \(track.title) » importé. Saisissez son BPM pour le rendre synchronisable."
                : "« \(track.title) » importé sans attestation : tempo non ajustable."
            return true
        } catch let error as TrackImportError {
            lastErrorMessage = error.displayMessage
            return false
        } catch {
            lastErrorMessage = "Import impossible."
            return false
        }
    }

    /// Vérifie que chaque fichier est toujours présent (§09) et retourne ceux qui
    /// ont disparu, pour que l'interface puisse le signaler.
    @discardableResult
    func refreshAvailability() -> [UUID] {
        let result = catalog.refreshAvailability()
        tracks = catalog.storedTracks
        return result.missingTrackIDs
    }

    func setManualBPM(_ bpm: Double?, for trackID: UUID) {
        do {
            try catalog.setManualBPM(bpm, forTrackID: trackID)
            tracks = catalog.storedTracks
            lastErrorMessage = nil
        } catch let error as TrackMetadataError {
            lastErrorMessage = error.displayMessage
        } catch {
            lastErrorMessage = "BPM refusé."
        }
    }

    func remove(trackID: UUID) {
        do {
            try catalog.removeTrack(id: trackID)
            tracks = catalog.storedTracks
            lastErrorMessage = nil
        } catch let error as TrackImportError {
            lastErrorMessage = error.displayMessage
        } catch {
            lastErrorMessage = "Suppression impossible."
        }
    }

    // MARK: - Morceau de test intégré

    /// Nom de ressource du morceau de test fourni avec l'application.
    static let bundledTestToneResource = "runsync-test-clicks-168bpm"
    /// Tempo connu du morceau de test (vérifié : 84 attaques, 168,0000 BPM mesurés).
    static let bundledTestToneBPM: Double = 168

    /// Le morceau de test est-il présent dans le paquet de l'application ?
    var isBundledTestToneAvailable: Bool {
        Bundle.main.url(forResource: Self.bundledTestToneResource, withExtension: "wav") != nil
    }

    /// Ajoute le morceau de test intégré à la bibliothèque locale.
    ///
    /// Ce fichier est **produit par le projet** (`Tools/generate_test_tone.py`,
    /// domaine public) : ses droits d'adaptation sont établis sans attestation
    /// utilisateur, contrairement à un morceau importé (§02). Il passe exactement
    /// par le même chemin d'import qu'un fichier utilisateur, ce qui permet de
    /// vérifier ce chemin sur l'appareil — et son BPM est renseigné tout de suite,
    /// sans quoi il ne serait pas synchronisable.
    @discardableResult
    func addBundledTestTrack() -> Bool {
        lastErrorMessage = nil
        lastImportSummary = nil
        guard let url = Bundle.main.url(
            forResource: Self.bundledTestToneResource,
            withExtension: "wav"
        ) else {
            lastErrorMessage = "Le morceau de test intégré est absent de l'application."
            return false
        }
        do {
            let track = try catalog.importTrack(
                LocalImportRequest(
                    sourceURL: url,
                    declaredTitle: "Clics de test 168 BPM",
                    declaredArtist: "RunSync (domaine public)",
                    userAttestsAdaptationRights: true
                )
            )
            try catalog.setManualBPM(Self.bundledTestToneBPM, forTrackID: track.id)
            tracks = catalog.storedTracks
            lastImportSummary = "« \(track.title) » ajouté : 168 BPM, tempo ajustable."
            return true
        } catch let error as TrackImportError {
            lastErrorMessage = error.displayMessage
            return false
        } catch let error as TrackMetadataError {
            lastErrorMessage = error.displayMessage
            return false
        } catch {
            lastErrorMessage = "Ajout du morceau de test impossible."
            return false
        }
    }

    /// URL absolue d'un morceau importé (lecture audio, RS-021).
    func absoluteURL(for track: TrackDescriptor) -> URL? {
        guard let relativePath = track.relativePath else { return nil }
        return try? storage.absoluteURL(forRelativePath: relativePath)
    }

    func dismissMessage() {
        lastErrorMessage = nil
        lastImportSummary = nil
    }

    /// Signale un échec survenu dans la couche système (sélecteur de fichiers).
    func reportImportFailure(_ message: String) {
        lastErrorMessage = message
    }
}
