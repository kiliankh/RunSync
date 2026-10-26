import Foundation

/// Paramètres du filtre de cadence. Centralisés et injectables pour les tests (§05) :
/// ce sont des **paramètres initiaux à mesurer**, pas des performances garanties.
public struct CadenceFilterConfiguration: Sendable, Equatable {
    /// Plage large de plausibilité ; les valeurs hors plage sont rejetées mais
    /// journalisées dans le diagnostic, jamais masquées (§05, T002).
    public var plausibleRangeSPM: ClosedRange<Double>
    /// Fenêtre médiane glissante sur les N dernières mesures valides (5 par défaut).
    public var medianWindowSize: Int
    /// Alpha du lissage exponentiel (0.25 initial).
    public var exponentialSmoothingAlpha: Double
    /// Écart minimal (SPM) pour envisager un changement de consigne.
    public var hysteresisSPM: Double
    /// Durée pendant laquelle l'écart doit se maintenir avant de bouger la consigne.
    public var hysteresisConfirmationSeconds: TimeInterval
    /// Au-delà de cette durée sans mesure valide, la qualité devient `unavailable`.
    public var staleSampleTimeoutSeconds: TimeInterval

    public static let standard = CadenceFilterConfiguration()

    public init(
        plausibleRangeSPM: ClosedRange<Double> = CadenceUnits.plausibleRangeSPM,
        medianWindowSize: Int = 5,
        exponentialSmoothingAlpha: Double = 0.25,
        hysteresisSPM: Double = 1.5,
        hysteresisConfirmationSeconds: TimeInterval = 2.0,
        staleSampleTimeoutSeconds: TimeInterval = 5.0
    ) {
        self.plausibleRangeSPM = plausibleRangeSPM
        self.medianWindowSize = medianWindowSize
        self.exponentialSmoothingAlpha = exponentialSmoothingAlpha
        self.hysteresisSPM = hysteresisSPM
        self.hysteresisConfirmationSeconds = hysteresisConfirmationSeconds
        self.staleSampleTimeoutSeconds = staleSampleTimeoutSeconds
    }

    /// Normalisation défensive : une configuration injectée ne doit jamais
    /// produire d'état incohérent (fenêtre vide, alpha hors plage, plage inversée).
    public var normalized: CadenceFilterConfiguration {
        var copy = self
        copy.medianWindowSize = min(max(medianWindowSize, 1), 61)
        copy.exponentialSmoothingAlpha = exponentialSmoothingAlpha.isFinite
            ? min(max(exponentialSmoothingAlpha, 0.01), 1.0)
            : 0.25
        copy.hysteresisSPM = hysteresisSPM.isFinite ? max(0, hysteresisSPM) : 1.5
        copy.hysteresisConfirmationSeconds = hysteresisConfirmationSeconds.isFinite
            ? max(0, hysteresisConfirmationSeconds)
            : 2.0
        copy.staleSampleTimeoutSeconds = staleSampleTimeoutSeconds.isFinite
            ? max(0, staleSampleTimeoutSeconds)
            : 5.0
        if !plausibleRangeSPM.lowerBound.isFinite
            || !plausibleRangeSPM.upperBound.isFinite
            || plausibleRangeSPM.lowerBound >= plausibleRangeSPM.upperBound {
            copy.plausibleRangeSPM = CadenceUnits.plausibleRangeSPM
        }
        return copy
    }
}

/// Motif de rejet d'une mesure de cadence (diagnostic, T002).
public enum CadenceRejection: Equatable, Sendable {
    /// Le capteur ne fournit aucune valeur (→ `nil`), cas normal d'un démarrage.
    case sensorReportedNoValue
    /// Valeur NaN.
    case notANumber
    /// Valeur infinie.
    case notFinite
    /// Valeur nulle ou négative.
    case nonPositive(Double)
    /// Valeur hors plage de plausibilité.
    case implausibleRange(Double)

    public var displayMessage: String {
        switch self {
        case .sensorReportedNoValue: return "Capteur sans valeur de cadence."
        case .notANumber: return "Valeur de cadence non numérique."
        case .notFinite: return "Valeur de cadence infinie."
        case let .nonPositive(value): return "Cadence non positive (\(value))."
        case let .implausibleRange(value): return "Cadence hors plage plausible (\(value))."
        }
    }
}

/// Résultat qualifié et horodaté du filtre (§05). `setpointSPM` est la consigne
/// robuste effectivement utilisée par les contrôleurs.
public struct CadenceAssessment: Sendable, Equatable {
    public let timestamp: Date
    /// Dernière mesure brute acceptée (avant lissage) — `nil` si rejetée.
    public let rawSPM: Double?
    /// Valeur lissée (EMA + médiane), avant hystérésis.
    public let smoothedSPM: Double?
    /// Consigne robuste après hystérésis : c'est elle que suivent Follow/Pace.
    public let setpointSPM: Double?
    public let quality: DataQuality
    public let lastRejection: CadenceRejection?
    public let rejectionCount: Int
    /// Vrai quand un écart est constaté mais pas encore confirmé (hystérésis).
    public let isAwaitingDeviationConfirmation: Bool
    public let secondsSinceLastPlausibleSample: TimeInterval?

    /// État initial : aucune donnée, aucune cadence inventée.
    public static let initial = CadenceAssessment(
        timestamp: Date(timeIntervalSince1970: 0),
        rawSPM: nil,
        smoothedSPM: nil,
        setpointSPM: nil,
        quality: .unavailable,
        lastRejection: nil,
        rejectionCount: 0,
        isAwaitingDeviationConfirmation: false,
        secondsSinceLastPlausibleSample: nil
    )

