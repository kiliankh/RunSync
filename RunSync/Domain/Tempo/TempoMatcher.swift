import Foundation

/// Sélection du meilleur morceau / ratio pour une cadence cible (§05).
///
/// Deux responsabilités :
/// 1. évaluer un morceau face à une cadence cible (ratios 1:1 et 2:1, bornage) ;
/// 2. classer les morceaux candidats par coût de sélection.
///
/// Le « score » de la spec est implémenté comme un **coût** (plus petit = meilleur) :
/// les termes de pénalité s'additionnent, ce qui correspond à l'intention du
/// cahier des charges. Détail des pondérations dans `TempoMatcher.Weights`.
public struct TempoMatcher: Sendable, Equatable {

    /// Pondérations du choix de morceau (première version, ajustables après mesure, §05).
    public enum Weights {
        /// Écart du ratio requis, normalisé par la limite d'ajustement.
        public static let requiredRateDeviation: Double = 0.65
        /// Pénalité de changement de morceau trop fréquent.
        public static let frequentTrackChange: Double = 0.20
        /// Préférence utilisateur / énergie, **quand elle est disponible et licite**.
        public static let userPreference: Double = 0.15
        /// Valeur retenue tant qu'aucune préférence licite n'existe : on n'invente
        /// aucune caractéristique musicale (§05).
        public static let userPreferenceUnavailable: Double = 0.0
    }

    public let policy: TempoMatchingPolicy

    public init(policy: TempoMatchingPolicy = .standard) {
        self.policy = policy
    }

    /// Évalue un morceau face à une cadence cible.
    ///
    /// Les rejets sont explicites et affichables : BPM inconnu, source non
    /// autorisée, fichier absent, droits non attestés. Un morceau rejeté n'est
    /// jamais présenté comme synchronisable (§02, FR-007).
    public func evaluate(
        track: TrackDescriptor,
        targetCadenceSPM: Double?,
        provider: MusicProviderCapabilities? = nil,
        recentlyPlayedTrackIDs: [UUID] = []
    ) -> TrackEvaluation {
        guard let cadence = targetCadenceSPM, cadence.isFinite, cadence > 0 else {
            return rejection(.targetCadenceUnavailable, track: track)
        }
        guard track.canAlterTempo else {
            // La cause d'un refus doit être exacte : si la **source** autorise
            // l'adaptation mais que ce morceau ne l'autorise pas, le problème est le
            // droit d'adaptation du fichier, pas la source. Sinon l'utilisateur lirait
            // un message trompeur sur un fichier local non attesté (§02).
            let resolvedProvider = provider ?? ProviderCatalog.provider(id: track.providerID)
            if resolvedProvider?.isTempoAdjustmentPermitted == true {
                return rejection(.adaptationRightsNotAttested, track: track)
            }
            return rejection(.tempoAdjustmentNotPermitted(providerID: track.providerID), track: track)
        }
        guard track.isFileAvailable else {
            return rejection(.fileUnavailable, track: track)
        }
        guard track.isAdaptationRightsAttested else {
            return rejection(.adaptationRightsNotAttested, track: track)
        }
        guard let nominalBPM = track.nominalBPM else {
            return rejection(.bpmUnknown, track: track)
        }
        guard nominalBPM.isFinite, nominalBPM > 0 else {
            return rejection(.bpmInvalid(nominalBPM), track: track)
        }

        // Parmi les ratios validés, retenir celui dont le ratio requis est le plus
        // proche de 1 : 170 SPM peut correspondre à 170 BPM (1:1) ou 85 BPM (2:1).
        var bestCandidate: (stepsPerBeat: Int, rate: Double, distance: Double)?
        for stepsPerBeat in policy.stepsPerBeatCandidates {
            guard let rate = policy.requiredRate(
                targetCadenceSPM: cadence,
                nominalBPM: nominalBPM,
                stepsPerBeat: stepsPerBeat
            ) else { continue }
            let distance = abs(log(rate))
            if bestCandidate == nil || distance < bestCandidate!.distance {
                bestCandidate = (stepsPerBeat, rate, distance)
            }
        }
        guard let candidate = bestCandidate else {
            return rejection(.bpmUnknown, track: track)
        }

        return TrackEvaluation(
            trackID: track.id,
            nominalBPM: nominalBPM,
            stepsPerBeat: candidate.stepsPerBeat,
            targetTrackBPM: policy.targetTrackBPM(
                targetCadenceSPM: cadence,
                stepsPerBeat: candidate.stepsPerBeat
            ),
            requiredRateRaw: candidate.rate,
            requiredRateLimited: policy.limitedRate(candidate.rate),
            isAdmissible: policy.isRateWithinBounds(candidate.rate),
            rejection: nil,
            selectionCost: selectionCost(
                requiredRate: candidate.rate,
                trackID: track.id,
                recentlyPlayedTrackIDs: recentlyPlayedTrackIDs
            )
        )
    }

