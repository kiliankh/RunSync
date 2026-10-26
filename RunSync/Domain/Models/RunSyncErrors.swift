import Foundation

/// Erreurs typées du Domain (§07). Chaque erreur expose un code stable destiné au
/// diagnostic et un message utilisateur. Aucun token, aucune URL privée, aucun
/// chemin de fichier privé ne doit figurer dans un log (§14).
public enum TempoPolicyError: Error, Equatable, Sendable {
    /// La limite d'ajustement doit rester dans une plage réaliste (FR-009 : ±5 % par défaut).
    case maxAdjustmentOutOfRange(Double)
    /// Seuls les ratios 1:1 et 2:1 sont validés par la spec ; en ajouter exige une
    /// validation UX préalable (§05).
    case unsupportedStepsPerBeat([Int])

    public var code: String { "runsync.tempo.policy" }

    public var displayMessage: String {
        switch self {
        case let .maxAdjustmentOutOfRange(value):
            return "Limite d'ajustement invalide (\(value))."
        case let .unsupportedStepsPerBeat(ratios):
            return "Ratios de synchronisation non validés : \(ratios)."
        }
    }
}

/// Erreurs de la garde d'ajustement tempo : la capacité technique ne suffit pas,
/// le droit d'adapter le flux est vérifié séparément (§02, T013).
public enum TempoAdjustmentError: Error, Equatable, Sendable {
    case providerNotPermitted(providerID: String)
    case trackFileUnavailable(trackID: UUID)
    case adaptationRightsNotAttested(trackID: UUID)
    case nominalBPMUnavailable(trackID: UUID)
    case invalidRequestedRate(Double)

    public var code: String { "runsync.tempo.adjustment" }

    public var displayMessage: String {
        switch self {
        case let .providerNotPermitted(providerID):
            return "La source « \(providerID) » n'autorise pas l'adaptation du tempo."
        case .trackFileUnavailable:
            return "Le fichier de ce morceau n'est plus disponible."
        case .adaptationRightsNotAttested:
            return "Le droit d'adapter ce fichier n'est pas attesté."
        case .nominalBPMUnavailable:
            return "Ce morceau n'a pas de BPM exploitable."
        case let .invalidRequestedRate(rate):
            return "Taux d'adaptation invalide (\(rate))."
        }
    }
}

/// Erreurs de lecture audio (§07).
///
/// Aucune erreur ne contient de chemin de fichier ni de donnée sensible : seuls
/// un code stable et un message utilisateur (§14).
public enum AudioPlaybackError: Error, Equatable, Sendable {
    /// Le lecteur est volontairement inactif (course sans audio) ou indisponible
    /// dans cette configuration.
    case playbackUnavailable(reason: String)
    case trackNotPrepared(trackID: UUID)
    case rateAdjustmentNotPermitted(trackID: UUID)
    /// Le fichier existe mais ne peut pas être ouvert par le moteur audio
    /// (format non pris en charge, fichier corrompu, droits de lecture absents).
    case trackFileUnreadable(trackID: UUID)
    /// La garde de conformité a refusé la demande. On conserve l'erreur d'origine
    /// (`TempoAdjustmentError`) plutôt que de l'aplatir en un message : la cause
    /// exacte (attestation absente, source non autorisée, BPM manquant) doit rester
    /// affichable telle quelle.
    case tempoAdjustmentRefused(TempoAdjustmentError)
    case underlying(code: String)

    public var code: String { "runsync.audio.playback" }

    public var displayMessage: String {
        switch self {
        case let .playbackUnavailable(reason):
            return "Lecture audio indisponible : \(reason)."
        case .trackNotPrepared:
            return "Aucun morceau n'est préparé pour la lecture."
        case .rateAdjustmentNotPermitted:
            return "Ce morceau ne peut pas voir son tempo ajusté."
        case .trackFileUnreadable:
            return "Ce fichier audio ne peut pas être lu (format non pris en charge ou fichier altéré)."
        case let .tempoAdjustmentRefused(error):
            return error.displayMessage
        case let .underlying(code):
            return "Erreur audio (\(code))."
        }
    }
}

/// Erreurs d'import de fichier local (FR-006, RS-020).
///
/// Aucun message ne contient de chemin de fichier : les URLs de documents de
/// l'utilisateur ne doivent jamais se retrouver dans un log ni dans une capture
/// d'écran (§14).
public enum TrackImportError: Error, Equatable, Sendable {
    case notImplementedInCurrentPhase
    case unsupportedFormat(String)
    case sourceFileUnreadable
    case fileTooLarge(sizeBytes: Int64, maximumBytes: Int64)
    case insufficientStorage(requiredBytes: Int64, availableBytes: Int64)
    case invalidFileName
    case accessDenied
    case storageUnavailable

    public var code: String { "runsync.track.import" }

    public var displayMessage: String {
        switch self {
        case .notImplementedInCurrentPhase:
            return "Import de fichiers non disponible dans cette phase."
        case let .unsupportedFormat(extensionName):
            return "Format non pris en charge (\(extensionName))."
        case .sourceFileUnreadable:
            return "Le fichier sélectionné est illisible ou a été déplacé."
        case let .fileTooLarge(sizeBytes, maximumBytes):
            let size = ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
            let maximum = ByteCountFormatter.string(fromByteCount: maximumBytes, countStyle: .file)
            return "Fichier trop volumineux (\(size) pour une limite de \(maximum))."
        case let .insufficientStorage(requiredBytes, availableBytes):
            let required = ByteCountFormatter.string(fromByteCount: requiredBytes, countStyle: .file)
            let available = ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file)
            return "Espace insuffisant : \(required) requis, \(available) disponibles."
        case .invalidFileName:
            return "Nom de fichier refusé : l'emplacement de destination est invalide."
        case .accessDenied:
            return "Accès au fichier refusé."
        case .storageUnavailable:
            return "Espace de stockage indisponible pour importer ce fichier."
        }
    }
}

/// Erreurs des sources de cadence (FR-003, RS-010).
///
/// La distinction compte : un appareil sans capteur et une autorisation refusée
/// demandent deux réactions différentes (mode démo ou retour vers les réglages),
/// et aucune ne doit produire une cadence inventée.
public enum CadenceSourceError: Error, Equatable, Sendable {
    case cadenceNotAvailableOnDevice
    case motionPermissionDenied
    case coreMotionFailure(code: Int)

    public var code: String { "runsync.cadence.source" }

    public var displayMessage: String {
        switch self {
        case .cadenceNotAvailableOnDevice:
            return "Cet appareil ne fournit pas de cadence de pas. Utilisez le scénario simulé."
        case .motionPermissionDenied:
            return "Accès à l'activité physique refusé : autorisez « Mouvement et forme » dans Réglages."
        case let .coreMotionFailure(code):
            return "Capteur de mouvement indisponible (code \(code))."
        }
    }
}

/// Erreurs de métadonnées de morceau (FR-007).
public enum TrackMetadataError: Error, Equatable, Sendable {
    case invalidBPM(Double)

    public var code: String { "runsync.track.metadata" }

    public var displayMessage: String {
        switch self {
        case let .invalidBPM(value):
            return "BPM invalide (\(value)) : une valeur strictement positive est attendue."
        }
    }
}
