import Foundation

/// Qualité d'une donnée ou d'une décision (spec §07).
///
/// La qualité est toujours explicite : l'application ne doit jamais présenter une
/// valeur incertaine comme fiable (FR-003, NFR-007).
public enum DataQuality: String, Codable, Sendable, CaseIterable, Equatable {
    /// Donnée utilisable pour piloter une décision.
    case good
    /// Donnée exploitable mais dégradée : on maintient la dernière consigne
    /// connue plutôt que d'appliquer une correction arbitraire (§05).
    case degraded
    /// Aucune donnée exploitable : aucune valeur ne doit être inventée.
    case unavailable

    public var displayName: String {
        switch self {
        case .good: return "Bonne"
        case .degraded: return "Dégradée"
        case .unavailable: return "Indisponible"
        }
    }

    /// Seule une qualité `good` autorise le pilotage actif du tempo (FR-010).
    public var isUsableForControl: Bool { self == .good }
}
