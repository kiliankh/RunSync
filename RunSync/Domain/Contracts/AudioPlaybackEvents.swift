import Foundation

/// Événements du moteur audio que la session doit connaître (FR-008, FR-017,
/// NFR-006).
///
/// Le Domain ne connaît ni `AVAudioSession` ni `MediaPlayer` : l'adaptateur
/// traduit les notifications système en ces cas, et l'app décide de la conduite à
/// tenir. Aucune reprise automatique n'est implicite : `interruptionEnded` porte
/// explicitement l'information « la reprise est recommandée », et l'app reste
/// seule juge (§05, §07).
public enum AudioPlaybackEvent: Sendable, Equatable {
    /// Un morceau est arrivé à sa fin naturelle (et non à cause d'un arrêt).
    case trackFinished(trackID: UUID)
    /// Une interruption système a commencé (appel, Siri, autre app).
    case interruptionBegan
    /// L'interruption est terminée. `shouldResume` reproduit la recommandation
    /// système ; la session ne reprend que si elle était en cours d'écoute.
    case interruptionEnded(shouldResume: Bool)
    /// La sortie audio a disparu (écouteurs débranchés, casque Bluetooth perdu) :
    /// la lecture est mise en pause plutôt que de basculer sur le haut-parleur.
    case outputRouteLost
    /// Commande système « lecture » (écran verrouillé, écouteurs, CarPlay).
    /// Le moteur ne l'exécute pas lui-même : la session reste propriétaire de la
    /// machine à états et décide.
    case playRequested
    /// Commande système « pause ».
    case pauseRequested
    /// Commande système « morceau suivant ».
    case nextTrackRequested
    /// Erreur audio non récupérable. Message utilisateur, sans donnée sensible.
    case failed(message: String)
}

/// État de lecture observable par l'interface (§03 E05) : durée, position, état.
/// Tous les champs sont optionnels ou explicites ; rien n'est inventé.
public struct AudioPlaybackState: Sendable, Equatable {
    public var preparedTrackID: UUID?
    public var isPlaying: Bool
    /// Position de lecture en secondes, `nil` si rien n'est chargé.
    public var elapsedSeconds: Double?
    /// Durée du morceau en secondes, `nil` si inconnue.
    public var durationSeconds: Double?
    /// Dernière vitesse appliquée (1.0 = tempo original).
    public var rate: Double

    public static let idle = AudioPlaybackState(
        preparedTrackID: nil,
        isPlaying: false,
        elapsedSeconds: nil,
        durationSeconds: nil,
        rate: 1.0
    )

    public init(
        preparedTrackID: UUID?,
        isPlaying: Bool,
        elapsedSeconds: Double?,
        durationSeconds: Double?,
        rate: Double
    ) {
        self.preparedTrackID = preparedTrackID
        self.isPlaying = isPlaying
        self.elapsedSeconds = elapsedSeconds
        self.durationSeconds = durationSeconds
        self.rate = rate
    }
}

/// Rapport d'événements audio. Séparé de `AudioPlayback` pour qu'un lecteur
/// minimal (course sans audio) n'ait pas à fabriquer un flux d'événements.
public protocol AudioEventReporting: Sendable {
    /// Flux d'événements du moteur. Un seul consommateur à la fois.
    ///
    /// `async` volontairement : le moteur réel est un `actor`, et une exigence
    /// synchrone ne pourrait pas être satisfaite par une méthode isolée à un acteur.
    func events() async -> AsyncStream<AudioPlaybackEvent>
}
