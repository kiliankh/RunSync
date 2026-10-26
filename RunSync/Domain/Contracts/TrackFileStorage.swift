import Foundation

/// Fichier stocké dans la sandbox d'import, décrit par un chemin **relatif**.
///
/// Un chemin relatif est utilisé partout hors de la couche disque : aucune
/// position absolue de la sandbox ne doit se retrouver dans un modèle, un log
/// ou un snapshot (§14).
public struct StoredFileReference: Sendable, Equatable {
    public let relativePath: String
    public let sizeBytes: Int64

    public init(relativePath: String, sizeBytes: Int64) {
        self.relativePath = relativePath
        self.sizeBytes = sizeBytes
    }
}

/// Accès disque pour les fichiers audio importés.
///
/// Contrat volontairement pauvre et synchrone (l'adaptateur `FileManager` est
/// synchrone) : c'est la couche qui décide des chemins, pas le Domain. Toute
/// implémentation doit rester confinée à un répertoire privé de l'application.
public protocol TrackFileStorage: Sendable {
    /// Espace disponible en octets, si le système le communique.
    func availableCapacityBytes() throws -> Int64?

    /// Taille d'un fichier source **avant** import, `nil` s'il est illisible ou absent.
    func sizeOfFile(at url: URL) throws -> Int64?

    /// Copie le fichier source dans la sandbox d'import.
    /// - Parameter suggestedFileName: nom de destination, relatif au répertoire d'import.
    func storeCopy(from url: URL, suggestedFileName: String) throws -> StoredFileReference

    func removeFile(relativePath: String) throws

    func fileExists(relativePath: String) throws -> Bool
}
