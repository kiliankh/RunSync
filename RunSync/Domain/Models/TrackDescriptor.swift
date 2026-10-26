import Foundation

/// Provenance du BPM : la priorité va au BPM manuel, puis aux métadonnées
/// licites, puis seulement à une analyse locale dont la confiance est affichée
/// (FR-007, §08). Aucune valeur n'est inventée.
public enum BPMProvenance: String, Codable, Sendable, CaseIterable, Equatable {
    /// Saisi par l'utilisateur — priorité absolue, toujours fiable pour nous.
    case manual
    /// Métadonnées fournies licitement par le fichier ou le fournisseur.
    case provided
    /// Estimation produite par l'analyseur local offline (score de confiance requis).
    case analyzed
    /// Aucun BPM connu : le morceau n'est pas présenté comme synchronisable.
    case unknown

    public var displayName: String {
        switch self {
        case .manual: return "BPM manuel"
        case .provided: return "BPM des métadonnées"
        case .analyzed: return "BPM estimé"
        case .unknown: return "BPM inconnu"
        }
    }
}

/// Morceau du catalogue local, indépendant de toute bibliothèque tierce (§07).
public struct TrackDescriptor: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let artist: String?
    /// BPM nominal mesuré/connu. `nil` = BPM inconnu : aucune synchronisation prétendue.
    public let nominalBPM: Double?
    public let bpmProvenance: BPMProvenance
    /// Confiance de l'estimation dans `0...1` quand `bpmProvenance == .analyzed`.
    public let bpmConfidence: Double?
    public let durationSeconds: Double?
    /// Identifiant du fournisseur (ex. `local.importedFiles`). Jamais un SDK ici.
    public let providerID: String
    /// Le droit d'adapter ce morceau est établi pour ce morceau (fichier importé
    /// par l'utilisateur avec attestation, §02). Capacité technique *et* légitimité.
    public let canAlterTempo: Bool
    /// Le fichier est-il encore présent dans la sandbox ? Un fichier supprimé ne
    /// doit pas rester faussement jouable (§09, FR-006, T014).
    public let isFileAvailable: Bool
    /// Attestation utilisateur : le fichier a été importé légalement et son
    /// adaptation est autorisée pour un usage personnel.
    public let isAdaptationRightsAttested: Bool
    /// Chemin **relatif** à la racine d'import de la sandbox. Jamais un chemin
    /// absolu : aucun emplacement privé ne doit être journalisé ou persisté (§14).
    public let relativePath: String?
    public let fileSizeBytes: Int64?
    public let importedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        artist: String? = nil,
        nominalBPM: Double? = nil,
        bpmProvenance: BPMProvenance = .unknown,
        bpmConfidence: Double? = nil,
        durationSeconds: Double? = nil,
        providerID: String,
        canAlterTempo: Bool,
        isFileAvailable: Bool = true,
        isAdaptationRightsAttested: Bool = false,
        relativePath: String? = nil,
        fileSizeBytes: Int64? = nil,
        importedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.nominalBPM = nominalBPM
        self.bpmProvenance = bpmProvenance
        self.bpmConfidence = bpmConfidence
        self.durationSeconds = durationSeconds
        self.providerID = providerID
        self.canAlterTempo = canAlterTempo
        self.isFileAvailable = isFileAvailable
        self.isAdaptationRightsAttested = isAdaptationRightsAttested
        self.relativePath = relativePath
        self.fileSizeBytes = fileSizeBytes
        self.importedAt = importedAt
    }

    /// Renseigne un BPM saisi par l'utilisateur (priorité FR-007).
    ///
    /// Une valeur absente, non finie ou non positive est refusée par une erreur
    /// typée plutôt qu'acceptée puis utilisée dans un calcul : un BPM faux
    /// produirait un tempo faux (T011).
    public func settingManualBPM(_ bpm: Double?) throws -> TrackDescriptor {
        guard let bpm else { return self }
        guard bpm.isFinite, bpm > 0 else { throw TrackMetadataError.invalidBPM(bpm) }
        return TrackDescriptor(
            id: id,
            title: title,
            artist: artist,
            nominalBPM: bpm,
            bpmProvenance: .manual,
            bpmConfidence: 1.0,
            durationSeconds: durationSeconds,
            providerID: providerID,
            canAlterTempo: canAlterTempo,
            isFileAvailable: isFileAvailable,
            isAdaptationRightsAttested: isAdaptationRightsAttested,
            relativePath: relativePath,
            fileSizeBytes: fileSizeBytes,
            importedAt: importedAt
        )
    }

    /// BPM exploitable pour un calcul de ratio : présent, fini et strictement positif.
    public var hasUsableNominalBPM: Bool {
        guard let nominalBPM else { return false }
        return nominalBPM.isFinite && nominalBPM > 0
    }

    /// Ce morceau peut-il être proposé comme tempo-ajustable ? Les trois conditions
    /// doivent être vraies ; sinon l'UI ne doit afficher aucune option trompeuse (§02).
    public var isTempoAdjustable: Bool {
        canAlterTempo && isFileAvailable && hasUsableNominalBPM
    }
}
