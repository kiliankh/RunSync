import Foundation
import RunSyncDomain

/// Catalogue statique en mémoire (§16.F : démonstration sans fournisseur tiers).
///
/// Aucune connexion réseau, aucune source tierce : uniquement des descripteurs
/// de morceaux de démonstration. Les fichiers audio réels ne sont pas inclus
/// dans le dépôt (`.gitignore`) et l'import local est l'étape RS-020.
public struct StaticTrackCatalog: TrackCatalog {
    public let availableTracks: [TrackDescriptor]

    public init(tracks: [TrackDescriptor]) {
        self.availableTracks = tracks
    }

    public func tracks() async throws -> [TrackDescriptor] {
        availableTracks
    }

    public func importLocalFile(from url: URL) async throws -> TrackDescriptor {
        // Volontairement non implémenté : l'import réel (security-scoped URLs,
        // copie sandbox, formats AVFoundation) est l'étape RS-020.
        throw TrackImportError.notImplementedInCurrentPhase
    }
}

/// Jeu de données de démonstration de la phase 1.
public enum DemoLibrary {

    /// UUID fixes pour rendre la démonstration et les tests reproductibles.
    public static let testTrackID = Self.fixedUUID("00000000-0000-0000-0000-0000000000A1")
    public static let bpmUnknownTrackID = Self.fixedUUID("00000000-0000-0000-0000-0000000000A2")
    public static let slowTrackID = Self.fixedUUID("00000000-0000-0000-0000-0000000000A3")

    /// Morceau de test à 168 BPM, BPM saisi manuellement (priorité FR-007).
    /// Utilisé par l'écran live de démonstration (§16.F).
    public static let testTrack = TrackDescriptor(
        id: testTrackID,
        title: "Tonalité de test 168 BPM",
        artist: "Asset libre de droits (démo)",
        nominalBPM: 168,
        bpmProvenance: .manual,
        bpmConfidence: 1.0,
        durationSeconds: 180,
        providerID: ProviderCatalog.localImportedFiles.id,
        canAlterTempo: true,
        isFileAvailable: true,
        isAdaptationRightsAttested: true
    )

    /// Morceau sans BPM connu : ne doit jamais être présenté comme synchronisable.
    public static let bpmUnknownTrack = TrackDescriptor(
        id: bpmUnknownTrackID,
        title: "Morceau sans BPM renseigné",
        artist: "Démo",
        nominalBPM: nil,
        bpmProvenance: .unknown,
        bpmConfidence: nil,
        durationSeconds: 200,
        providerID: ProviderCatalog.localImportedFiles.id,
        canAlterTempo: true,
        isFileAvailable: true,
        isAdaptationRightsAttested: true
    )

    /// Morceau à 150 BPM : alternative admissible pour une cadence de 150 SPM
    /// (sert à montrer la suggestion de changement de morceau, §05 exemple C).
    public static let slowTrack = TrackDescriptor(
        id: slowTrackID,
        title: "Tonalité de test 150 BPM",
        artist: "Asset libre de droits (démo)",
        nominalBPM: 150,
        bpmProvenance: .manual,
        bpmConfidence: 1.0,
        durationSeconds: 180,
        providerID: ProviderCatalog.localImportedFiles.id,
        canAlterTempo: true,
        isFileAvailable: true,
        isAdaptationRightsAttested: true
    )

    public static let tracks: [TrackDescriptor] = [testTrack, slowTrack, bpmUnknownTrack]

    public static let catalog = StaticTrackCatalog(tracks: tracks)

    private static func fixedUUID(_ string: String) -> UUID {
        UUID(uuidString: string) ?? UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    }
}
