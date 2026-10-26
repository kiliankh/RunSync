import Foundation
import Observation
import RunSyncDomain
import RunSyncSimulation

/// Réglages utilisateur (E07). Ils vivent encore en mémoire : la persistance
/// SwiftData arrive avec RS-033.
@Observable
final class AppSettings {
    /// Limite d'ajustement du tempo : ±5 % par défaut, ±3 % en option prudente (FR-009).
    var maxAdjustment: Double = 0.05
    /// Source de cadence : capteur Core Motion sur iPhone, scénario simulé ailleurs
    /// (le simulateur iOS ne fournit jamais de cadence).
    var cadenceSource: CadenceSourceChoice = .coreMotion
    /// Signaux sonores de guidage : désactivés par défaut (§05).
    var audibleGuidanceEnabled: Bool = false
    /// Onboarding terminé (aucun compte, aucun réseau : FR-001).
    var onboardingCompleted: Bool = false

    var matchingPolicy: TempoMatchingPolicy {
        (try? TempoMatchingPolicy(maxAdjustment: maxAdjustment, stepsPerBeatCandidates: [1, 2]))
            ?? .standard
    }
}

/// Source de cadence sélectionnable dans les réglages.
enum CadenceSourceChoice: String, CaseIterable, Identifiable, Sendable {
    case coreMotion
    case simulation

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .coreMotion: return "Capteur de l'iPhone (Core Motion)"
        case .simulation: return "Scénario simulé (démonstration)"
        }
    }

    /// Disponible maintenant ? Le simulateur iOS ne fournit pas de cadence : le dire
    /// évite de croire à un bug.
    var isAvailable: Bool {
        switch self {
        case .coreMotion: return CoreMotionCadenceSource.availability.canRun
        case .simulation: return true
        }
    }

    var availabilityMessage: String {
        switch self {
        case .coreMotion:
            return CoreMotionCadenceSource.availability.displayMessage
        case .simulation:
            return "Scénario déterministe 170 → 176 → 160 → capteur perdu → 170 SPM, "
                + "utilisable partout, y compris dans le simulateur."
        }
    }
}

/// Paramètres d'une course, transmis de l'écran de préparation à l'écran live (§03 E04).
struct RunConfiguration: Equatable, Sendable {
    var mode: RunMode = .follow
    /// Cadence cible déclarée en mode Pace (jamais déduite de la seule allure, §05).
    var targetCadenceSPM: Double = 170
    /// Allure cible en secondes par kilomètre (affichage de l'écart uniquement).
    var targetPaceSecondsPerKilometer: Double? = 300
    var playlistTrackIDs: [UUID] = [DemoLibrary.testTrackID]
    /// Autorise une course sans audio (démonstration du scénario de cadence seule).
    /// Le bouton « Démarrer » reste actif sans cette option dès qu'un morceau
    /// réellement jouable est sélectionné.
    var allowRunWithoutAudio: Bool = false
}

/// Morceau programmé pour une course, avec son fichier local quand il existe.
///
/// `url == nil` signifie « descripteur sans fichier » : l'écran de session ne
/// prétend alors rien jouer (les morceaux de démonstration n'ont pas d'audio).
struct RunAudioItem: Identifiable, Sendable {
    let track: TrackDescriptor
    let url: URL?

    var id: UUID { track.id }
}

/// Composition root (§06) : un seul endroit construit les dépendances concrètes.
/// Les vues ne connaissent que les protocoles du Domain.
@Observable
final class DependencyContainer {
    let settings: AppSettings
    let audioPlayback: AudioPlayback
    /// Rapport d'événements du moteur audio (interruptions, fin de morceau,
    /// commandes système). `nil` si le lecteur injecté n'en fournit pas.
    let audioEventSource: (any AudioEventReporting)?
    let library: LocalLibraryStore

    /// Dernière configuration utilisée et dernier résumé, pour l'écran Accueil (E02).
    /// En mémoire uniquement : la persistance arrive avec RS-033.
    var lastRunConfiguration: RunConfiguration?
    var lastRunMetrics: RunMetricsSnapshot?

