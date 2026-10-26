import Foundation

/// Contrat de lecture audio (§07).
///
/// Un lecteur ne reçoit **jamais** le droit d'altérer un flux simplement parce
/// qu'il sait lire un titre : `supportsTempoAdjustment` décrit une capacité, et
/// toute demande de rate passe par `TempoAdjustmentGate`, qui vérifie la source
/// et la conformité (§02).
public protocol AudioPlayback: Sendable {
    /// Capacité déclarée par ce lecteur pour la source en cours.
    var supportsTempoAdjustment: Bool { get }

    /// Prépare un morceau à partir de **son fichier local**. Le descripteur est
    /// transmis avec l'URL pour que le lecteur puisse vérifier lui-même les droits
    /// d'adaptation (attestation, BPM, provenance) avant toute lecture : un lecteur
    /// qui ne recevrait qu'un identifiant ne pourrait pas appliquer la garde de
    /// conformité (§02, écart documenté dans Docs/ARCHITECTURE.md).
    func prepare(track: TrackDescriptor, fileURL: URL) async throws
    func play() async throws
    func pause() async
    func stop() async

    /// Demande de vitesse de lecture. L'implémentation **doit** revalider la
    /// valeur avec `TempoAdjustmentGate` : le fait que le contrôleur ait déjà borné
    /// la consigne ne dispense jamais de vérifier les droits de la source (T013).
    func setRate(_ rate: Float) async throws

    /// Position de lecture demandée, en secondes depuis le début du morceau (FR-008).
    /// Une position hors du morceau est bornée, jamais propagée telle quelle.
    func seek(toElapsedSeconds seconds: Double) async throws

    /// État courant, pour l'affichage de session (§03 E05).
    func state() async -> AudioPlaybackState

    /// Morceau actuellement préparé, si connu (diagnostic et UI).
    var preparedTrackID: UUID? { get }
}
