import Foundation
import RunSyncDomain

/// Stockage disque réel des fichiers audio importés, confiné à un sous-répertoire
/// privé de l'application.
///
/// Le code est du Foundation pur : il s'exécute à l'identique sur iOS, macOS et
/// Linux, ce qui permet de tester **réellement** l'import (copie, taille, espace
/// disponible, suppression) sans simulateur ni appareil — la partie inaccessible
/// sans iOS (document picker, security-scoped URL) reste dans l'adaptateur de
/// l'application.
public struct FileSystemTrackStorage: TrackFileStorage {
    public let rootDirectory: URL
    public let importDirectoryName: String

    public init(rootDirectory: URL, importDirectoryName: String = "ImportedAudio") {
        self.rootDirectory = rootDirectory
        self.importDirectoryName = importDirectoryName
    }

    /// Répertoire où sont copiés les morceaux importés.
    public var importDirectory: URL {
        rootDirectory.appendingPathComponent(importDirectoryName, isDirectory: true)
    }

    /// URL absolue d'un fichier à partir de son chemin relatif (usage interne et UI).
    public func absoluteURL(forRelativePath relativePath: String) throws -> URL {
        try resolve(relativePath)
    }

    // MARK: - TrackFileStorage

    public func availableCapacityBytes() throws -> Int64? {
        // Si le système ne sait pas répondre, on retourne `nil` : l'import n'est pas
        // bloqué pour autant, la vérification de taille reste effectuée.
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: rootDirectory.path) else {
            return nil
        }
        return (attributes[.systemFreeSize] as? NSNumber)?.int64Value
    }

    public func sizeOfFile(at url: URL) throws -> Int64? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return nil }
        return (attributes[.size] as? NSNumber)?.int64Value
    }

    public func storeCopy(from url: URL, suggestedFileName: String) throws -> StoredFileReference {
        let fileName = try sanitizedFileName(suggestedFileName)
        let destination = importDirectory.appendingPathComponent(fileName)
        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(at: importDirectory, withIntermediateDirectories: true)
        } catch {
            throw TrackImportError.storageUnavailable
        }

        // Un import répété avec le même identifiant remplace le fichier précédent.
        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }

        do {
            try fileManager.copyItem(at: url, to: destination)
        } catch {
            throw Self.mapWriteError(error)
        }

        let size = (try? fileManager.attributesOfItem(atPath: destination.path))
            .flatMap { ($0[.size] as? NSNumber)?.int64Value } ?? 0
        guard size > 0 else {
            try? fileManager.removeItem(at: destination)
            throw TrackImportError.sourceFileUnreadable
        }
        return StoredFileReference(relativePath: fileName, sizeBytes: size)
    }

    public func removeFile(relativePath: String) throws {
        let url = try resolve(relativePath)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return } // idempotent
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw TrackImportError.accessDenied
        }
    }

    public func fileExists(relativePath: String) throws -> Bool {
        FileManager.default.fileExists(atPath: try resolve(relativePath).path)
    }

    // MARK: - Interne

    /// Refuse tout nom qui ne serait pas un simple nom de fichier : un chemin
    /// relatif remontant (`../`) ne doit jamais permettre d'écrire hors du
    /// répertoire d'import.
    private func sanitizedFileName(_ suggestedFileName: String) throws -> String {
        let trimmed = suggestedFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSafe = !trimmed.isEmpty
            && trimmed != "."
            && trimmed != ".."
            && !trimmed.contains("/")
            && !trimmed.contains("\\")
            && !trimmed.contains(":")
        guard isSafe else { throw TrackImportError.invalidFileName }
        return trimmed
    }

    private func resolve(_ relativePath: String) throws -> URL {
        importDirectory.appendingPathComponent(try sanitizedFileName(relativePath))
    }

    private static func mapWriteError(_ error: Error) -> TrackImportError {
        let code = (error as NSError).code
        switch code {
        case CocoaError.fileWriteOutOfSpace.rawValue:
            return .storageUnavailable
        case CocoaError.fileReadNoPermission.rawValue, CocoaError.fileWriteNoPermission.rawValue:
            return .accessDenied
        default:
            return .accessDenied
        }
    }
}
