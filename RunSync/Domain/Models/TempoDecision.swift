import Foundation

/// Raison d'une décision tempo, exposée telle quelle à l'utilisateur (NFR-007 :
/// l'application indique toujours si le tempo est ajusté, clampé, maintenu ou indisponible).
///
/// Écart documenté par rapport à l'esquisse §07 du cahier des charges : la spec
/// proposait `reason: String`. Un enum typé est utilisé à la place pour être
/// testable et pour éviter les chaînes libres incohérentes ; la traduction
/// utilisateur est fournie par `displayMessage` (Docs/ARCHITECTURE.md).
public enum TempoDecisionReason: String, Codable, Sendable, CaseIterable, Equatable {
    /// Le tempo suit la cadence mesurée filtrée (mode Follow).
    case followingCadence
    /// Le tempo suit la cadence cible déclarée, indépendamment de la cadence observée (mode Pace).
    case paceTargetMaintained
    /// Le ratio requis dépasse la limite d'ajustement et a été borné (FR-009).
    case clampedToMaximumAdjustment
    /// Cadence indisponible : le rate courant est maintenu temporairement (§05).
    case cadenceUnavailableHolding
    /// Cadence indisponible depuis trop longtemps : retour doux vers le tempo original.
    case returningToNeutral
    /// Le morceau n'a pas de BPM exploitable : aucune synchronisation prétendue.
    case bpmUnknown
    /// Le fournisseur n'autorise pas l'adaptation du tempo (garde de conformité, §02).
    case tempoAdjustmentNotPermitted
    /// Le fichier n'est plus disponible dans la sandbox.
    case trackFileUnavailable
    /// Aucun morceau du catalogue n'est admissible : un autre morceau est suggéré.
    case noAdmissibleTrack

    public var displayMessage: String {
        switch self {
        case .followingCadence:
            return "Tempo synchronisé sur ta cadence."
        case .paceTargetMaintained:
            return "Tempo calé sur ta cadence cible."
        case .clampedToMaximumAdjustment:
            return "Tempo limité au maximum d'ajustement autorisé."
        case .cadenceUnavailableHolding:
            return "Cadence indisponible : tempo maintenu temporairement."
        case .returningToNeutral:
            return "Cadence indisponible : retour progressif au tempo original."
        case .bpmUnknown:
            return "BPM inconnu : ce morceau ne peut pas être synchronisé."
        case .tempoAdjustmentNotPermitted:
            return "Cette source n'autorise pas l'adaptation du tempo."
        case .trackFileUnavailable:
            return "Fichier introuvable : morceau non jouable."
        case .noAdmissibleTrack:
            return "Aucun morceau ne correspond : un autre morceau est proposé."
        }
    }

    /// Vrai si le tempo est réellement piloté par la cadence mesurée ou cible.
    public var isActivelySynchronized: Bool {
        self == .followingCadence || self == .paceTargetMaintained
    }
}

/// Décision tempo calculée par les contrôleurs Follow/Pace, indépendante de tout
/// framework audio (§07).
public struct TempoDecision: Sendable, Equatable {
    /// Morceau concerné par la décision, si connu.
    public let trackID: UUID?
    /// BPM cible visé pour le morceau : `targetCadenceSPM / stepsPerBeat`.
    public let targetTrackBPM: Double?
    /// Ratio brut requis (`targetTrackBPM / nominalBPM`), **avant** bornage.
    /// `nil` quand aucune synchronisation n'est calculable.
    public let requiredRate: Double?
    /// Ratio effectivement appliqué après bornage.
    public let appliedRate: Double
    /// Nombre de pas par battement retenu (1 = 1:1, 2 = 2:1).
    public let stepsPerBeat: Int?
    /// Vrai si le bornage a modifié le ratio requis.
    public let isClamped: Bool
    public let quality: DataQuality
    public let reason: TempoDecisionReason

    public init(
        trackID: UUID?,
        targetTrackBPM: Double?,
        requiredRate: Double?,
        appliedRate: Double,
        stepsPerBeat: Int?,
        isClamped: Bool,
        quality: DataQuality,
        reason: TempoDecisionReason
    ) {
        self.trackID = trackID
        self.targetTrackBPM = targetTrackBPM
        self.requiredRate = requiredRate
        self.appliedRate = appliedRate
        self.stepsPerBeat = stepsPerBeat
        self.isClamped = isClamped
        self.quality = quality
        self.reason = reason
    }

    /// Décision neutre : tempo original, aucune synchronisation, aucune donnée inventée.
    public static func neutral(reason: TempoDecisionReason = .cadenceUnavailableHolding) -> TempoDecision {
        TempoDecision(
            trackID: nil,
            targetTrackBPM: nil,
            requiredRate: nil,
            appliedRate: 1.0,
            stepsPerBeat: nil,
            isClamped: false,
            quality: .unavailable,
            reason: reason
        )
    }

    /// Taux d'ajustement en pourcentage, pour l'affichage (§03 E05).
    public var appliedAdjustmentPercent: Double { (appliedRate - 1) * 100 }
}
