import Foundation

/// Mode de course choisi par l'utilisateur (spec §03 E04, §05).
///
/// - `follow` : le tempo musical suit la cadence **mesurée**, dans les limites
///   d'ajustement autorisées.
/// - `pace` : le tempo musical suit une cadence **cible déclarée**, l'écart réel
///   à la cible étant affiché séparément (FR-011).
public enum RunMode: String, Codable, Sendable, CaseIterable, Identifiable, Equatable {
    case follow
    case pace

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .follow: return "Follow"
        case .pace: return "Pace"
        }
    }

    public var shortExplanation: String {
        switch self {
        case .follow:
            return "La musique suit ta cadence réelle, dans la limite d'ajustement choisie."
        case .pace:
            return "La musique suit une cadence cible que tu choisis, pour te guider."
        }
    }

    /// En mode Pace, la cadence cible est déclarée par l'utilisateur. En mode
    /// Follow, elle est mesurée. L'allure seule ne détermine pas la cadence (§05).
    public var usesUserDeclaredTargetCadence: Bool { self == .pace }
}
