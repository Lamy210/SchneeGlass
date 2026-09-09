import Foundation
import SchneeGlassDomain

public enum ConfigurationPersistenceError: Error, Hashable, Sendable {
    case corruptCurrent
    case unsupportedSchemaVersion(Int)
    case unsafeStorageTopology
    case invalidBackupIdentifier
    case backupNotFound
    case corruptBackup
}

public struct ConfigurationBackupDescriptor: Hashable, Sendable, Identifiable {
    public let id: String
    public let createdAt: Date

    public init(id: String, createdAt: Date) {
        self.id = id
        self.createdAt = createdAt
    }
}

public protocol ConfigurationRecoveryProviding: Sendable {
    func availableBackups() async throws -> [ConfigurationBackupDescriptor]
    func restoreBackup(id: String) async throws -> [GlassConfiguration]
}
