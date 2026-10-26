import Foundation

/// Temporisations du mode Follow (§05). Paramètres injectables pour les tests.
public struct FollowTimingConfiguration: Sendable, Equatable {
    /// Dérivée maximale du rate par seconde (≈ 1 point de %/s).
    public var rateSlewPerSecond: Double
    /// Durée pendant laquelle un écart soutenu prépare un changement de morceau.
    public var sustainedOutOfRangeSeconds: TimeInterval
    /// Durée de maintien du rate courant quand la cadence devient indisponible.
    public var cadenceLossHoldSeconds: TimeInterval
    /// Durée du retour doux vers le tempo original (1.0) après le maintien.
    public var returnToNeutralSeconds: TimeInterval

    public static let standard = FollowTimingConfiguration()

    public init(
        rateSlewPerSecond: Double = 0.01,
        sustainedOutOfRangeSeconds: TimeInterval = 15,
        cadenceLossHoldSeconds: TimeInterval = 5,
        returnToNeutralSeconds: TimeInterval = 10
    ) {
        self.rateSlewPerSecond = rateSlewPerSecond.isFinite ? max(0, rateSlewPerSecond) : 0.01
        self.sustainedOutOfRangeSeconds = sustainedOutOfRangeSeconds.isFinite
            ? max(0, sustainedOutOfRangeSeconds) : 15
        self.cadenceLossHoldSeconds = cadenceLossHoldSeconds.isFinite
            ? max(0, cadenceLossHoldSeconds) : 5
        self.returnToNeutralSeconds = returnToNeutralSeconds.isFinite
            ? max(0, returnToNeutralSeconds) : 10
    }
}

/// Décision de sortie du mode Follow.
public struct FollowDecision: Sendable, Equatable {
    public let timestamp: Date
    public let tempo: TempoDecision
    /// Cadence filtrée retenue comme cible, `nil` si indisponible.
    public let cadenceSetpointSPM: Double?
    /// Morceau suggéré pour remplacer le morceau courant (jamais une coupure instantanée).
    public let recommendedTrackID: UUID?
    public let isCadenceUnavailable: Bool
}

/// Contrôleur du mode Follow (RS-023).
///
/// Comportement (§05) :
/// - la cible est la cadence **filtrée** (`CadenceAssessment.setpointSPM`) ;
/// - le ratio requis est borné à ±`maxAdjustment` ;
/// - un écart soutenu (15 s par défaut) **prépare** un passage à un autre morceau,
///   il ne coupe jamais le titre instantanément ;
/// - cadence indisponible : maintien du rate courant (5 s) puis retour doux à 1.0
///   (10 s), sans jamais fabriquer de cadence.
public struct FollowController: Sendable {
    public let policy: TempoMatchingPolicy
    public let timing: FollowTimingConfiguration
    /// Morceaux récemment joués, utilisés par la pénalité de changement fréquent.
    public var recentlyPlayedTrackIDs: [UUID]

    private let matcher: TempoMatcher
    private var appliedRate: Double = 1.0
    private var lastUpdateTimestamp: Date?
    private var cadenceLossStartedAt: Date?
    private var neutralReturnStartRate: Double?
    private var outOfRangeSince: Date?
    private var lastStepsPerBeat: Int?
    private var lastRecommendation: UUID?

    public init(
        policy: TempoMatchingPolicy = .standard,
        timing: FollowTimingConfiguration = .standard,
        recentlyPlayedTrackIDs: [UUID] = []
    ) {
        self.policy = policy
        self.timing = timing
        self.recentlyPlayedTrackIDs = recentlyPlayedTrackIDs
        self.matcher = TempoMatcher(policy: policy)
    }

    /// Rate actuellement appliqué (diagnostic et UI).
    public var currentAppliedRate: Double { appliedRate }

    /// Démarre une session : tempo original, horloge initialisée.
    public mutating func start(at date: Date) {
        reset()
        lastUpdateTimestamp = date
    }

    public mutating func reset() {
        appliedRate = 1.0
        lastUpdateTimestamp = nil
        cadenceLossStartedAt = nil
        neutralReturnStartRate = nil
        outOfRangeSince = nil
        lastStepsPerBeat = nil
        lastRecommendation = nil
    }

