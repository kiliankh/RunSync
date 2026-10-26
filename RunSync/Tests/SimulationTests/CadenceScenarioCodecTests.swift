import XCTest
import RunSyncDomain
import RunSyncSimulation

/// Fixtures du simulateur (RS-004) : décodage JSON/CSV et rejet des scénarios
/// invalides à la frontière d'entrée (§07 : les entrées externes sont non fiables).
final class CadenceScenarioCodecTests: XCTestCase {

    /// `.../RunSync/Tests/Fixtures` — les fixtures vivent hors des répertoires de
    /// cibles SwiftPM, elles sont donc lues directement depuis le disque.
    private static var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SimulationTests
            .deletingLastPathComponent()   // Tests
            .appendingPathComponent("Fixtures")
    }

    private func fixtureData(_ name: String, extension ext: String) throws -> Data {
        try Data(contentsOf: Self.fixturesDirectory.appendingPathComponent("\(name).\(ext)"))
    }

    func test_theJSONFixtureMatchesTheBuiltInDemoScenario() throws {
        let scenario = try CadenceScenarioCodec.decodeJSON(
            try fixtureData("cadence_demo_scenario", extension: "json")
        )
        XCTAssertEqual(scenario, CadenceScenario.demoFollow)
        XCTAssertEqual(scenario.id, "demo.follow")
        XCTAssertEqual(scenario.durationSeconds, 60)
        XCTAssertEqual(scenario.steps.count, 5)
    }

    func test_theCSVFixtureMatchesTheBuiltInDemoScenario() throws {
        let scenario = try CadenceScenarioCodec.decodeCSV(
            String(decoding: try fixtureData("cadence_demo_scenario", extension: "csv"), as: UTF8.self)
        )
        XCTAssertEqual(scenario, CadenceScenario.demoFollow)
    }

    func test_bothFormatsProduceIdenticalSamples() throws {
        let fromJSON = try CadenceScenarioCodec.decodeJSON(
            try fixtureData("cadence_demo_scenario", extension: "json")
        )
        let fromCSV = try CadenceScenarioCodec.decodeCSV(
            String(decoding: try fixtureData("cadence_demo_scenario", extension: "csv"), as: UTF8.self)
        )
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(fromJSON.replay(startingAt: start), fromCSV.replay(startingAt: start))
        // Une valeur absente dans le CSV est bien « capteur sans valeur ».
        XCTAssertNil(fromCSV.value(atElapsed: 30))
        XCTAssertEqual(fromCSV.value(atElapsed: 55), 170)
    }

    func test_aScenarioWithNonIncreasingOffsetsIsRejected() throws {
        let text = String(
            decoding: try fixtureData("cadence_invalid_scenario", extension: "csv"),
            as: UTF8.self
        )
        XCTAssertThrowsError(try CadenceScenarioCodec.decodeCSV(text)) { error in
            XCTAssertEqual(error as? CadenceScenarioError, .nonIncreasingOffsets(index: 2))
        }
    }

    func test_malformedCSVIsReportedWithItsLineNumber() {
        let text = """
        duration=30
        offsetSeconds,stepsPerMinute
        0,170
        10,pas un nombre
        """
        XCTAssertThrowsError(try CadenceScenarioCodec.decodeCSV(text)) { error in
            XCTAssertEqual(
                error as? CadenceScenarioError,
                .malformedLine(lineNumber: 4, content: "10,pas un nombre")
            )
        }
    }

    func test_aCSVWithoutDurationIsRejected() {
        let text = """
        offsetSeconds,stepsPerMinute
        0,170
        """
        XCTAssertThrowsError(try CadenceScenarioCodec.decodeCSV(text)) { error in
            XCTAssertEqual(error as? CadenceScenarioError, .missingDuration)
        }
    }

    func test_validationRefusesEmptyScenariosAndNonFiniteValues() {
        XCTAssertThrowsError(
            try CadenceScenario(id: "empty", name: "vide", steps: [], durationSeconds: 10).validated()
        ) { error in
            XCTAssertEqual(error as? CadenceScenarioError, .emptySteps)
        }

        XCTAssertThrowsError(
            try CadenceScenario(
                id: "nan",
                name: "non fini",
                steps: [.init(offsetSeconds: 0, stepsPerMinute: .nan)],
                durationSeconds: 10
            ).validated()
        ) { error in
            XCTAssertEqual(error as? CadenceScenarioError, .nonFiniteCadence(index: 0))
        }

        XCTAssertThrowsError(
            try CadenceScenario(
                id: "short",
                name: "durée trop courte",
                steps: [.init(offsetSeconds: 0, stepsPerMinute: 170)],
                durationSeconds: -1
            ).validated()
        )
    }

    func test_theDecodedScenarioIsRejectedWhenDurationCannotCoverIt() {
        let json = """
        {
          "id": "bad",
          "name": "durée insuffisante",
          "durationSeconds": 5,
          "steps": [
            { "offsetSeconds": 0, "stepsPerMinute": 170 },
            { "offsetSeconds": 40, "stepsPerMinute": 180 }
          ]
        }
        """
        XCTAssertThrowsError(try CadenceScenarioCodec.decodeJSON(Data(json.utf8))) { error in
            guard case .durationShorterThanLastStep? = error as? CadenceScenarioError else {
                return XCTFail("Attendu .durationShorterThanLastStep, obtenu \(error)")
            }
        }
    }

    func test_aJSONScenarioWithoutCadenceValuesDecodesAsUnavailable() throws {
        let json = """
        {
          "id": "noCadence",
          "name": "capteur absent",
          "durationSeconds": 3,
          "steps": [{ "offsetSeconds": 0, "stepsPerMinute": null }]
        }
        """
        let scenario = try CadenceScenarioCodec.decodeJSON(Data(json.utf8))
        let samples = scenario.replay(startingAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(samples.count, 4)
        XCTAssertTrue(samples.allSatisfy { $0.stepsPerMinute == nil })
        XCTAssertTrue(samples.allSatisfy { $0.quality == .unavailable })
    }
}
