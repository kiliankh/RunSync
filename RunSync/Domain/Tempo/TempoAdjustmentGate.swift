import Foundation

/// Garde d'ajustement du tempo (§02, §07, RS-040).
///
/// Un lecteur ne reçoit jamais le droit d'altérer un flux parce qu'il sait lire
/// un titre. Cette garde est le point d'entrée unique de toute demande de rate :
/// elle vérifie la capacité technique **et** le statut de conformité du
/// fournisseur, l'existence du fichier, l'attestation de droits et le BPM, puis
/// borne la valeur demandée.
public struct TempoAdjustmentGate: Sendable, Equatable {
    public let policy: TempoMatchingPolicy

    public init(policy: TempoMatchingPolicy = .standard) {
        self.policy = policy
    }

    /// La source autorise-t-elle une adaptation du tempo pour ce morceau ?
    public func isPermitted(
        track: TrackDescriptor,
        provider: MusicProviderCapabilities
    ) -> Bool {
        provider.isTempoAdjustmentPermitted
            && track.canAlterTempo
            && track.isFileAvailable
            && track.isAdaptationRightsAttested
            && track.hasUsableNominalBPM
    }

    /// Borne une valeur sans vérification de droits (usage interne après évaluation).
    public func limitedRate(_ requestedRate: Double?) -> Double {
        policy.limitedRate(requestedRate)
    }

    /// Valide une demande de rate puis la borne. Toute demande non autorisée lève
    /// une erreur typée : l'application n'ajuste jamais un flux qu'elle n'a pas le
    /// droit de traiter (T013).
    public func validatedRate(
        requestedRate: Double,
        track: TrackDescriptor,
        provider: MusicProviderCapabilities
    ) throws -> Double {
        guard provider.isTempoAdjustmentPermitted, track.canAlterTempo else {
            throw TempoAdjustmentError.providerNotPermitted(providerID: provider.id)
        }
        guard track.isFileAvailable else {
            throw TempoAdjustmentError.trackFileUnavailable(trackID: track.id)
        }
        guard track.isAdaptationRightsAttested else {
            throw TempoAdjustmentError.adaptationRightsNotAttested(trackID: track.id)
        }
        guard track.hasUsableNominalBPM else {
            throw TempoAdjustmentError.nominalBPMUnavailable(trackID: track.id)
        }
        guard requestedRate.isFinite, requestedRate > 0 else {
            throw TempoAdjustmentError.invalidRequestedRate(requestedRate)
        }
        return policy.limitedRate(requestedRate)
    }
}
