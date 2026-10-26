import CoreMotion
import Foundation
import RunSyncDomain

/// Disponibilité du capteur de cadence (FR-003, RS-010).
///
/// Ce diagnostic est **affiché** : l'utilisateur doit savoir si sa cadence vient
/// d'un capteur réel, d'un scénario simulé, ou de rien du tout. Le simulateur iOS
/// ne fournit jamais de cadence : c'est le premier piège du projet.
public enum CadenceSensorAvailability: Equatable, Sendable {
    /// Capteur présent et autorisé.
    case available
    /// Appareil sans coprocesseur de mouvement exploitable (dont le simulateur).
    case deviceWithoutCadence
    /// Autorisation « Mouvement et forme » refusée ou restreinte.
    case permissionDenied
    /// Autorisation pas encore demandée : `startUpdates` déclenchera la demande.
    case permissionNotDetermined

    public var canRun: Bool { self == .available }

    public var displayMessage: String {
        switch self {
        case .available:
            return "Capteur de cadence disponible."
        case .deviceWithoutCadence:
            return "Aucune cadence sur cet appareil (le simulateur n'en fournit jamais) : scénario simulé requis."
        case .permissionDenied:
            return "Accès à l'activité physique refusé. Autorisez « Mouvement et forme » dans Réglages → RunSync."
        case .permissionNotDetermined:
            return "L'autorisation « Mouvement et forme » sera demandée au démarrage de la course."
        }
    }
}

/// Source de cadence réelle : `CMPedometer` (FR-003, RS-010).
///
/// Choix d'implémentation documentés :
/// - `startUpdates(from:withHandler:)` est la seule API d'écoulement de la
///   cadence (il n'existe pas de variante dédiée à la cadence) ;
/// - `CMPedometerData.currentCadence` est en **pas par seconde** et peut être
///   `nil`. La conversion passe par `CadenceSample.fromStepsPerSecond`, qui
///   produit un échantillon `unavailable` plutôt qu'un `0` inventé (cas D du §05) ;
/// - l'horodatage utilisé est `data.endDate`, c'est-à-dire la fin de la période
///   effectivement mesurée, et non l'instant de réception du callback : le filtre
///   et les statistiques raisonnent ainsi sur des durées réelles ;
/// - la fréquence des callbacks n'est pas documentée par Apple et peut varier
///   (y compris des secondes sans mise à jour). Le filtre du noyau traite une
///   mesure périmée comme `degraded` puis `unavailable` : aucune cadence n'est
///   extrapolée entre deux appels ;
/// - `CMPedometer` est manipulé depuis n'importe quel fil ; le seul état partagé
///   ici est protégé par un verrou, ce qui évite de dépendre de l'isolation d'un
///   acteur pour une classe dont les méthodes sont synchrones.
public final class CoreMotionCadenceSource: CadenceSource, @unchecked Sendable {

    /// Identifiant de source, journalisé dans les diagnostics (jamais de donnée
    /// personnelle).
    public static let sourceIdentifier = "coremotion.pedometer"

    private let lock = NSLock()
    private var activePedometer: CMPedometer?
    private let startDate: Date

    public init(startDate: Date = Date()) {
        self.startDate = startDate
    }

    /// État du capteur, sans démarrer de mesure. Utilisé par les réglages et par
    /// l'écran de session pour annoncer une dégradation avant qu'elle ne surprenne
    /// l'utilisateur.
    public static var availability: CadenceSensorAvailability {
        guard CMPedometer.isCadenceAvailable() else { return .deviceWithoutCadence }
        switch CMPedometer.authorizationStatus() {
        case .authorized:
            return .available
        case .denied, .restricted:
            return .permissionDenied
        case .notDetermined:
            return .permissionNotDetermined
        @unknown default:
            return .permissionNotDetermined
        }
    }

    public func samples() -> AsyncThrowingStream<CadenceSample, Error> {
        let startDate = self.startDate
        return AsyncThrowingStream { continuation in
            let availability = Self.availability
            guard availability != .deviceWithoutCadence else {
                continuation.finish(throwing: CadenceSourceError.cadenceNotAvailableOnDevice)
                return
            }
            guard availability != .permissionDenied else {
                continuation.finish(throwing: CadenceSourceError.motionPermissionDenied)
                return
            }

            let pedometer = CMPedometer()
            setActive(pedometer)
            continuation.onTermination = { [weak self] _ in
                self?.stopActivePedometer()
            }

            pedometer.startUpdates(from: startDate) { data, error in
                if let error {
                    continuation.finish(throwing: Self.mapped(error))
                    return
                }
                guard let data else { return }
                // `currentCadence` nil => échantillon explicitement indisponible.
                continuation.yield(
                    CadenceSample.fromStepsPerSecond(
                        data.currentCadence?.doubleValue,
                        timestamp: data.endDate,
                        sourceIdentifier: Self.sourceIdentifier
                    )
                )
            }
        }
    }

    /// Arrête explicitement la mesure (changement de source en cours de session).
    public func stop() {
        stopActivePedometer()
    }

    // MARK: - État partagé

    private func setActive(_ pedometer: CMPedometer) {
        lock.lock()
        defer { lock.unlock() }
        activePedometer?.stopUpdates()
        activePedometer = pedometer
    }

    private func stopActivePedometer() {
        lock.lock()
        defer { lock.unlock() }
        activePedometer?.stopUpdates()
        activePedometer = nil
    }

    private static func mapped(_ error: Error) -> CadenceSourceError {
        let nsError = error as NSError
        guard nsError.domain == CMErrorDomain else {
            return .coreMotionFailure(code: nsError.code)
        }
        if nsError.code == Int(CMErrorMotionActivityNotAuthorized.rawValue) {
            return .motionPermissionDenied
        }
        if nsError.code == Int(CMErrorMotionActivityNotAvailable.rawValue) {
            return .cadenceNotAvailableOnDevice
        }
        return .coreMotionFailure(code: nsError.code)
    }
}
