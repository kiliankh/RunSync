import Foundation

/// Machine à états de session (§07). Transitions idempotentes : `stop`/`finish`
/// ne doivent jamais produire de double moteur ni de session fantôme (T012).
public enum RunSessionState: String, Codable, Sendable, CaseIterable, Equatable {
    case idle
    case preparing
    case running
    case paused
    case finishing
    case finished
    case failed

    /// Une session occupant des ressources (capteurs, audio, enregistrement).
    public var isOccupyingARun: Bool {
        switch self {
        case .preparing, .running, .paused, .finishing: return true
        case .idle, .finished, .failed: return false
        }
    }
}

/// Événements de la machine à états.
public enum RunSessionEvent: String, Sendable, CaseIterable, Equatable {
    case prepare
    case start
    case pause
    case resume
    case beginFinishing
    case finish
    case fail
    case reset
}

public enum RunSessionTransitionError: Error, Equatable, Sendable {
    case invalidTransition(from: RunSessionState, event: RunSessionEvent)

    public var code: String { "runsync.session.invalid_transition" }

    public var displayMessage: String {
        switch self {
        case let .invalidTransition(from, event):
            return "Action « \(event.rawValue) » impossible depuis l'état « \(from.rawValue) »."
        }
    }
}

/// Machine à états pure et testable de la session active.
///
/// Règles (partiellement T012, le coordinateur complet `RS-013` arrive en phase 2) :
/// - `start` depuis `idle` est autorisé (préparation implicite) et reste idempotent ;
/// - `start` depuis `running` ne fait rien (pas de seconde session) ;
/// - `pause` depuis `paused`, `resume` depuis `running` : idempotents ;
/// - `finish` est idempotent depuis tout état de course active, `finishing` ou `finished` ;
/// - `reset` ramène à `idle` depuis n'importe quel état.
public struct RunSessionStateMachine: Sendable, Equatable {
    public private(set) var state: RunSessionState
    public private(set) var appliedEventCount: Int

    public init(state: RunSessionState = .idle) {
        self.state = state
        self.appliedEventCount = 0
    }

    @discardableResult
    public mutating func apply(_ event: RunSessionEvent) throws -> RunSessionState {
        switch event {
        case .prepare:
            switch state {
            case .idle, .finished, .failed:
                state = .preparing
            case .preparing:
                break // idempotent
            case .running, .paused, .finishing:
                throw RunSessionTransitionError.invalidTransition(from: state, event: event)
            }

        case .start:
            switch state {
            case .idle, .preparing, .paused, .finished, .failed:
                state = .running
            case .running:
                break // idempotent : aucune seconde session
            case .finishing:
                throw RunSessionTransitionError.invalidTransition(from: state, event: event)
            }

        case .pause:
            switch state {
            case .running:
                state = .paused
            case .paused:
                break // idempotent
            case .idle, .preparing, .finishing, .finished, .failed:
                throw RunSessionTransitionError.invalidTransition(from: state, event: event)
            }

        case .resume:
            switch state {
            case .paused:
                state = .running
            case .running:
                break // idempotent
            case .idle, .preparing, .finishing, .finished, .failed:
                throw RunSessionTransitionError.invalidTransition(from: state, event: event)
            }

        case .beginFinishing:
            switch state {
            case .preparing, .running, .paused:
                state = .finishing
            case .finishing:
                break // idempotent
            case .idle, .finished, .failed:
                throw RunSessionTransitionError.invalidTransition(from: state, event: event)
            }

        case .finish:
            switch state {
            case .preparing, .running, .paused, .finishing, .finished:
                state = .finished
            case .failed:
                state = .finished
            case .idle:
                throw RunSessionTransitionError.invalidTransition(from: state, event: event)
            }

        case .fail:
            switch state {
            case .preparing, .running, .paused, .finishing:
                state = .failed
            case .failed:
                break // idempotent
            case .idle, .finished:
                throw RunSessionTransitionError.invalidTransition(from: state, event: event)
            }

        case .reset:
            state = .idle
        }

        appliedEventCount += 1
        return state
    }

    /// Nombre de fois où l'événement a réellement changé l'état. Permet aux tests
    /// et au diagnostic de vérifier qu'aucune double session n'a démarré (T012).
    @discardableResult
    public mutating func applyCountingTransitions(_ event: RunSessionEvent) throws -> Int {
        let previous = state
        try apply(event)
        return state == previous ? 0 : 1
    }
}
