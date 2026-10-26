import Foundation
import RunSyncDomain

/// Lecteur inactif : course de démonstration sans audio (§03 E04).
///
/// Il ne simule **rien** : aucune position, aucun rate, aucune lecture. Chaque
/// opération qui prétendrait jouer quelque chose échoue avec une erreur typée
/// explicite, ce qui garantit qu'aucun écran ne peut afficher « en cours de
/// lecture » alors qu'aucun son ne sort.
final class NoAudioPlayback: AudioPlayback {

    /// Sans audio, il n'y a rien à ajuster : c'est faux, et l'interface le dit.
    var supportsTempoAdjustment: Bool { false }

    func prepare(track: TrackDescriptor, fileURL: URL) async throws {
        throw AudioPlaybackError.playbackUnavailable(reason: "course sans audio")
    }

    func play() async throws {
        throw AudioPlaybackError.playbackUnavailable(reason: "course sans audio")
    }

    /// Pause et arrêt restent des non-actions sûres : elles ne peuvent pas laisser
    /// l'application dans un état fantôme.
    func pause() async {}

    func stop() async {}

    func setRate(_ rate: Float) async throws {
        throw AudioPlaybackError.playbackUnavailable(reason: "aucun moteur audio actif")
    }

    func seek(toElapsedSeconds seconds: Double) async throws {
        throw AudioPlaybackError.playbackUnavailable(reason: "aucun moteur audio actif")
    }

    func state() async -> AudioPlaybackState { .idle }
}
