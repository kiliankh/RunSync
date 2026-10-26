import XCTest
@testable import RunSyncDomain

/// Tests de la rampe de vitesse (§05 : « limiter dérivée playbackRate à env. 0.01
/// par seconde », « mise à jour effective du paramètre audio à intervalles
/// contrôlés (ex. 4 Hz au maximum) », NFR-004).
///
/// Ces tests décrivent le comportement observable côté audio : jamais de marche
/// audible, jamais d'écriture inutile dans le graphe, jamais de dépassement de la
/// limite d'ajustement.
final class PlaybackRateRampTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    /// Interrogation à 4 Hz (une fois toutes les 0,25 s), comme la session réelle.
    private func poll(
        _ ramp: inout PlaybackRateRamp,
        from start: Date = Date(timeIntervalSince1970: 1_700_000_000),
        ticks: Int,
        interval: TimeInterval = 0.25
    ) -> [PlaybackRateRamp.Command] {
        var commands: [PlaybackRateRamp.Command] = []
        for tick in 0...ticks {
            let now = start.addingTimeInterval(Double(tick) * interval)
            if let command = ramp.command(at: now) {
                commands.append(command)
            }
        }
        return commands
    }

    // MARK: - État initial

    func testFirstCommandIsEmittedImmediatelyAtOriginalTempo() {
        var ramp = PlaybackRateRamp()
        let command = ramp.command(at: base)

        XCTAssertEqual(command?.rate, 1.0, "Le premier état transmis est le tempo original.")
        XCTAssertEqual(command?.isInitial, true)
        XCTAssertEqual(command?.timestamp, base)
        XCTAssertEqual(ramp.currentRate, 1.0)
        XCTAssertTrue(ramp.isSettled, "Sans consigne, la rampe est stable.")
    }

    func testSettledRampDoesNotWriteToTheAudioGraph() {
        var ramp = PlaybackRateRamp()
        _ = ramp.command(at: base)

        let commands = poll(&ramp, ticks: 8)

        XCTAssertTrue(
            commands.isEmpty,
            "Aucune écriture audio n'est nécessaire tant que rien ne change (NFR-004)."
        )
    }

    // MARK: - Limitation de la dérivée

    func testRampsTowardTargetAtOnePercentPerSecond() {
        var ramp = PlaybackRateRamp()
        ramp.acceptTarget(1.05)

        let commands = poll(&ramp, ticks: 20) // 0 -> 5 s
        let rates = commands.map(\.rate)

        XCTAssertEqual(rates.first ?? 0, 1.0, accuracy: 1e-9)
        XCTAssertEqual(rates.last ?? 0, 1.05, accuracy: 1e-9)
        XCTAssertEqual(ramp.currentRate, 1.05, accuracy: 1e-9)
        XCTAssertTrue(ramp.isSettled)
    }

    func testNoSingleStepExceedsOnePercentagePointPerSecond() {
        var ramp = PlaybackRateRamp()
        ramp.acceptTarget(1.05)

        let commands = poll(&ramp, ticks: 24)

        XCTAssertEqual(commands.first?.rate ?? 0, 1.0, accuracy: 1e-9)
        for (previous, current) in zip(commands, commands.dropFirst()) {
            XCTAssertLessThanOrEqual(
                abs(current.rate - previous.rate),
                0.0025 + 1e-9,
                "Une écriture audio ne dépasse jamais 1 point de % par seconde écoulée."
            )
        }
    }

    func testDownwardRampIsAlsoLimited() {
        var ramp = PlaybackRateRamp()
        ramp.acceptTarget(1.05)
        let upward = poll(&ramp, ticks: 20)
        XCTAssertEqual(ramp.currentRate, 1.05, accuracy: 1e-9)

        ramp.acceptTarget(1.0)
        let downward = poll(&ramp, from: base.addingTimeInterval(5), ticks: 20)

        // La suite complète (montée puis descente) reste monotone par morceaux et
        // sans marche : c'est ce que le moteur audio va réellement appliquer.
        let sequence = upward + downward
        for (previous, current) in zip(sequence, sequence.dropFirst()) {
            XCTAssertLessThanOrEqual(
                abs(current.rate - previous.rate),
                0.0025 + 1e-9,
                "La rampe descendante est limitée comme la montante."
            )
        }
        XCTAssertEqual(ramp.currentRate, 1.0, accuracy: 1e-9)
    }

    /// Cas redouté : une longue inactivité ne doit pas autoriser un rattrapage
    /// brutal de plusieurs points de pourcentage en une seule écriture.
    func testLongIdlePeriodDoesNotAllowAnAudibleJump() {
        var ramp = PlaybackRateRamp()
        _ = poll(&ramp, ticks: 120) // 30 s sans aucune consigne : maintien à 1.0

        XCTAssertEqual(ramp.currentRate, 1.0, accuracy: 1e-9)

        ramp.acceptTarget(1.05)
        let command = ramp.command(at: base.addingTimeInterval(30.25))

        let rate = try? XCTUnwrap(command?.rate)
        XCTAssertEqual(rate ?? 0, 1.0025, accuracy: 1e-9)
    }

    // MARK: - Cadence de mise à jour

    func testMinimumCommandIntervalBoundsUpdateFrequency() {
        var ramp = PlaybackRateRamp()
        ramp.acceptTarget(1.05)
        _ = ramp.command(at: base)

        XCTAssertNil(ramp.command(at: base.addingTimeInterval(0.05)))
        XCTAssertNil(ramp.command(at: base.addingTimeInterval(0.10)))
        XCTAssertNil(ramp.command(at: base.addingTimeInterval(0.24)))

        let due = ramp.command(at: base.addingTimeInterval(0.25))
        XCTAssertNotNil(due, "La commande suivante est due à l'intervalle minimal.")
        XCTAssertEqual(due?.isInitial, false)
    }

    func testRapidPollingStillProducesAtMostFourCommandsPerSecond() {
        var ramp = PlaybackRateRamp()
        ramp.acceptTarget(1.05)

        // 100 interrogations en 1 seconde : la fréquence d'écriture reste bornée.
        var commands: [PlaybackRateRamp.Command] = []
        for tick in 0...100 {
            let now = base.addingTimeInterval(Double(tick) * 0.01)
            if let command = ramp.command(at: now) {
                commands.append(command)
            }
        }

        XCTAssertLessThanOrEqual(commands.count, 5)
        for pair in zip(commands, commands.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                pair.1.timestamp.timeIntervalSince(pair.0.timestamp),
                0.25 - 1e-9
            )
        }
    }

    // MARK: - Bornes et absence de consigne

    func testTargetIsClampedToTheAdjustmentLimit() {
        var ramp = PlaybackRateRamp(policy: .standard)
        ramp.acceptTarget(1.5)

        let commands = poll(&ramp, ticks: 40)

        XCTAssertLessThanOrEqual(commands.map(\.rate).max() ?? 0, 1.05 + 1e-9)
        XCTAssertEqual(ramp.currentRate, 1.05, accuracy: 1e-9)
    }

    func testLowerTargetIsClampedToTheAdjustmentLimit() {
        var ramp = PlaybackRateRamp(policy: .standard)
        ramp.acceptTarget(0.5)

        _ = poll(&ramp, ticks: 40)

        XCTAssertEqual(ramp.currentRate, 0.95, accuracy: 1e-9)
    }

    /// Cas D du §05 : plus de cadence exploitable. La consigne est absente, la
    /// vitesse courante est maintenue — aucune valeur n'est inventée.
    func testMissingTargetHoldsTheCurrentRate() {
        var ramp = PlaybackRateRamp()
        ramp.acceptTarget(1.03)
        _ = poll(&ramp, ticks: 12)
        let held = ramp.currentRate
        XCTAssertEqual(held, 1.03, accuracy: 1e-9)

        ramp.acceptTarget(nil)
        let commands = poll(&ramp, from: base.addingTimeInterval(3), ticks: 20)

        XCTAssertEqual(ramp.currentRate, held, accuracy: 1e-9)
        XCTAssertTrue(commands.isEmpty)
        XCTAssertEqual(ramp.pendingAdjustmentPercent, 0, accuracy: 1e-9)
    }

    /// Une consigne non finie est rejetée par la politique, qui retourne le tempo
    /// original : on ne part pas non plus dans l'autre excès en appliquant une borne
    /// maximale inventée.
    func testNonFiniteTargetFallsBackToOriginalTempo() {
        var ramp = PlaybackRateRamp()
        ramp.acceptTarget(1.03)
        _ = poll(&ramp, ticks: 12)

        ramp.acceptTarget(Double.nan)
        _ = poll(&ramp, from: base.addingTimeInterval(3), ticks: 12)

        XCTAssertEqual(ramp.currentRate, 1.0, accuracy: 1e-9)
        XCTAssertTrue(ramp.isSettled)
    }

    func testPendingAdjustmentReportsRemainingDistance() {
        var ramp = PlaybackRateRamp()
        ramp.acceptTarget(1.05)
        _ = poll(&ramp, ticks: 4) // 1 s de rampe

        XCTAssertEqual(ramp.pendingAdjustmentPercent, 4.0, accuracy: 1e-6)
        XCTAssertFalse(ramp.isSettled)
    }

    func testResetReturnsToOriginalTempo() {
        var ramp = PlaybackRateRamp()
        ramp.acceptTarget(1.05)
        _ = poll(&ramp, ticks: 8)

        ramp.reset()

        XCTAssertEqual(ramp.currentRate, 1.0)
        XCTAssertNil(ramp.targetRate)
        XCTAssertTrue(ramp.isSettled)

        let command = ramp.command(at: base.addingTimeInterval(10))
        XCTAssertEqual(command?.rate, 1.0)
        XCTAssertEqual(command?.isInitial, true, "Après réinitialisation, la session réaffirme son état initial.")
    }

    // MARK: - Robustesse des paramètres injectés

    func testDefensiveParametersAreNormalized() {
        let ramp = PlaybackRateRamp(
            maximumSlewPerSecond: .nan,
            minimumCommandInterval: -1,
            minimumEmittedDelta: 0,
            maximumEvaluationStepSeconds: .infinity
        )

        XCTAssertEqual(ramp.maximumSlewPerSecond, 0.01)
        XCTAssertEqual(ramp.minimumCommandInterval, 0.05)
        XCTAssertEqual(ramp.minimumEmittedDelta, 0.0005)
        XCTAssertEqual(ramp.maximumEvaluationStepSeconds, 1.0)
        XCTAssertEqual(ramp.currentRate, 1.0)
    }

    func testDurationOfAFullFivePercentTransitionIsFiveSeconds() {
        var ramp = PlaybackRateRamp()
        ramp.acceptTarget(1.05)

        var reachedAt: TimeInterval?
        for tick in 0...200 {
            let elapsed = Double(tick) * 0.05
            _ = ramp.command(at: base.addingTimeInterval(elapsed))
            if reachedAt == nil, ramp.isSettled, ramp.currentRate > 1.0 {
                reachedAt = elapsed
            }
        }

        let duration = reachedAt ?? 0
        XCTAssertGreaterThanOrEqual(duration, 4.9)
        XCTAssertLessThanOrEqual(duration, 5.1, "5 points de % à 1 point par seconde.")
    }
}
