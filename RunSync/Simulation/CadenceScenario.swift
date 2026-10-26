import Foundation
import RunSyncDomain

/// Erreurs de scénario de cadence (simulateur RS-004).
public enum CadenceScenarioError: Error, Equatable, Sendable {
    case emptySteps
    case negativeOffset(index: Int)
    case nonIncreasingOffsets(index: Int)
    case nonFiniteCadence(index: Int)
    case durationShorterThanLastStep(lastOffset: TimeInterval, duration: TimeInterval)
    case missingDuration
    case malformedLine(lineNumber: Int, content: String)

    public var code: String { "runsync.simulation.scenario" }

    public var displayMessage: String {
        switch self {
        case .emptySteps:
            return "Scénario de cadence vide."
        case let .negativeOffset(index):
            return "Décalage négatif au point \(index)."
        case let .nonIncreasingOffsets(index):
            return "Décalages non croissants au point \(index)."
        case let .nonFiniteCadence(index):
            return "Cadence non finie au point \(index)."
        case let .durationShorterThanLastStep(lastOffset, duration):
            return "Durée (\(duration) s) plus courte que le dernier point (\(lastOffset) s)."
        case .missingDuration:
            return "Durée du scénario manquante."
        case let .malformedLine(lineNumber, content):
            return "Ligne \(lineNumber) illisible : « \(content) »."
        }
    }
}

/// Scénario de cadence déterministe : une suite de points de changement
/// horodatés. Un point sans valeur (`stepsPerMinute == nil`) simule un capteur
/// qui ne fournit aucune mesure — cas D du cahier des charges §05 (FR-004).
public struct CadenceScenario: Sendable, Equatable, Codable {

    /// Point de changement : la valeur devient effective à `offsetSeconds`.
    public struct Step: Sendable, Equatable, Codable {
        public let offsetSeconds: TimeInterval
        /// `nil` = le capteur ne fournit aucune valeur à partir de ce point.
        public let stepsPerMinute: Double?
        public let note: String?

        public init(offsetSeconds: TimeInterval, stepsPerMinute: Double?, note: String? = nil) {
            self.offsetSeconds = offsetSeconds
            self.stepsPerMinute = stepsPerMinute
            self.note = note
        }
    }

    public let id: String
    public let name: String
    /// Points de changement, triés par décalage croissant strict.
    public let steps: [Step]
    /// Durée totale du scénario en secondes.
    public let durationSeconds: TimeInterval

    public init(
        id: String,
        name: String,
        steps: [Step],
        durationSeconds: TimeInterval
    ) {
        self.id = id
        self.name = name
        self.steps = steps
        self.durationSeconds = durationSeconds
    }

    /// Valide les invariants du scénario. À appeler à la frontière d'entrée
    /// (décodage de fixture, saisie externe) — §07.
    @discardableResult
    public func validated() throws -> CadenceScenario {
        guard !steps.isEmpty else { throw CadenceScenarioError.emptySteps }
        var previousOffset: TimeInterval?
        for (index, step) in steps.enumerated() {
            if !step.offsetSeconds.isFinite || step.offsetSeconds < 0 {
                throw CadenceScenarioError.negativeOffset(index: index)
            }
            if let previousOffset, step.offsetSeconds <= previousOffset {
                throw CadenceScenarioError.nonIncreasingOffsets(index: index)
            }
            if let value = step.stepsPerMinute, !value.isFinite {
                throw CadenceScenarioError.nonFiniteCadence(index: index)
            }
            previousOffset = step.offsetSeconds
        }
        guard durationSeconds.isFinite,
              let lastOffset = steps.last?.offsetSeconds,
              durationSeconds >= lastOffset
        else {
            throw CadenceScenarioError.durationShorterThanLastStep(
                lastOffset: steps.last?.offsetSeconds ?? 0,
                duration: durationSeconds
            )
        }
        return self
    }

    /// Valeur de cadence effective à un instant donné du scénario.
    /// Recherche linéaire volontairement triviale : les scénarios sont courts
    /// et le déterminisme prime.
    public func value(atElapsed elapsed: TimeInterval) -> Double? {
        var current: Double?
        for step in steps {
            if step.offsetSeconds <= elapsed {
                current = step.stepsPerMinute
            } else {
                break
            }
        }
        return current
    }

    /// Développe le scénario en échantillons horodatés, à intervalle fixe.
    /// Entièrement déterministe : aucune horloge murale, aucun minuteur (FR-004).
    public func replay(
        tickInterval: TimeInterval = 1.0,
        startingAt startDate: Date,
        sourceIdentifier: String = "simulation.cadence"
    ) -> [CadenceSample] {
        let interval = tickInterval.isFinite && tickInterval > 0 ? tickInterval : 1.0
        let sampleCount = Int((durationSeconds / interval).rounded(.down)) + 1
        guard sampleCount > 0 else { return [] }
        return (0..<sampleCount).map { index in
            let elapsed = Double(index) * interval
            let value = value(atElapsed: elapsed)
            return CadenceSample(
                timestamp: startDate.addingTimeInterval(elapsed),
                stepsPerMinute: value,
                quality: value == nil ? .unavailable : .good,
                sourceIdentifier: sourceIdentifier
            )
        }
    }

    // MARK: - Scénarios de référence

    /// Script imposé par la spec §16.E : 170 -> 176 -> 160 -> indisponible -> 170.
    ///
    /// Durées choisies pour rendre visibles les états exigés :
    /// montée à 176 (changement soutenu de consigne), baisse à 160 (bornage),
    /// 22 s sans mesure (maintien puis retour doux vers le tempo original),
    /// reprise à 170 (retour au suivi).
    public static let demoFollow = CadenceScenario(
        id: "demo.follow",
        name: "Suivi 170 -> 176 -> 160 -> indisponible -> 170",
        steps: [
            Step(offsetSeconds: 0, stepsPerMinute: 170, note: "allure de croisière"),
            Step(offsetSeconds: 10, stepsPerMinute: 176, note: "accélération soutenue"),
            Step(offsetSeconds: 20, stepsPerMinute: 160, note: "ralentissement"),
            Step(offsetSeconds: 28, stepsPerMinute: nil, note: "capteur indisponible"),
            Step(offsetSeconds: 50, stepsPerMinute: 170, note: "reprise")
        ],
        durationSeconds: 60
    )

    /// Cadence stable à 170 SPM : sert aux tests de non-pompage (§05 exemple F).
    public static func constant(
        _ stepsPerMinute: Double,
        durationSeconds: TimeInterval,
        id: String = "constant",
        name: String? = nil
    ) -> CadenceScenario {
        CadenceScenario(
            id: id,
            name: name ?? "Cadence constante \(stepsPerMinute) SPM",
            steps: [Step(offsetSeconds: 0, stepsPerMinute: stepsPerMinute, note: nil)],
            durationSeconds: durationSeconds
        )
    }
}
