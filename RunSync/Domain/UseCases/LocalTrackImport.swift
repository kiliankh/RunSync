import Foundation

/// Politique d'import des fichiers locaux (FR-006, RS-020).
public struct LocalImportPolicy: Sendable, Equatable {

    /// Extensions acceptées.
    ///
    /// ⚠️ Cette liste est une **hypothèse à vérifier sur appareil** : la prise en
    /// charge réelle d'un format dépend d'AVFoundation et doit être testée sur
    /// iPhone (RS-020). En cas de doute, un format est refusé plutôt qu'importé
    /// dans un état inutilisable. FLAC est volontairement exclu tant que la
    /// compatibilité n'a pas été démontrée.
    public static let defaultAcceptedExtensions: Set<String> = [
        "m4a", "mp3", "wav", "aif", "aiff", "caf", "aac", "mp4"
    ]

    public var acceptedExtensions: Set<String>
    /// Taille maximale d'un fichier importé (200 Mo par défaut).
    public var maximumFileSizeBytes: Int64
    /// Marge d'espace libre à conserver au-delà de la taille du fichier (50 Mo).
    public var freeSpaceMarginBytes: Int64

    public static let standard = LocalImportPolicy()

    public init(
        acceptedExtensions: Set<String> = LocalImportPolicy.defaultAcceptedExtensions,
        maximumFileSizeBytes: Int64 = 200 * 1024 * 1024,
        freeSpaceMarginBytes: Int64 = 50 * 1024 * 1024
    ) {
        self.acceptedExtensions = acceptedExtensions
        self.maximumFileSizeBytes = maximumFileSizeBytes
        self.freeSpaceMarginBytes = freeSpaceMarginBytes
    }

    public var isValid: Bool {
        !acceptedExtensions.isEmpty && maximumFileSizeBytes > 0 && freeSpaceMarginBytes >= 0
    }
}

/// Demande d'import. `userAttestsAdaptationRights` porte la déclaration de
/// l'utilisateur : sans elle, le morceau est importé mais **jamais** présenté
/// comme tempo-ajustable (§02 : seuls les fichiers dont le droit d'adaptation
/// est établi sont traités).
public struct LocalImportRequest: Sendable, Equatable {
    public let sourceURL: URL
    public let declaredTitle: String?
    public let declaredArtist: String?
    public let userAttestsAdaptationRights: Bool
    public let identifier: UUID

    public init(
        sourceURL: URL,
        declaredTitle: String? = nil,
        declaredArtist: String? = nil,
        userAttestsAdaptationRights: Bool,
        identifier: UUID = UUID()
    ) {
        self.sourceURL = sourceURL
        self.declaredTitle = declaredTitle
        self.declaredArtist = declaredArtist
        self.userAttestsAdaptationRights = userAttestsAdaptationRights
        self.identifier = identifier
    }
}

/// Import d'un fichier audio local dans la sandbox privée de l'application.
///
/// Le cas d'usage est **pur** : il ne connaît ni `UIDocumentPicker`, ni
/// security-scoped URL (ce sont les responsabilités de l'adaptateur iOS), et il
/// travaille sur une abstraction disque, ce qui permet de tester réellement les
/// erreurs de format, de taille, d'espace, d'accès et de fichier disparu (T014).
public struct LocalTrackImporter: Sendable {
    public let storage: TrackFileStorage
    public let policy: LocalImportPolicy
    private let clock: @Sendable () -> Date

    public init(
        storage: TrackFileStorage,
        policy: LocalImportPolicy = .standard,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.storage = storage
        self.policy = policy
        self.clock = now
    }

    /// Vérifie tout ce qui peut l'être **avant** de copier quoi que ce soit :
    /// l'interface peut ainsi refuser un fichier sans effet de bord.
    public func validate(_ request: LocalImportRequest) throws {
        guard policy.isValid else { throw TrackImportError.notImplementedInCurrentPhase }
        let fileExtension = request.sourceURL.pathExtension.lowercased()
        guard !fileExtension.isEmpty, policy.acceptedExtensions.contains(fileExtension) else {
            throw TrackImportError.unsupportedFormat(
                fileExtension.isEmpty ? "sans extension" : fileExtension
            )
        }
        guard let size = try storage.sizeOfFile(at: request.sourceURL), size > 0 else {
            throw TrackImportError.sourceFileUnreadable
        }
        guard size <= policy.maximumFileSizeBytes else {
            throw TrackImportError.fileTooLarge(
                sizeBytes: size,
                maximumBytes: policy.maximumFileSizeBytes
            )
        }
        if let available = try storage.availableCapacityBytes() {
            let required = size + policy.freeSpaceMarginBytes
            guard available >= required else {
                throw TrackImportError.insufficientStorage(
                    requiredBytes: required,
                    availableBytes: available
                )
            }
        }
    }

    /// Importe le fichier et retourne le descripteur correspondant.
    ///
    /// Le BPM n'est pas deviné : le morceau entre dans la bibliothèque avec
    /// `bpmProvenance == .unknown` et un BPM `nil` (FR-007).
    public func importTrack(_ request: LocalImportRequest) throws -> TrackDescriptor {
        try validate(request)
        let fileExtension = request.sourceURL.pathExtension.lowercased()
        let fileName = "\(request.identifier.uuidString).\(fileExtension)"
        let stored = try storage.storeCopy(from: request.sourceURL, suggestedFileName: fileName)

        return TrackDescriptor(
            id: request.identifier,
            title: Self.displayTitle(for: request),
            artist: request.declaredArtist?.trimmingCharacters(in: .whitespacesAndNewlines),
            nominalBPM: nil,
            bpmProvenance: .unknown,
            bpmConfidence: nil,
            durationSeconds: nil,
            providerID: ProviderCatalog.localImportedFiles.id,
            canAlterTempo: request.userAttestsAdaptationRights,
            isFileAvailable: true,
            isAdaptationRightsAttested: request.userAttestsAdaptationRights,
            relativePath: stored.relativePath,
            fileSizeBytes: stored.sizeBytes,
            importedAt: clock()
        )
    }

    private static func displayTitle(for request: LocalImportRequest) -> String {
        if let declared = request.declaredTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !declared.isEmpty {
            return declared
        }
        let fromFileName = request.sourceURL.deletingPathExtension().lastPathComponent
        return fromFileName.isEmpty ? "Morceau importé" : fromFileName
    }
}
