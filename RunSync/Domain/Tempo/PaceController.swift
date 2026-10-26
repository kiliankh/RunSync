import Foundation

/// Configuration du mode Pace (§05).
///
/// Point clé : la cadence cible est **déclarée séparément**. L'allure seule ne
/// détermine pas la cadence (elle dépend de la longueur de foulée) ; tant
/// qu'aucune calibration personnelle n'existe, l'UI propose le choix explicite
/// 160/170/180 ou un curseur, et ne devine rien.
public struct PaceControllerConfiguration: Sendable, Equatable {
    /// Cadence cible déclarée par l'utilisateur (SPM).
    public var targetCadenceSPM: Double
    /// Allure cible en secondes par kilomètre, pour l'affichage de l'écart.
    public var targetPaceSecondsPerKilometer: Double?
    /// Signaux sonores doux : désactivés par défaut (§05).
    public var audibleGuidanceEnabled: Bool
    /// Dérivée maximale du rate par seconde.
    public var rateSlewPerSecond: Double

    public init(
        targetCadenceSPM: Double,
        targetPaceSecondsPerKilometer: Double? = nil,
        audibleGuidanceEnabled: Bool = false,
        rateSlewPerSecond: Double = 0.01
    ) {
        self.targetCadenceSPM = targetCadenceSPM
        self.targetPaceSecondsPerKilometer = targetPaceSecondsPerKilometer
        self.audibleGuidanceEnabled = audibleGuidanceEnabled
        self.rateSlewPerSecond = rateSlewPerSecond.isFinite ? max(0, rateSlewPerSecond) : 0.01
    }

    /// Cible exploitable ? Une cible hors plage plausible n'est pas une cible :
    /// le contrôleur n'invente alors aucune consigne.
    public var hasUsableTargetCadence: Bool {
        CadenceUnits.isPlausibleSPM(targetCadenceSPM)
    }
}

/// Décision de sortie du mode Pace : le tempo visé **et** l'écart réel à la cible,
/// présentés séparément (FR-011).
public struct PaceDecision: Sendable, Equatable {
    public let timestamp: Date
    public let tempo: TempoDecision
    public let targetCadenceSPM: Double
    public let observedCadenceSPM: Double?
    /// `cadence observée - cadence cible` : négatif = l'utilisateur est en dessous.
    public let cadenceDeltaSPM: Double?
    public let observedPaceSecondsPerKilometer: Double?
    /// `allure observée - allure cible`, dans le même sens.
    public let paceDeltaSecondsPerKilometer: Double?
    public let recommendedTrackID: UUID?
    public let audibleGuidanceEnabled: Bool
}

/// Contrôleur du mode Pace (RS-024).
///
/// Le tempo musical reste calé sur la cadence cible déclarée : l'application
/// **n'accélère pas** la musique quand l'utilisateur ralentit, sinon le guidage
/// serait contradictoire (§05 exemple E).
public struct PaceController: Sendable {
    public let policy: TempoMatchingPolicy
    public var configuration: PaceControllerConfiguration

    private let matcher: TempoMatcher
    private var appliedRate: Double = 1.0
    private var lastUpdateTimestamp: Date?

    public init(
        policy: TempoMatchingPolicy = .standard,
        configuration: PaceControllerConfiguration
    ) {
        self.policy = policy
        self.configuration = configuration
        self.matcher = TempoMatcher(policy: policy)
    }

    public var currentAppliedRate: Double { appliedRate }

    public mutating func start(at date: Date) {
        reset()
        lastUpdateTimestamp = date
    }

    public mutating func reset() {
        appliedRate = 1.0
        lastUpdateTimestamp = nil
    }

