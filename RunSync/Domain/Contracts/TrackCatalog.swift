import Foundation

/// Catalogue de morceaux (§07). L'adaptateur local est le seul utilisé au MVP ;
/// les fournisseurs tiers restent des stubs désactivés par la garde de conformité (§02).
public protocol TrackCatalog: Sendable {
    func tracks() async throws -> [TrackDescriptor]

    /// Import d'un fichier fourni par l'utilisateur. Doit respecter les
    /// security-scoped URLs, copier dans la sandbox et remonter une erreur typée
    /// pour un format incompatible ou un accès refusé (FR-006, RS-020).
    func importLocalFile(from url: URL) async throws -> TrackDescriptor
}

/// Évaluation d'un morceau vis-à-vis d'une cadence cible (§05).
public struct TrackEvaluation: Sendable, Equatable {
    public let trackID: UUID
    public let nominalBPM: Double?
    /// Ratio musical retenu (le plus proche de 1 parmi les ratios validés).
    public let stepsPerBeat: Int?
    /// `targetCadenceSPM / stepsPerBeat`.
    public let targetTrackBPM: Double?
    /// Ratio brut requis, avant bornage. `nil` si non calculable.
    public let requiredRateRaw: Double?
    /// Ratio borné dans `[1 - maxAdjustment, 1 + maxAdjustment]`. `nil` si non calculable.
    public let requiredRateLimited: Double?
    /// Admissible : ratio requis dans les limites d'ajustement.
    public let isAdmissible: Bool
    /// Cause de rejet, si le morceau n'est pas synchronisable.
    public let rejection: TempoRejection?
    /// Coût de sélection (plus petit = meilleur). Voir `TempoMatcher`.
    public let selectionCost: Double?

    public init(
        trackID: UUID,
        nominalBPM: Double?,
        stepsPerBeat: Int?,
        targetTrackBPM: Double?,
        requiredRateRaw: Double?,
        requiredRateLimited: Double?,
        isAdmissible: Bool,
        rejection: TempoRejection?,
        selectionCost: Double?
    ) {
        self.trackID = trackID
        self.nominalBPM = nominalBPM
        self.stepsPerBeat = stepsPerBeat
        self.targetTrackBPM = targetTrackBPM
        self.requiredRateRaw = requiredRateRaw
        self.requiredRateLimited = requiredRateLimited
        self.isAdmissible = isAdmissible
        self.rejection = rejection
        self.selectionCost = selectionCost
    }
}

/// Motifs pour lesquels un morceau n'est pas synchronisable. Chaque motif est
/// affichable : aucune option trompeuse dans l'interface (§02, FR-007).
public enum TempoRejection: Equatable, Sendable {
    case targetCadenceUnavailable
    case bpmUnknown
    case bpmInvalid(Double)
    case tempoAdjustmentNotPermitted(providerID: String)
    case fileUnavailable
    case adaptationRightsNotAttested

    public var displayMessage: String {
        switch self {
        case .targetCadenceUnavailable:
            return "Cadence cible inconnue : aucune synchronisation calculée."
        case .bpmUnknown:
            return "BPM inconnu."
        case let .bpmInvalid(value):
            return "BPM invalide (\(value))."
        case let .tempoAdjustmentNotPermitted(providerID):
            return "Source « \(providerID) » : adaptation du tempo non autorisée."
        case .fileUnavailable:
            return "Fichier introuvable."
        case .adaptationRightsNotAttested:
            return "Droit d'adaptation non attesté pour ce fichier."
        }
    }

    /// Raison correspondante pour une décision tempo.
    public var decisionReason: TempoDecisionReason {
        switch self {
        case .targetCadenceUnavailable:
            return .cadenceUnavailableHolding
        case .bpmUnknown, .bpmInvalid:
            return .bpmUnknown
        case .tempoAdjustmentNotPermitted, .adaptationRightsNotAttested:
            return .tempoAdjustmentNotPermitted
        case .fileUnavailable:
            return .trackFileUnavailable
        }
    }
}