    public init(
        timestamp: Date,
        rawSPM: Double?,
        smoothedSPM: Double?,
        setpointSPM: Double?,
        quality: DataQuality,
        lastRejection: CadenceRejection?,
        rejectionCount: Int,
        isAwaitingDeviationConfirmation: Bool,
        secondsSinceLastPlausibleSample: TimeInterval?
    ) {
        self.timestamp = timestamp
        self.rawSPM = rawSPM
        self.smoothedSPM = smoothedSPM
        self.setpointSPM = setpointSPM
        self.quality = quality
        self.lastRejection = lastRejection
        self.rejectionCount = rejectionCount
        self.isAwaitingDeviationConfirmation = isAwaitingDeviationConfirmation
        self.secondsSinceLastPlausibleSample = secondsSinceLastPlausibleSample
    }
}

/// Filtre robuste de cadence (RS-011) : validation, fenêtre médiane, lissage EMA,
/// hystérésis avec confirmation temporelle, état de qualité explicite.
///
/// Objectifs couverts : T001 (conversion), T002 (rejets invalides non masqués),
/// T003 (un outlier isolé ne provoque pas de saut), T010 (absence de cadence
/// traitée comme indisponible, jamais 0), §05 exemple F (pas de pompage).
public struct CadenceFilter: Sendable {
    public let configuration: CadenceFilterConfiguration

    private var validWindow: [Double] = []
    private var smoothed: Double?
    private var setpoint: Double?
    private var deviationStart: Date?
    private var lastValidTimestamp: Date?
    private var lastValidSPM: Double?
    private var lastRejection: CadenceRejection?
    private var rejectionCountValue: Int = 0

    public private(set) var currentAssessment: CadenceAssessment = .initial

    public init(configuration: CadenceFilterConfiguration = .standard) {
        self.configuration = configuration.normalized
    }

    /// Rejette ou accepte une mesure, met à jour la consigne et retourne l'état qualifié.
    /// Aucun chemin de cette fonction ne remplace une cadence absente par 0.
    @discardableResult
    public mutating func ingest(_ sample: CadenceSample) -> CadenceAssessment {
        let rejection = Self.rejection(for: sample, in: configuration.plausibleRangeSPM)
        var acceptedValue: Double?

        if let rejection {
            lastRejection = rejection
            rejectionCountValue += 1
        } else if let spm = sample.stepsPerMinute {
            acceptedValue = spm
            applyAccepted(spm: spm, timestamp: sample.timestamp)
        } else {
            lastRejection = .sensorReportedNoValue
            rejectionCountValue += 1
        }

        currentAssessment = makeAssessment(
            timestamp: sample.timestamp,
            acceptedValue: acceptedValue
        )
        return currentAssessment
    }

    public mutating func reset() {
        validWindow.removeAll()
        smoothed = nil
        setpoint = nil
        deviationStart = nil
        lastValidTimestamp = nil
        lastValidSPM = nil
        lastRejection = nil
        rejectionCountValue = 0
        currentAssessment = .initial
    }

    /// Nombre total de mesures rejetées depuis le dernier `reset()` (diagnostic).
    public var rejectionCount: Int { rejectionCountValue }

    // MARK: - Interne

    private mutating func applyAccepted(spm: Double, timestamp: Date) {
        validWindow.append(spm)
        if validWindow.count > configuration.medianWindowSize {
            validWindow.removeFirst(validWindow.count - configuration.medianWindowSize)
        }
        lastValidTimestamp = timestamp
        lastValidSPM = spm

        guard let median = Self.median(validWindow) else { return }
        let alpha = configuration.exponentialSmoothingAlpha
        smoothed = smoothed.map { alpha * median + (1 - alpha) * $0 } ?? median

        guard let smoothedValue = smoothed else { return }
        guard let currentSetpoint = setpoint else {
            setpoint = smoothedValue
            deviationStart = nil
            return
        }
        if abs(smoothedValue - currentSetpoint) > configuration.hysteresisSPM {
            if let start = deviationStart {
                if timestamp.timeIntervalSince(start) >= configuration.hysteresisConfirmationSeconds {
                    setpoint = smoothedValue
                    deviationStart = nil
                }
            } else {
                deviationStart = timestamp
            }
        } else {
            deviationStart = nil
        }
    }

    private func makeAssessment(timestamp: Date, acceptedValue: Double?) -> CadenceAssessment {
        let age = lastValidTimestamp.map { timestamp.timeIntervalSince($0) }
        let quality: DataQuality
        if lastValidTimestamp == nil {
            quality = .unavailable
        } else if acceptedValue != nil {
            quality = .good
        } else {
            // Intervalle de faible confiance : état dégradé, aucune correction arbitraire.
            quality = (age ?? .greatestFiniteMagnitude) <= configuration.staleSampleTimeoutSeconds
                ? .degraded
                : .unavailable
        }
        return CadenceAssessment(
            timestamp: timestamp,
            rawSPM: acceptedValue,
            smoothedSPM: smoothed,
            setpointSPM: setpoint,
            quality: quality,
            lastRejection: lastRejection,
            rejectionCount: rejectionCountValue,
            isAwaitingDeviationConfirmation: deviationStart != nil,
            secondsSinceLastPlausibleSample: age
        )
    }

    private static func rejection(
        for sample: CadenceSample,
        in range: ClosedRange<Double>
    ) -> CadenceRejection? {
        guard let value = sample.stepsPerMinute else { return .sensorReportedNoValue }
        if value.isNaN { return .notANumber }
        if !value.isFinite { return .notFinite }
        if value <= 0 { return .nonPositive(value) }
        if !CadenceUnits.isPlausibleSPM(value, in: range) { return .implausibleRange(value) }
        return nil
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let count = sorted.count
        if count % 2 == 1 { return sorted[count / 2] }
        return (sorted[count / 2 - 1] + sorted[count / 2]) / 2
    }
}