    public mutating func update(
        observedCadence: CadenceAssessment,
        pace: PaceSample? = nil,
        track: TrackDescriptor?,
        candidates: [TrackDescriptor] = [],
        now: Date
    ) -> PaceDecision {
        let dt = lastUpdateTimestamp.map { max(0, now.timeIntervalSince($0)) } ?? 0
        lastUpdateTimestamp = now
        let slewBudget = configuration.rateSlewPerSecond * dt

        let observedSPM: Double? = observedCadence.quality == .unavailable
            ? nil
            : observedCadence.setpointSPM
        let observedPace = pace?.secondsPerKilometer
        let cadenceDelta = observedSPM.map { $0 - configuration.targetCadenceSPM }
        let paceDelta: Double? = {
            guard let observedPace, let target = configuration.targetPaceSecondsPerKilometer else { return nil }
            return observedPace - target
        }()

        guard configuration.hasUsableTargetCadence else {
            appliedRate = slew(appliedRate, toward: 1.0, budget: slewBudget)
            let decision = TempoDecision(
                trackID: track?.id,
                targetTrackBPM: nil,
                requiredRate: nil,
                appliedRate: appliedRate,
                stepsPerBeat: nil,
                isClamped: false,
                quality: .unavailable,
                reason: .cadenceUnavailableHolding
            )
            return PaceDecision(
                timestamp: now,
                tempo: decision,
                targetCadenceSPM: configuration.targetCadenceSPM,
                observedCadenceSPM: observedSPM,
                cadenceDeltaSPM: cadenceDelta,
                observedPaceSecondsPerKilometer: observedPace,
                paceDeltaSecondsPerKilometer: paceDelta,
                recommendedTrackID: nil,
                audibleGuidanceEnabled: configuration.audibleGuidanceEnabled
            )
        }

        // La cible musicale est la cadence cible déclarée, jamais la cadence observée.
        let targetCadence = configuration.targetCadenceSPM
        let evaluation = track.map {
            matcher.evaluate(
                track: $0,
                targetCadenceSPM: targetCadence,
                recentlyPlayedTrackIDs: []
            )
        }
        let alternatives = candidates.filter { $0.id != track?.id }

        var reason: TempoDecisionReason = .paceTargetMaintained
        var targetRate = appliedRate
        var isClamped = false

        if let evaluation, let raw = evaluation.requiredRateRaw {
            targetRate = policy.limitedRate(raw)
            isClamped = !policy.isRateWithinBounds(raw)
            if isClamped { reason = .clampedToMaximumAdjustment }
        } else {
            reason = evaluation?.rejection?.decisionReason ?? .bpmUnknown
            targetRate = appliedRate
        }

        let recommendation = (isClamped || evaluation?.rejection != nil)
            ? matcher.bestMatch(
                tracks: alternatives,
                targetCadenceSPM: targetCadence,
                recentlyPlayedTrackIDs: []
            )?.trackID
            : nil

        appliedRate = slew(appliedRate, toward: targetRate, budget: slewBudget)

        let decision = TempoDecision(
            trackID: track?.id,
            targetTrackBPM: evaluation?.targetTrackBPM
                ?? policy.targetTrackBPM(targetCadenceSPM: targetCadence, stepsPerBeat: 1),
            requiredRate: evaluation?.requiredRateRaw,
            appliedRate: appliedRate,
            stepsPerBeat: evaluation?.stepsPerBeat,
            isClamped: isClamped,
            quality: .good,
            reason: reason
        )
        return PaceDecision(
            timestamp: now,
            tempo: decision,
            targetCadenceSPM: targetCadence,
            observedCadenceSPM: observedSPM,
            cadenceDeltaSPM: cadenceDelta,
            observedPaceSecondsPerKilometer: observedPace,
            paceDeltaSecondsPerKilometer: paceDelta,
            recommendedTrackID: recommendation,
            audibleGuidanceEnabled: configuration.audibleGuidanceEnabled
        )
    }

    private func slew(_ current: Double, toward target: Double, budget: Double) -> Double {
        let delta = target - current
        let limitedDelta = min(max(delta, -budget), budget)
        return policy.limitedRate(current + limitedDelta)
    }
}