    init(
        settings: AppSettings = AppSettings(),
        audioPlayback: AudioPlayback? = nil,
        library: LocalLibraryStore = LocalLibraryStore.makeDefaultStore()
    ) {
        self.settings = settings
        self.library = library
        let playback = audioPlayback ?? AudioEnginePlayback(policy: settings.matchingPolicy)
        self.audioPlayback = playback
        self.audioEventSource = playback as? (any AudioEventReporting)
    }

    /// Morceaux proposables pour une course : la bibliothèque réelle dès qu'elle
    /// contient un morceau disponible, sinon le jeu de démonstration (sans fichier).
    var availableTracks: [TrackDescriptor] {
        // Un fichier disparu ne doit jamais rester jouable (§09) ; s'il ne reste
        // aucun morceau réel, les descripteurs de démonstration prennent le relais.
        let usable = library.tracks.filter { $0.isFileAvailable }
        return usable.isEmpty ? DemoLibrary.tracks : usable
    }

    var providers: [MusicProviderCapabilities] { ProviderCatalog.all }

    func provider(id: String) -> MusicProviderCapabilities? {
        ProviderCatalog.provider(id: id)
    }

    /// Chemin du fichier local d'un morceau, `nil` pour un descripteur sans fichier
    /// (morceaux de démonstration) ou un fichier disparu.
    func audioFileURL(for track: TrackDescriptor) -> URL? {
        guard track.isFileAvailable else { return nil }
        return library.absoluteURL(for: track)
    }

    /// Playlist effective d'une course : les morceaux choisis, dans l'ordre, avec
    /// leur fichier quand il existe. Un seul morceau jouable reste une playlist
    /// valide ; un morceau sans fichier n'est proposé que si le mode sans audio est
    /// explicitement choisi.
    func audioItems(for configuration: RunConfiguration) -> [RunAudioItem] {
        let available = availableTracks
        let ordered = configuration.playlistTrackIDs.compactMap { identifier in
            available.first { $0.id == identifier }
        }
        let fallback = ordered.isEmpty ? Array(available.prefix(1)) : ordered
        return fallback.map { RunAudioItem(track: $0, url: audioFileURL(for: $0)) }
    }

    /// La session peut-elle réellement jouer quelque chose ? C'est cette question,
    /// et non une supposition, qui active le bouton « Démarrer ».
    func hasPlayableAudio(for configuration: RunConfiguration) -> Bool {
        audioItems(for: configuration).contains { $0.url != nil }
    }

    /// Construit le modèle de l'écran live. La dépendance de cadence est injectée :
    /// Core Motion quand l'appareil le permet, scénario simulé sinon — et l'écran
    /// affiche toujours laquelle des deux il utilise.
    @MainActor
    func makeActiveRunViewModel(configuration: RunConfiguration) -> ActiveRunViewModel {
        let items = audioItems(for: configuration)
        let sensor = CoreMotionCadenceSource.availability
        let source: any CadenceSource
        let description: String
        switch settings.cadenceSource {
        case .coreMotion where sensor.canRun:
            source = CoreMotionCadenceSource()
            description = "Cadence mesurée par le capteur de l'iPhone (Core Motion)"
        case .coreMotion:
            source = FakeCadenceSource(scenario: .demoFollow, tickInterval: 1.0, startDate: Date())
            description = "Cadence simulée : capteur indisponible. \(sensor.displayMessage)"
        case .simulation:
            source = FakeCadenceSource(scenario: .demoFollow, tickInterval: 1.0, startDate: Date())
            description = "Cadence simulée (scénario déterministe)"
        }
        return ActiveRunViewModel(
            configuration: configuration,
            audioItems: items,
            cadenceSource: source,
            cadenceSourceDescription: description,
            audioPlayback: audioPlayback,
            audioEventSource: audioEventSource,
            settings: settings
        )
    }

    /// Mémorise le résumé d'une course terminée (aucune écriture disque pour l'instant).
    @MainActor
    func recordFinishedRun(configuration: RunConfiguration, metrics: RunMetricsSnapshot) {
        lastRunConfiguration = configuration
        lastRunMetrics = metrics
    }
}
