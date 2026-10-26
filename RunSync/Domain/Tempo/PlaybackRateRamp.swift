import Foundation

/// Rampe de vitesse de lecture : la frontière entre la décision de tempo et le
/// moteur audio (§05, NFR-004).
///
/// Pourquoi ce type existe : `FollowController` et `PaceController` calculent une
/// consigne, mais cette consigne est réévaluée à chaque mesure du capteur, alors
/// que le paramètre audio ne doit **jamais** être écrit à chaque pas. Le cahier
/// des charges impose deux choses distinctes :
/// - une dérivée de `playbackRate` limitée à ≈ 0,01 par seconde ;
/// - une mise à jour effective du paramètre audio à intervalle contrôlé (4 Hz au
///   maximum).
///
/// Cette rampe est du Swift pur, sans AVFAudio : elle est donc testable sans
/// iPhone, ce qui est précisément là où un défaut coûterait le plus cher (une
/// marche audible dans la musique).
///
/// Comportement précis :
/// - `acceptTarget` mémorise la consigne, bornée par la politique (une consigne
///   non finie est rejetée et devient le tempo original, jamais une borne
///   inventée) ;
/// - `command(at:)` fait avancer la vitesse courante vers cette consigne d'au plus
///   `maximumSlewPerSecond` par seconde écoulée, et ne retourne une commande que
///   si l'intervalle minimal est écoulé **et** si le changement est perceptible ;
/// - une consigne absente (`nil`) signifie « maintenir » : la vitesse courante ne
///   bouge pas, ce qui est exactement l'état HOLD de la §05 ;
/// - la vitesse courante est initialisée à 1.0 (tempo original), jamais à une
///   valeur inventée.
public struct PlaybackRateRamp: Sendable, Equatable {

    /// Instruction à transmettre au moteur audio. `rate` est la vitesse effective
    /// à appliquer (1.0 = tempo original, hauteur préservée par le moteur).
    public struct Command: Sendable, Equatable {
        public let rate: Double
        public let timestamp: Date
        /// Vrai pour la première commande d'une session (état initial explicite).
        public let isInitial: Bool

        public init(rate: Double, timestamp: Date, isInitial: Bool = false) {
            self.rate = rate
            self.timestamp = timestamp
            self.isInitial = isInitial
        }
    }

    public let policy: TempoMatchingPolicy

    /// Dérivée maximale de la vitesse, par seconde (≈ 1 point de %/s).
    public let maximumSlewPerSecond: Double

    /// Intervalle minimal entre deux commandes : borne la fréquence d'écriture du
    /// graphe audio (4 Hz par défaut, comme le recommande la §05).
    public let minimumCommandInterval: TimeInterval

    /// Pas de commande en dessous de ce changement : inutile d'écrire au moteur
    /// audio pour un écart inaudible.
    public let minimumEmittedDelta: Double

    /// Borne haute du temps pris en compte entre deux évaluations. Sans elle, une
    /// longue période d'inactivité autoriserait un rattrapage brutal de plusieurs
    /// points de pourcentage en une seule écriture — précisément la marche audible
    /// que cette rampe doit empêcher.
    public let maximumEvaluationStepSeconds: TimeInterval

    /// Consigne courante, déjà bornée. `nil` = maintien de la vitesse actuelle.
    public private(set) var targetRate: Double?
    /// Vitesse appliquée à la dernière commande émise.
    public private(set) var currentRate: Double

    private var lastEvaluationTimestamp: Date?
    private var lastEmittedRate: Double?
    private var lastEmittedTimestamp: Date?

    public init(
        policy: TempoMatchingPolicy = .standard,
        maximumSlewPerSecond: Double = 0.01,
        minimumCommandInterval: TimeInterval = 0.25,
        minimumEmittedDelta: Double = 0.0005,
        maximumEvaluationStepSeconds: TimeInterval = 1.0
    ) {
        self.policy = policy
        self.maximumSlewPerSecond = maximumSlewPerSecond.isFinite
            ? max(0, maximumSlewPerSecond)
            : 0.01
        self.minimumCommandInterval = minimumCommandInterval.isFinite
            ? max(0.05, minimumCommandInterval)
            : 0.25
        self.minimumEmittedDelta = (minimumEmittedDelta.isFinite && minimumEmittedDelta > 0)
            ? minimumEmittedDelta
            : 0.0005
        self.maximumEvaluationStepSeconds = maximumEvaluationStepSeconds.isFinite
            ? max(self.minimumCommandInterval, maximumEvaluationStepSeconds)
            : 1.0
        self.targetRate = nil
        self.currentRate = 1.0
    }

    /// La vitesse courante est-elle au niveau de la consigne ? Utile au diagnostic
    /// et à l'affichage (« transition en cours » / « stabilisé »).
    public var isSettled: Bool {
        guard let targetRate else { return true }
        return abs(targetRate - currentRate) <= minimumEmittedDelta
    }

    /// Écart restant à parcourir, en points de pourcentage (diagnostic).
    public var pendingAdjustmentPercent: Double {
        guard let targetRate else { return 0 }
        return (targetRate - currentRate) * 100
    }

    /// Nouvelle session : tempo original, horloges remises à zéro.
    public mutating func reset() {
        targetRate = nil
        currentRate = 1.0
        lastEvaluationTimestamp = nil
        lastEmittedRate = nil
        lastEmittedTimestamp = nil
    }

    /// Fixe la consigne, bornée par la politique. `nil` = maintenir la vitesse
    /// courante (aucune consigne inventée).
    public mutating func acceptTarget(_ rate: Double?) {
        targetRate = rate.map { policy.limitedRate($0) }
    }

    /// Fait avancer la rampe et retourne la commande à émettre, s'il y en a une.
    ///
    /// - La première évaluation émet immédiatement l'état initial (tempo original).
    /// - Ensuite, deux conditions sont requises : intervalle minimal écoulé **et**
    ///   changement perceptible. Sinon la méthode retourne `nil` et le moteur audio
    ///   n'est pas touché.
    public mutating func command(at now: Date) -> Command? {
        // Première évaluation : aucun temps ne s'est écoulé, donc aucun pas de
        // rampe. Sans cette règle, l'état initial transmis au moteur audio serait
        // déjà décalé d'un point de pourcentage — une marche audible au démarrage.
        let elapsed = lastEvaluationTimestamp.map { max(0, now.timeIntervalSince($0)) }
        let step = elapsed.map { min($0, maximumEvaluationStepSeconds) } ?? 0
        lastEvaluationTimestamp = now

        if let targetRate {
            let budget = maximumSlewPerSecond * step
            let delta = targetRate - currentRate
            let limited = min(max(delta, -budget), budget)
            currentRate = policy.limitedRate(currentRate + limited)
        }
        // Sans consigne : la vitesse courante est maintenue telle quelle (HOLD).

        if let lastEmittedTimestamp,
           now.timeIntervalSince(lastEmittedTimestamp) < minimumCommandInterval {
            return nil
        }

        let isInitial = lastEmittedRate == nil
        guard isInitial || abs(currentRate - (lastEmittedRate ?? currentRate)) >= minimumEmittedDelta else {
            return nil
        }

        lastEmittedRate = currentRate
        lastEmittedTimestamp = now
        return Command(rate: currentRate, timestamp: now, isInitial: isInitial)
    }
}
