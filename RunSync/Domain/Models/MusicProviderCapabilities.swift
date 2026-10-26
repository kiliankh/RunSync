import Foundation

/// Statut d'une revue technique/juridique de fournisseur (§02).
/// Règle de feature gating : une capacité non confirmée est **désactivée**.
public enum ComplianceStatus: String, Codable, Sendable, CaseIterable, Equatable {
    /// Revue effectivement réalisée à la date indiquée, décision GO documentée.
    case confirmed
    /// Revue non réalisée ou non actualisée : fonctionnalité désactivée.
    case underReview
    /// Usage interdit : la fonctionnalité ne doit pas exister dans l'application.
    case prohibited

    public var displayName: String {
        switch self {
        case .confirmed: return "Conformité confirmée"
        case .underReview: return "À vérifier"
        case .prohibited: return "Non autorisé"
        }
    }
}

/// Trace de la revue d'un fournisseur : date, sources officielles, décision (§02).
public struct ProviderComplianceRecord: Sendable, Equatable {
    public let status: ComplianceStatus
    /// Date de la dernière vérification réelle. `nil` si rien n'a été vérifié :
    /// c'est le cas de tous les fournisseurs tiers dans cette phase.
    public let reviewedAt: Date?
    /// URLs officielles à recontrôler à la date d'implémentation.
    public let sourceURLs: [String]
    public let notes: String

    public init(
        status: ComplianceStatus,
        reviewedAt: Date? = nil,
        sourceURLs: [String] = [],
        notes: String
    ) {
        self.status = status
        self.reviewedAt = reviewedAt
        self.sourceURLs = sourceURLs
        self.notes = notes
    }
}

/// Capacités déclarées par un fournisseur musical (§02, §07).
///
/// Principe non négociable : les métadonnées/commandes de lecture et l'accès au
/// flux PCM sont **deux capacités distinctes**, et disposer de l'une ne donne
/// jamais le droit d'altérer un flux. La capacité d'adaptation du tempo exige en
/// plus une revue de conformité `confirmed`.
public struct MusicProviderCapabilities: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    /// Peut lister un catalogue de morceaux.
    public let canBrowseCatalog: Bool
    /// Peut contrôler la lecture (play/pause/next).
    public let canControlPlayback: Bool
    /// Capacité **technique** déclarée par l'adaptateur d'ajuster le tempo.
    public let canAdjustTempo: Bool
    /// Accès au flux PCM (nécessaire à un traitement audio local).
    public let canAccessPCM: Bool
    /// Nécessite une connexion réseau (dégrade explicitement le mode hors ligne, FR-020).
    public let requiresNetwork: Bool
    public let compliance: ProviderComplianceRecord

    public init(
        id: String,
        displayName: String,
        canBrowseCatalog: Bool,
        canControlPlayback: Bool,
        canAdjustTempo: Bool,
        canAccessPCM: Bool,
        requiresNetwork: Bool,
        compliance: ProviderComplianceRecord
    ) {
        self.id = id
        self.displayName = displayName
        self.canBrowseCatalog = canBrowseCatalog
        self.canControlPlayback = canControlPlayback
        self.canAdjustTempo = canAdjustTempo
        self.canAccessPCM = canAccessPCM
        self.requiresNetwork = requiresNetwork
        self.compliance = compliance
    }

    /// Garde unique utilisée par l'UI et par le moteur audio : capacité technique
    /// **et** conformité confirmée. Tant que la revue n'est pas faite, c'est faux.
    public var isTempoAdjustmentPermitted: Bool {
        canAdjustTempo && compliance.status == .confirmed
    }
}

/// Catalogue de fournisseurs déclarés dans cette phase.
///
/// ⚠️ Les entrées tierces reproduisent l'état du cahier des charges §02 et sont
/// marquées `underReview`/`prohibited` : **aucune n'a été vérifiée par l'agent à
/// une source officielle**. Elles doivent être recontrôlées avant toute
/// implémentation (Docs/PROVIDER_COMPLIANCE.md).
public enum ProviderCatalog {
    public static let localImportedFiles = MusicProviderCapabilities(
        id: "local.importedFiles",
        displayName: "Fichiers locaux importés",
        canBrowseCatalog: true,
        canControlPlayback: true,
        canAdjustTempo: true,
        canAccessPCM: true,
        requiresNetwork: false,
        compliance: ProviderComplianceRecord(
            status: .confirmed,
            reviewedAt: nil,
            sourceURLs: [],
            notes: "Chemin MVP validé : fichiers de l'utilisateur importés légalement "
                + "dans la sandbox, droit d'adaptation attesté par l'utilisateur (§02, FR-006)."
        )
    )

    public static let appleMusic = MusicProviderCapabilities(
        id: "appleMusic",
        displayName: "Apple Music (MusicKit)",
        canBrowseCatalog: true,
        canControlPlayback: true,
        canAdjustTempo: false,
        canAccessPCM: false,
        requiresNetwork: true,
        compliance: ProviderComplianceRecord(
            status: .underReview,
            sourceURLs: ["https://developer.apple.com/documentation/musickit"],
            notes: "POC isolé uniquement (RS-041). `playbackRate` documenté n'équivaut pas à un "
                + "accès PCM ni à un time-stretch musical. Non vérifié par l'agent : à recontrôler."
        )
    )

    public static let spotify = MusicProviderCapabilities(
        id: "spotify",
        displayName: "Spotify",
        canBrowseCatalog: true,
        canControlPlayback: true,
        canAdjustTempo: false,
        canAccessPCM: false,
        requiresNetwork: true,
        compliance: ProviderComplianceRecord(
            status: .underReview,
            sourceURLs: [
                "https://developer.spotify.com/policy",
                "https://developer.spotify.com/documentation/ios/getting-started"
            ],
            notes: "Le SDK iOS n'expose pas de flux PCM et l'altération du contenu est proscrite "
                + "(§02). Adaptateur stub/mock uniquement, jamais présenté comme tempo-ajustable. "
                + "Non vérifié par l'agent : à recontrôler."
        )
    )

    public static let soundCloud = MusicProviderCapabilities(
        id: "soundCloud",
        displayName: "SoundCloud",
        canBrowseCatalog: false,
        canControlPlayback: false,
        canAdjustTempo: false,
        canAccessPCM: false,
        requiresNetwork: true,
        compliance: ProviderComplianceRecord(
            status: .underReview,
            notes: "Droits et disponibilité d'API non vérifiés (RS-043). Aucun accès PCM présumé."
        )
    )

    public static let youTube = MusicProviderCapabilities(
        id: "youTube",
        displayName: "YouTube / YouTube Music",
        canBrowseCatalog: false,
        canControlPlayback: false,
        canAdjustTempo: false,
        canAccessPCM: false,
        requiresNetwork: true,
        compliance: ProviderComplianceRecord(
            status: .prohibited,
            sourceURLs: ["https://developers.google.com/youtube/terms/developer-policies"],
            notes: "Isoler ou modifier l'audio des vidéos est interdit par les règles de l'API "
                + "(§02). Hors périmètre : aucun adaptateur de lecture caché."
        )
    )

    /// Tous les fournisseurs déclarés, le chemin local d'abord (MVP).
    public static let all: [MusicProviderCapabilities] = [
        localImportedFiles, appleMusic, spotify, soundCloud, youTube
    ]

    public static func provider(id: String) -> MusicProviderCapabilities? {
        all.first { $0.id == id }
    }
}
