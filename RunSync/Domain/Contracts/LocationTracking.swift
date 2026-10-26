import Foundation

/// Suivi de localisation / allure (RS-012, phase 2).
/// Aucune vitesse fictive quand le signal GPS est absent : `quality` et champs
/// optionnels le disent explicitement (FR-005).
public protocol LocationTracking: Sendable {
    func samples() -> AsyncThrowingStream<PaceSample, Error>
}
