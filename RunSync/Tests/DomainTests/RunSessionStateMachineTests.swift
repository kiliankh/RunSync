import XCTest
import RunSyncDomain

/// Machine à états de session : T012 « no double session; pause/reprise/finish
/// idempotents ». Le coordinateur complet `RS-013` (audio + capteurs) arrive en
/// phase 2 ; cette machine est la partie pure, testable sans iPhone.
final class RunSessionStateMachineTests: XCTestCase {

    func test_T012_startIsIdempotentAndNeverCreatesASecondSession() throws {
        var machine = RunSessionStateMachine()
        XCTAssertEqual(try machine.apply(.start), .running)
        XCTAssertEqual(try machine.apply(.start), .running)
        XCTAssertEqual(try machine.applyCountingTransitions(.start), 0, "Aucune seconde session")
        XCTAssertTrue(machine.state.isOccupyingARun)
        XCTAssertEqual(try machine.apply(.pause), .paused)
        XCTAssertEqual(try machine.apply(.pause), .paused, "La pause est idempotente")
        XCTAssertEqual(try machine.apply(.resume), .running)
        XCTAssertEqual(try machine.apply(.finish), .finished)
        XCTAssertEqual(try machine.apply(.finish), .finished, "Terminer deux fois ne casse rien")
        XCTAssertEqual(try machine.applyCountingTransitions(.finish), 0)
        XCTAssertFalse(machine.state.isOccupyingARun)
        XCTAssertEqual(try machine.apply(.reset), .idle)
    }

    func test_T012_invalidTransitionsAreRejectedWithoutChangingTheState() {
        var machine = RunSessionStateMachine()
        XCTAssertThrowsError(try machine.apply(.pause)) { error in
            XCTAssertEqual(
                error as? RunSessionTransitionError,
                .invalidTransition(from: .idle, event: .pause)
            )
        }
        XCTAssertEqual(machine.state, .idle)

        XCTAssertThrowsError(try machine.apply(.finish))
        XCTAssertEqual(machine.state, .idle)

        XCTAssertNoThrow(try machine.apply(.start))
        XCTAssertThrowsError(try machine.apply(.prepare)) { error in
            XCTAssertEqual(
                error as? RunSessionTransitionError,
                .invalidTransition(from: .running, event: .prepare)
            )
        }
        XCTAssertEqual(machine.state, .running)
    }

    func test_anIrreversibleFailureMovesToFailedAndCanBeReset() throws {
        var machine = RunSessionStateMachine()
        XCTAssertEqual(try machine.apply(.prepare), .preparing)
        XCTAssertEqual(try machine.apply(.fail), .failed)
        XCTAssertEqual(try machine.apply(.fail), .failed, "L'échec est idempotent")
        XCTAssertEqual(try machine.apply(.reset), .idle)
        XCTAssertEqual(try machine.apply(.start), .running, "Une nouvelle session peut démarrer")
    }

    func test_theTeardownStateIsReachableAndFinishRemainsIdempotent() throws {
        var machine = RunSessionStateMachine()
        XCTAssertEqual(try machine.apply(.start), .running)
        XCTAssertEqual(try machine.apply(.beginFinishing), .finishing)
        XCTAssertEqual(try machine.apply(.finish), .finished)
        XCTAssertEqual(try machine.apply(.finish), .finished)
    }

    func test_theErrorExposesAStableCodeAndAUserMessage() {
        let error = RunSessionTransitionError.invalidTransition(from: .idle, event: .pause)
        XCTAssertEqual(error.code, "runsync.session.invalid_transition")
        XCTAssertFalse(error.displayMessage.isEmpty)
    }
}