    /// Classement : morceaux admissibles d'abord (coût croissant), puis les autres
    /// par distance croissante à 1.0, ce qui permet de suggérer « le moins mauvais »
    /// morceau quand aucun n'est admissible (§05 exemple C).
    public func ranked(
        tracks: [TrackDescriptor],
        targetCadenceSPM: Double?,
        provider: MusicProviderCapabilities? = nil,
        recentlyPlayedTrackIDs: [UUID] = []
    ) -> [TrackEvaluation] {
        let evaluations = tracks.map {
            evaluate(
                track: $0,
                targetCadenceSPM: targetCadenceSPM,
                provider: provider ?? ProviderCatalog.provider(id: $0.providerID),
                recentlyPlayedTrackIDs: recentlyPlayedTrackIDs
            )
        }
        let admissible = evaluations
            .filter { $0.isAdmissible }
            .sorted { ($0.selectionCost ?? .greatestFiniteMagnitude) < ($1.selectionCost ?? .greatestFiniteMagnitude) }
        let remaining = evaluations
            .filter { !$0.isAdmissible }
            .sorted { distanceFromUnity($0) < distanceFromUnity($1) }
        return admissible + remaining
    }

    /// Meilleur morceau admissible pour une cadence cible, s'il existe.
    public func bestMatch(
        tracks: [TrackDescriptor],
        targetCadenceSPM: Double?,
        provider: MusicProviderCapabilities? = nil,
        recentlyPlayedTrackIDs: [UUID] = []
    ) -> TrackEvaluation? {
        ranked(
            tracks: tracks,
            targetCadenceSPM: targetCadenceSPM,
            provider: provider,
            recentlyPlayedTrackIDs: recentlyPlayedTrackIDs
        ).first { $0.isAdmissible }
    }

    /// Coût de sélection (§05) :
    /// `0.65 * |log(rate)| normalisé + 0.20 * pénalité de changement + 0.15 * préférence`.
    public func selectionCost(
        requiredRate: Double,
        trackID: UUID,
        recentlyPlayedTrackIDs: [UUID]
    ) -> Double {
        let deviation = abs(log(requiredRate))
        let normalizer = log(1 + policy.maxAdjustment)
        let normalizedDeviation = normalizer > 0 ? min(1, deviation / normalizer) : 0
        let changePenalty = recentlyPlayedTrackIDs.contains(trackID) ? 1.0 : 0.0
        return Weights.requiredRateDeviation * normalizedDeviation
            + Weights.frequentTrackChange * changePenalty
            + Weights.userPreference * Weights.userPreferenceUnavailable
    }

    private func rejection(_ reason: TempoRejection, track: TrackDescriptor) -> TrackEvaluation {
        TrackEvaluation(
            trackID: track.id,
            nominalBPM: track.nominalBPM,
            stepsPerBeat: nil,
            targetTrackBPM: nil,
            requiredRateRaw: nil,
            requiredRateLimited: nil,
            isAdmissible: false,
            rejection: reason,
            selectionCost: nil
        )
    }

    private func distanceFromUnity(_ evaluation: TrackEvaluation) -> Double {
        guard let rate = evaluation.requiredRateRaw else { return .greatestFiniteMagnitude }
        return abs(log(rate))
    }
}
