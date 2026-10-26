import Foundation

/// Source de cadence (Core Motion en production, simulateur en démo/tests).
///
/// Le Domain ne dépend pas de CoreMotion : l'adaptateur `CoreMotionCadenceSource`
/// (RS-010) vit dans Infrastructure et convertit `currentCadence` (pas/seconde)
/// en SPM via `CadenceUnits`. Un échantillon sans valeur doit produire
/// `CadenceSample(stepsPerMinute: nil, quality: .unavailable)`, jamais `0`.
public protocol CadenceSource: Sendable {
    func samples() -> AsyncThrowingStream<CadenceSample, Error>
}