    public mutating func update(
        cadence: CadenceAssessment,
        track: TrackDescriptor?,
        candidates: [TrackDescriptor] = [],
        now: Date
    ) -> FollowDecision {
        let dt = lastUpdateTimestamp.map { max(0, now.timeIntervalSince($0)) } ?? 0
        lastUpdateTimestamp = now
        let slewBudget = timing.rateSlewPerSecond * dt

        guard cadence.quality != .unavailable, let targetCadence = cadence.setpointSPM else {
            return handleUnavailableCadence(track: track, now: now)
        }

        cadenceLossStartedAt = nil
        neutralReturnStartRate = nil

        guard let currentTrack = track else {
            let best = matcher.bestMatch(
                tracks: candidates,
                targetCadenceSPM: targetCadence,
                recentlyPlayedTrackIDs: recentlyPlayedTrackIDs
            )
            lastRecommendation = best?.trackID
            appliedRate = slew(appliedRate, toward: 1.0, budget: slewBudget)
            let decision = TempoDecision(
                trackID: nil,
                targetTrackBPM: nil,
                requiredRate: nil,
                appliedRate: appliedRate,
                stepsPerBeat: nil,
                isClamped: false,
                quality: .degraded,
                reason: .bpmUnknown
            )
            return FollowDecision(
                timestamp: now,
                tempo: decision,
                cadenceSetpointSPM: targetCadence,
                recommendedTrackID: best?.trackID,
                isCadenceUnavailable: false
            )
        }

        let evaluation = matcher.evaluate(
            track: currentTrack,
            targetCadenceSPM: targetCadence,
            recentlyPlayedTrackIDs: recentlyPlayedTrackIDs
        )
        let alternatives = candidates.filter { $0.id != currentTrack.id }

        var reason: TempoDecisionReason
        var targetRate = appliedRate
        var recommendation: UUID?
        var requiredRate = evaluation.requiredRateRaw
        var isClamped = false

        if let raw = evaluation.requiredRateRaw {
            targetRate = policy.limitedRate(raw)
            isClamped = !policy.isRateWithinBounds(raw)
            if isClamped {
                reason = .clampedToMaximumAdjustment
                if outOfRangeSince == nil { outOfRangeSince = now }
                if let since = outOfRangeSince,
                   now.timeIntervalSince(since) >= timing.sustainedOutOfRangeSeconds {
                    recommendation = matcher.bestMatch(
                        tracks: alternatives,
                        targetCadenceSPM: targetCadence,
                        recentlyPlayedTrackIDs: recentlyPlayedTrackIDs
                    )?.trackID
                    if recommendation != nil { reason = .noAdmissibleTrack }
                }
            } else {
                reason = .followingCadence
                outOfRangeSince = nil
            }
        } else {
            // Morceau non synchronisable (BPM inconnu, source non autorisée, fichier absent).
            reason = evaluation.rejection?.decisionReason ?? .bpmUnknown
            requiredRate = nil
            targetRate = appliedRate
            outOfRangeSince = nil
            recommendation = matcher.bestMatch(
                tracks: alternatives,
                targetCadenceSPM: targetCadence,
                recentlyPlayedTrackIDs: recentlyPlayedTrackIDs
            )?.trackID
        }

        lastStepsPerBeat = evaluation.stepsPerBeat
        lastRecommendation = recommendation
        appliedRate = slew(appliedRate, toward: targetRate, budget: slewBudget)

        let decision = TempoDecision(
            trackID: currentTrack.id,
            targetTrackBPM: evaluation.targetTrackBPM,
            requiredRate: requiredRate,
            appliedRate: appliedRate,
            stepsPerBeat: evaluation.stepsPerBeat,
            isClamped: isClamped,
            quality: cadence.quality,
            reason: reason
        )
        return FollowDecision(
            timestamp: now,
            tempo: decision,
            cadenceSetpointSPM: targetCadence,
            recommendedTrackID: recommendation,
            isCadenceUnavailable: false
        )
    }

    // MARK: - Interne

    private mutating func handleUnavailableCadence(
        track: TrackDescriptor?,
        now: Date
    ) -> FollowDecision {
        if cadenceLossStartedAt == nil {
            cadenceLossStartedAt = now
            neutralReturnStartRate = nil
            outOfRangeSince = nil
        }
        let lossElapsed = now.timeIntervalSince(cadenceLossStartedAt ?? now)
        let isHolding = lossElapsed <= timing.cadenceLossHoldSeconds

        if isHolding {
            neutralReturnStartRate = nil
        } else {
            if neutralReturnStartRate == nil { neutralReturnStartRate = appliedRate }
            let startRate = neutralReturnStartRate ?? appliedRate
            let progress: Double
            if timing.returnToNeutralSeconds > 0 {
                progress = min(1, (lossElapsed - timing.cadenceLossHoldSeconds) / timing.returnToNeutralSeconds)
            } else {
                progress = 1
            }
            appliedRate = policy.limitedRate(startRate + (1.0 - startRate) * progress)
        }

        let decision = TempoDecision(
            trackID: track?.id,
            targetTrackBPM: nil,
            requiredRate: nil,
            appliedRate: appliedRate,
            stepsPerBeat: lastStepsPerBeat,
            isClamped: false,
            quality: .unavailable,
            reason: isHolding ? .cadenceUnavailableHolding : .returningToNeutral
        )
        return FollowDecision(
            timestamp: now,
            tempo: decision,
            cadenceSetpointSPM: nil,
            recommendedTrackID: lastRecommendation,
            isCadenceUnavailable: true
        )
    }

    private func slew(_ current: Double, toward target: Double, budget: Double) -> Double {
        let delta = target - current
        let limitedDelta = min(max(delta, -budget), budget)
        return policy.limitedRate(current + limitedDelta)
    }
}
