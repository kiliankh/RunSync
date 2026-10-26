import Foundation
import RunSyncDomain
import RunSyncSimulation

// Outil de diagnostic (livrable « suite de tests et outils de diagnostic », §00 §12 RS-045).
//
// Il rejoue un scénario de cadence déterministe et affiche la chaîne complète :
// cadence brute -> filtre (consigne, qualité) -> matcher -> décision -> rate appliqué.
// Aucun capteur, aucun audio, aucun réseau, aucun appareil : exécutable partout où
// Swift compile (macOS comme Linux).
//
//   swift run runsync-demo            # scénario de démonstration (Follow)
//   swift run runsync-demo pace       # démonstration du mode Pace

func pad(_ text: String, _ width: Int, rightAligned: Bool = true) -> String {
    if text.count >= width { return String(text.prefix(width)) }
    let padding = String(repeating: " ", count: width - text.count)
    return rightAligned ? padding + text : text + padding
}

func number(_ value: Double?, digits: Int = 1, width: Int = 8) -> String {
    guard let value, value.isFinite else { return pad("—", width) }
    return pad(String(format: "%.\(digits)f", value), width)
}

let startDate = Date(timeIntervalSince1970: 1_700_000_000)
let arguments = Array(CommandLine.arguments.dropFirst())
let paceMode = arguments.contains("pace")

if paceMode {
    demonstratePaceMode()
} else {
    demonstrateFollowMode()
}

// MARK: - Mode Follow : le script de démonstration complet

func demonstrateFollowMode() {
    let scenario = CadenceScenario.demoFollow
    let source = FakeCadenceSource(scenario: scenario, tickInterval: 1.0, startDate: startDate)

    var filter = CadenceFilter()
    var controller = FollowController(policy: .standard)
    controller.start(at: startDate.addingTimeInterval(-1))

    print("RunSync — diagnostic du mode Follow")
    print("Scénario    : \(scenario.name)")
    print("Morceau test: \(DemoLibrary.testTrack.title) — "
        + "\(DemoLibrary.testTrack.nominalBPM.map { String(format: "%.0f BPM", $0) } ?? "BPM inconnu")")
    print("Politique   : ajustement maximal ±\(Int(TempoMatchingPolicy.standard.maxAdjustment * 100)) %, "
        + "rampe \(FollowTimingConfiguration.standard.rateSlewPerSecond)/s, "
        + "maintien \(Int(FollowTimingConfiguration.standard.cadenceLossHoldSeconds)) s")
    print("")
    print(pad("t(s)", 5) + pad("brute", 8) + pad("consigne", 10) + pad("qualité", 13)
        + pad("ratio", 9) + pad("rate", 9) + pad("ajust.", 8) + "  raison")
    print(String(repeating: "-", count: 96))

    // Le scénario est échantillonné à 1 Hz : un échantillon synchronisé = une seconde.
    var synchronizedSeconds: Double = 0
    var cadenceSum: Double = 0
    var cadenceCount = 0

    for sample in source.replay() {
        let assessment = filter.ingest(sample)
        let decision = controller.update(
            cadence: assessment,
            track: DemoLibrary.testTrack,
            candidates: DemoLibrary.tracks,
            now: sample.timestamp
        ).tempo

        if let raw = assessment.rawSPM {
            cadenceSum += raw
            cadenceCount += 1
        }
        let elapsed = sample.timestamp.timeIntervalSince(startDate)
        if decision.reason.isActivelySynchronized, elapsed > 0 {
            synchronizedSeconds += 1
        }

        let second = Int(elapsed.rounded())
        let shouldPrint = second % 2 == 0 || decision.reason != .followingCadence
        guard shouldPrint else { continue }

        print(
            pad("\(second)", 5)
                + number(assessment.rawSPM, width: 8)
                + number(assessment.setpointSPM, width: 10)
                + " " + pad(assessment.quality.rawValue, 12, rightAligned: false)
                + number(decision.requiredRate, digits: 4, width: 8) + " "
                + number(decision.appliedRate, digits: 4, width: 8) + " "
                + number(decision.appliedAdjustmentPercent, width: 8)
                + "  " + decision.reason.rawValue
        )
    }

    let averageCadence = cadenceCount > 0 ? cadenceSum / Double(cadenceCount) : nil
    print("")
    print("Résumé")
    print("  durée simulée        : \(Int(scenario.durationSeconds)) s")
    print("  cadence moyenne      : \(averageCadence.map { String(format: "%.1f SPM", $0) } ?? "—")")
    print("  mesures valides      : \(cadenceCount)")
    print("  mesures rejetées     : \(filter.rejectionCount) (aucune cadence inventée)")
    print("  temps synchronisé    : \(Int(synchronizedSeconds)) s sur \(Int(scenario.durationSeconds)) s")
    print("  rate final           : \(String(format: "%.4f", controller.currentAppliedRate))")
    print("")
    print("Rappel : la consigne est bornée par l'hystérésis (1,5 SPM confirmés sur 2 s).")
    print("Elle peut donc se stabiliser légèrement sous la cadence réelle : c'est voulu,")
    print("pour éviter toute oscillation audible du tempo.")
}

// MARK: - Mode Pace : cible déclarée, écart réel affiché à part

func demonstratePaceMode() {
    let paceTarget = 172.0
    var controller = PaceController(
        policy: .standard,
        configuration: PaceControllerConfiguration(
            targetCadenceSPM: paceTarget,
            targetPaceSecondsPerKilometer: 300
        )
    )
    controller.start(at: startDate)

    let track = TrackDescriptor(
        title: "Test 172 BPM",
        nominalBPM: 172,
        bpmProvenance: .manual,
        bpmConfidence: 1.0,
        providerID: ProviderCatalog.localImportedFiles.id,
        canAlterTempo: true,
        isFileAvailable: true,
        isAdaptationRightsAttested: true
    )

    print("RunSync — diagnostic du mode Pace")
    print("Allure cible : 5:00 /km   Cadence cible déclarée : \(Int(paceTarget)) SPM")
    print("Morceau      : \(track.title) — 172 BPM")
    print("")
    print(pad("t(s)", 5) + pad("cadence", 9) + pad("Δ cible", 9) + pad("rate", 9)
        + pad("BPM cible", 11) + "  raison")
    print(String(repeating: "-", count: 84))

    var filter = CadenceFilter()
    for index in 1...12 {
        // Le coureur est en dessous de sa cible et varie : la musique ne doit pas suivre.
        let observed = [160.0, 158, 162, 155, 165, 160, 150, 168, 160, 157, 163, 160][index - 1]
        let timestamp = startDate.addingTimeInterval(Double(index))
        let assessment = filter.ingest(
            CadenceSample(
                timestamp: timestamp,
                stepsPerMinute: observed,
                quality: .good,
                sourceIdentifier: "simulation.cadence"
            )
        )
        let decision = controller.update(
            observedCadence: assessment,
            track: track,
            candidates: [track],
            now: timestamp
        )
        print(
            pad("\(index)", 5)
                + number(observed, width: 9)
                + number(decision.cadenceDeltaSPM, width: 9)
                + number(decision.tempo.appliedRate, digits: 4, width: 8)
                + number(decision.tempo.targetTrackBPM, width: 11)
                + "  " + decision.tempo.reason.rawValue
        )
    }
    print("")
    print("La cible musicale reste 172 SPM : l'application n'accélère pas la musique")
    print("quand le coureur ralentit, sinon le guidage serait contradictoire (§05).")
}
