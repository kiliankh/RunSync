import Foundation
import RunSyncDomain

/// Faux stockage enregistreur : il permet de vérifier qu'un import invalide
/// **n'écrit rien** et de provoquer chaque erreur typée de façon déterministe.
/// Utilisé uniquement dans les tests (état mutable, accès mono-thread).
final class RecordingTrackFileStorage: TrackFileStorage, @unchecked Sendable {
    var capacityBytes: Int64? = 4 * 1024 * 1024 * 1024
    var sourceSizes: [String: Int64] = [:]
    var storedFiles: [String: Int64] = [:]
    var copyError: TrackImportError?
    var removeError: TrackImportError?

    private(set) var storeCopyCallCount = 0
    private(set) var removeCallCount = 0

    init() {}

    func registerSource(_ url: URL, sizeBytes: Int64) {
        sourceSizes[url.lastPathComponent] = sizeBytes
    }

    func availableCapacityBytes() throws -> Int64? {
        capacityBytes
    }

    func sizeOfFile(at url: URL) throws -> Int64? {
        sourceSizes[url.lastPathComponent]
    }

    func storeCopy(from url: URL, suggestedFileName: String) throws -> StoredFileReference {
        storeCopyCallCount += 1
        if let copyError { throw copyError }
        let size = sourceSizes[url.lastPathComponent] ?? 1024
        storedFiles[suggestedFileName] = size
        return StoredFileReference(relativePath: suggestedFileName, sizeBytes: size)
    }

    func removeFile(relativePath: String) throws {
        removeCallCount += 1
        if let removeError { throw removeError }
        storedFiles[relativePath] = nil
    }

    func fileExists(relativePath: String) throws -> Bool {
        storedFiles[relativePath] != nil
    }
}
