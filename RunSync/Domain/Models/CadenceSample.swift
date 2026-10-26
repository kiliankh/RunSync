import Foundation

/// Échantillon de cadence horodaté (FR-003, §07).
///
/// `stepsPerMinute == nil` signifie « capteur sans valeur disponible ». Cette
/// valeur ne doit **jamais** être remplacée par `0` ni par une cadence déduite de
/// l'allure : le contrôleur bascule alors en état indisponible (§05 exemple D).
public struct CadenceSample: Sendable, Equatable {
    public let timestamp: Date
    public let stepsPerMinute: Double?
    public let quality: DataQuality
    public let sourceIdentifier: String

    public init(
        timestamp: Date,
        stepsPerMinute: Double?,
        quality: DataQuality,
        sourceIdentifier: String
    ) {
        self.timestamp = timestamp
        self.stepsPerMinute = stepsPerMinute
        self.quality = quality
        self.sourceIdentifier = sourceIdentifier
    }

    /// Le capteur déclare explicitement ne pas avoir de valeur exploitable.
    public static func sensorUnavailable(
        timestamp: Date,
        sourceIdentifier: String
    ) -> CadenceSample {
        CadenceSample(
            timestamp: timestamp,
            stepsPerMinute: nil,
            quality: .unavailable,
            sourceIdentifier: sourceIdentifier
        )
    }

    /// Conversion depuis CoreMotion (pas/seconde -> SPM) à la frontière de
    /// l'adaptateur. T001 : 2.833333 pas/s => ~170 SPM. Une valeur non exploitable
    /// produit un échantillon `unavailable`, jamais un `0`.
    public static func fromStepsPerSecond(
        _ stepsPerSecond: Double?,
        timestamp: Date,
        sourceIdentifier: String
    ) -> CadenceSample {
        guard let spm = CadenceUnits.stepsPerSecondToSPM(stepsPerSecond) else {
            return .sensorUnavailable(timestamp: timestamp, sourceIdentifier: sourceIdentifier)
        }
        return CadenceSample(
            timestamp: timestamp,
            stepsPerMinute: spm,
            quality: .good,
            sourceIdentifier: sourceIdentifier
        )
    }
}
