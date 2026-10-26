import Foundation

/// Paramètres de synchronisation, validés à la construction (FR-009, §05).
///
/// `maxAdjustment` est la limite d'ajustement du tempo : ±5 % par défaut, ±3 %
/// en option « prudente ». Seuls les ratios 1:1 et 2:1 sont validés par la spec :
/// en ajouter d'autres exige une validation UX et fait échouer la construction.
public struct TempoMatchingPolicy: Sendable, Equatable {
    /// Ratios validés par le cahier des charges §05 (n pas par battement).
    public static let supportedStepsPerBeat: Set<Int> = [1, 2]
    public static let minimumSupportedAdjustment: Double = 0.005
    public static let maximumSupportedAdjustment: Double = 0.25

    /// ±5 % : valeur par défaut du produit (§03 E07).
    public static let standard = TempoMatchingPolicy(
        uncheckedMaxAdjustment: 0.05,
        stepsPerBeatCandidates: [1, 2]
    )

    /// ±3 % : option prudente proposée dans les réglages (§03 E07).
    public static let conservative = TempoMatchingPolicy(
        uncheckedMaxAdjustment: 0.03,
        stepsPerBeatCandidates: [1, 2]
    )

    public let maxAdjustment: Double
    public let stepsPerBeatCandidates: [Int]

    private init(uncheckedMaxAdjustment: Double, stepsPerBeatCandidates: [Int]) {
        self.maxAdjustment = uncheckedMaxAdjustment
        self.stepsPerBeatCandidates = stepsPerBeatCandidates
    }

    public init(
        maxAdjustment: Double = 0.05,
        stepsPerBeatCandidates: [Int] = [1, 2]
    ) throws {
        guard maxAdjustment.isFinite,
              maxAdjustment >= Self.minimumSupportedAdjustment,
              maxAdjustment <= Self.maximumSupportedAdjustment
        else {
            throw TempoPolicyError.maxAdjustmentOutOfRange(maxAdjustment)
        }
        guard !stepsPerBeatCandidates.isEmpty,
              stepsPerBeatCandidates.allSatisfy({ Self.supportedStepsPerBeat.contains($0) })
        else {
            throw TempoPolicyError.unsupportedStepsPerBeat(stepsPerBeatCandidates)
        }
        self.init(
            uncheckedMaxAdjustment: maxAdjustment,
            stepsPerBeatCandidates: stepsPerBeatCandidates.sorted()
        )
    }

    /// Borne basse du rate appliqué (ex. 0.95 pour ±5 %).
    public var lowerBoundRate: Double { 1 - maxAdjustment }
    /// Borne haute du rate appliqué (ex. 1.05 pour ±5 %).
    public var upperBoundRate: Double { 1 + maxAdjustment }

    /// Admissibilité d'un ratio : `abs(requiredRate - 1) <= maxAdjustment` (§05).
    public func isRateWithinBounds(_ rate: Double) -> Bool {
        guard rate.isFinite, rate > 0 else { return false }
        return abs(rate - 1) <= maxAdjustment
    }

    /// Bornage dans `[1 - maxAdjustment, 1 + maxAdjustment]`.
    /// Valeur absente ou non finie => 1.0 (tempo original), jamais une valeur inventée.
    public func limitedRate(_ rawRate: Double?) -> Double {
        guard let rawRate, rawRate.isFinite, rawRate > 0 else { return 1.0 }
        return min(max(rawRate, lowerBoundRate), upperBoundRate)
    }

    /// BPM cible visé pour un morceau : `targetCadenceSPM / stepsPerBeat` (§05).
    public func targetTrackBPM(targetCadenceSPM: Double, stepsPerBeat: Int) -> Double? {
        guard targetCadenceSPM.isFinite, targetCadenceSPM > 0, stepsPerBeat > 0 else { return nil }
        let value = targetCadenceSPM / Double(stepsPerBeat)
        guard value.isFinite, value > 0 else { return nil }
        return value
    }

    /// Ratio requis `targetTrackBPM / nominalBPM` pour n pas par battement (§05).
    /// `nil` si l'un des termes est absent ou inexploitable : aucune division par zéro.
    public func requiredRate(
        targetCadenceSPM: Double,
        nominalBPM: Double,
        stepsPerBeat: Int
    ) -> Double? {
        guard let targetTrackBPM = targetTrackBPM(
            targetCadenceSPM: targetCadenceSPM,
            stepsPerBeat: stepsPerBeat
        ) else { return nil }
        guard nominalBPM.isFinite, nominalBPM > 0 else { return nil }
        let rate = targetTrackBPM / nominalBPM
        guard rate.isFinite, rate > 0 else { return nil }
        return rate
    }
}
