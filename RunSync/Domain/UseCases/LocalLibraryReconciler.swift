import Foundation

/// Résultat d'une réconciliation de bibliothèque.
public struct LibraryReconciliationResult: Sendable, Equatable {
    /// Morceaux avec `isFileAvailable` remis à jour.
    public let tracks: [TrackDescriptor]
    /// Morceaux dont le fichier a disparu : ils doivent être signalés, pas joués (§09).
    public let missingTrackIDs: [UUID]

    public init(tracks: [TrackDescriptor], missingTrackIDs: [UUID]) {
        self.tracks = tracks
        self.missingTrackIDs = missingTrackIDs
    }
}

/// Vérifie que chaque morceau de la bibliothèque possède encore son fichier.
///
/// « La suppression du fichier importé ne doit pas laisser d'élément faussement
/// jouable » (§09, T014) : un morceau dont le fichier a disparu passe à
/// `isFileAvailable == false`, ce qui le fait rejeter par `TempoMatcher`
/// (`TempoRejection.fileUnavailable`) et par `TempoAdjustmentGate`.
///
/// Les morceaux sans fichier local (démonstration) ne sont pas modifiés : leur
/// disponibilité ne dépend pas du disque.
public struct LocalLibraryReconciler: Sendable {
    public let storage: TrackFileStorage

    public init(storage: TrackFileStorage) {
        self.storage = storage
    }

    public func reconcile(_ tracks: [TrackDescriptor]) -> LibraryReconciliationResult {
        var updated: [TrackDescriptor] = []
        var missing: [UUID] = []
        updated.reserveCapacity(tracks.count)

        for track in tracks {
            guard let relativePath = track.relativePath else {
                updated.append(track)
                continue
            }
            let exists = (try? storage.fileExists(relativePath: relativePath)) ?? false
            if exists {
                updated.append(track)
            } else {
                missing.append(track.id)
                updated.append(Self.markingUnavailable(track))
            }
        }
        return LibraryReconciliationResult(tracks: updated, missingTrackIDs: missing)
    }

    /// Copie le descripteur en le marquant indisponible, **sans** effacer le BPM
    /// ni le titre : l'utilisateur doit voir ce qui a disparu, pas un morceau vide.
    static func markingUnavailable(_ track: TrackDescriptor) -> TrackDescriptor {
        TrackDescriptor(
            id: track.id,
            title: track.title,
            artist: track.artist,
            nominalBPM: track.nominalBPM,
            bpmProvenance: track.bpmProvenance,
            bpmConfidence: track.bpmConfidence,
            durationSeconds: track.durationSeconds,
            providerID: track.providerID,
            canAlterTempo: track.canAlterTempo,
            isFileAvailable: false,
            isAdaptationRightsAttested: track.isAdaptationRightsAttested,
            relativePath: track.relativePath,
            fileSizeBytes: track.fileSizeBytes,
            importedAt: track.importedAt
        )
    }
}
