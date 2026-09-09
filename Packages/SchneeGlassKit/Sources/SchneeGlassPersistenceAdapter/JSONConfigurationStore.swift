import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import SchneeGlassPOSIXSupport

public actor JSONConfigurationStore: ConfigurationPersisting, ConfigurationRecoveryProviding {
    public static let schemaVersion = 1
    public static let maximumBackupCount = 5

    private static let configurationDirectory = ["Configuration"]
    private static let backupDirectory = ["Configuration", "Backups"]
    private static let preservedDirectory = ["Configuration", "Preserved"]
    private static let configurationFilename = "config.json"

    private struct Envelope: Codable, Sendable {
        let schemaVersion: Int
        let glasses: [GlassConfiguration]
    }

    private enum DecodingFailure: Error {
        case corrupt
        case unsupportedSchema(Int)
    }

    private let stateStore: PhysicalStateStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseDirectory: URL) {
        self.stateStore = PhysicalStateStore(rootURL: baseDirectory.standardizedFileURL)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public func load() async throws -> [GlassConfiguration] {
        let data: Data
        do {
            guard let current = try stateStore.readRegularFile(
                in: Self.configurationDirectory,
                named: Self.configurationFilename
            ) else {
                return []
            }
            data = current
        } catch {
            throw Self.mapCurrentReadError(error)
        }

        do {
            return try decodeEnvelope(data).glasses
        } catch let failure as DecodingFailure {
            throw Self.mapCurrentFailure(failure)
        } catch {
            throw ConfigurationPersistenceError.corruptCurrent
        }
    }

    public func save(_ configurations: [GlassConfiguration]) async throws {
        let newData = try validatedEncodedData(configurations)

        let currentData: Data?
        do {
            currentData = try stateStore.readRegularFile(
                in: Self.configurationDirectory,
                named: Self.configurationFilename
            )
        } catch {
            throw Self.mapCurrentReadError(error)
        }

        if let currentData {
            do {
                _ = try decodeEnvelope(currentData)
            } catch let failure as DecodingFailure {
                throw Self.mapCurrentFailure(failure)
            } catch {
                throw ConfigurationPersistenceError.corruptCurrent
            }

            try writeBackup(data: currentData)
        }

        // Finish fallible backup housekeeping before replacing current state. The atomic rename in
        // PhysicalStateStore is the final fallible commit step for the visible configuration.
        try rotateBackups()
        do {
            try stateStore.writeAtomically(
                newData,
                in: Self.configurationDirectory,
                named: Self.configurationFilename
            )
        } catch {
            try Self.rethrowStorageMutation(error)
        }
    }

    public func availableBackups() async throws -> [ConfigurationBackupDescriptor] {
        let names: [String]
        do {
            names = try stateStore.regularFileNames(in: Self.backupDirectory)
        } catch {
            try Self.rethrowStorageMutation(error)
        }

        var descriptors: [ConfigurationBackupDescriptor] = []
        descriptors.reserveCapacity(names.count)

        for name in names where Self.isBackupFilename(name) {
            guard let createdAt = Self.backupCreatedAt(from: name) else {
                continue
            }

            do {
                guard let data = try stateStore.readRegularFile(
                    in: Self.backupDirectory,
                    named: name
                ) else {
                    continue
                }
                _ = try decodeEnvelope(data)
                descriptors.append(
                    ConfigurationBackupDescriptor(id: name, createdAt: createdAt)
                )
            } catch {
                // Corrupt, unreadable, replaced, or non-regular individual backups are not surfaced.
            }
        }

        return descriptors.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id > rhs.id
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    public func restoreBackup(id: String) async throws -> [GlassConfiguration] {
        guard Self.isBackupFilename(id),
              (id as NSString).lastPathComponent == id
        else {
            throw ConfigurationPersistenceError.invalidBackupIdentifier
        }

        let names: [String]
        do {
            names = try stateStore.regularFileNames(in: Self.backupDirectory)
        } catch {
            try Self.rethrowStorageMutation(error)
        }
        guard names.contains(id) else {
            throw ConfigurationPersistenceError.backupNotFound
        }

        let backupData: Data
        do {
            guard let data = try stateStore.readRegularFile(
                in: Self.backupDirectory,
                named: id
            ) else {
                throw ConfigurationPersistenceError.backupNotFound
            }
            backupData = data
        } catch let error as ConfigurationPersistenceError {
            throw error
        } catch {
            throw ConfigurationPersistenceError.corruptBackup
        }

        let backupEnvelope: Envelope
        do {
            backupEnvelope = try decodeEnvelope(backupData)
        } catch let failure as DecodingFailure {
            switch failure {
            case .corrupt:
                throw ConfigurationPersistenceError.corruptBackup
            case let .unsupportedSchema(version):
                throw ConfigurationPersistenceError.unsupportedSchemaVersion(version)
            }
        } catch {
            throw ConfigurationPersistenceError.corruptBackup
        }

        try preserveOrBackupCurrentBeforeExplicitRestore()
        try rotateBackups()
        do {
            try stateStore.writeAtomically(
                backupData,
                in: Self.configurationDirectory,
                named: Self.configurationFilename
            )
        } catch {
            try Self.rethrowStorageMutation(error)
        }
        return backupEnvelope.glasses
    }

    private func validatedEncodedData(_ configurations: [GlassConfiguration]) throws -> Data {
        let envelope = Envelope(
            schemaVersion: Self.schemaVersion,
            glasses: configurations
        )
        let data = try encoder.encode(envelope)
        _ = try decoder.decode(Envelope.self, from: data)
        return data
    }

    private func decodeEnvelope(_ data: Data) throws -> Envelope {
        let envelope: Envelope
        do {
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch {
            throw DecodingFailure.corrupt
        }

        guard envelope.schemaVersion == Self.schemaVersion else {
            throw DecodingFailure.unsupportedSchema(envelope.schemaVersion)
        }
        return envelope
    }

    private func writeBackup(data: Data) throws {
        do {
            try stateStore.writeAtomically(
                data,
                in: Self.backupDirectory,
                named: Self.makeBackupFilename(),
                replaceExisting: false
            )
        } catch {
            try Self.rethrowStorageMutation(error)
        }
    }

    private func preserveOrBackupCurrentBeforeExplicitRestore() throws {
        let currentData: Data
        do {
            guard let data = try stateStore.readRegularFile(
                in: Self.configurationDirectory,
                named: Self.configurationFilename
            ) else {
                return
            }
            currentData = data
        } catch {
            throw Self.mapCurrentReadError(error)
        }

        do {
            _ = try decodeEnvelope(currentData)
        } catch let failure as DecodingFailure {
            switch failure {
            case .corrupt:
                do {
                    try stateStore.writeAtomically(
                        currentData,
                        in: Self.preservedDirectory,
                        named: Self.makePreservedFilename(),
                        replaceExisting: false
                    )
                } catch {
                    try Self.rethrowStorageMutation(error)
                }
                return
            case let .unsupportedSchema(version):
                throw ConfigurationPersistenceError.unsupportedSchemaVersion(version)
            }
        } catch {
            throw ConfigurationPersistenceError.corruptCurrent
        }

        try writeBackup(data: currentData)
    }

    private func rotateBackups() throws {
        let names: [String]
        do {
            names = try stateStore.regularFileNames(in: Self.backupDirectory)
        } catch {
            try Self.rethrowStorageMutation(error)
        }

        let backups = names
            .filter(Self.isBackupFilename)
            .sorted { lhs, rhs in
                let lhsDate = Self.backupCreatedAt(from: lhs) ?? .distantPast
                let rhsDate = Self.backupCreatedAt(from: rhs) ?? .distantPast
                if lhsDate == rhsDate {
                    return lhs > rhs
                }
                return lhsDate > rhsDate
            }

        guard backups.count > Self.maximumBackupCount else {
            return
        }

        for name in backups.dropFirst(Self.maximumBackupCount) {
            do {
                try stateStore.removeRegularFile(in: Self.backupDirectory, named: name)
            } catch {
                try Self.rethrowStorageMutation(error)
            }
        }
    }

    private static func mapCurrentReadError(_ error: Error) -> ConfigurationPersistenceError {
        if let physical = error as? PhysicalStateStoreError {
            switch physical {
            case .unsafeTopology, .invalidPathComponent:
                return .unsafeStorageTopology
            case .alreadyExists, .ioFailure:
                return .corruptCurrent
            }
        }
        return .corruptCurrent
    }

    private static func rethrowStorageMutation(_ error: Error) throws -> Never {
        if let physical = error as? PhysicalStateStoreError {
            switch physical {
            case .unsafeTopology, .invalidPathComponent:
                throw ConfigurationPersistenceError.unsafeStorageTopology
            case .alreadyExists, .ioFailure:
                throw physical
            }
        }
        throw error
    }

    private static func mapCurrentFailure(_ failure: DecodingFailure) -> ConfigurationPersistenceError {
        switch failure {
        case .corrupt:
            return .corruptCurrent
        case let .unsupportedSchema(version):
            return .unsupportedSchemaVersion(version)
        }
    }

    private static func makeBackupFilename(now: Date = Date()) -> String {
        let milliseconds = Int64((now.timeIntervalSince1970 * 1_000).rounded(.down))
        return "backup-\(milliseconds)-\(UUID().uuidString.lowercased()).json"
    }

    private static func makePreservedFilename(now: Date = Date()) -> String {
        let milliseconds = Int64((now.timeIntervalSince1970 * 1_000).rounded(.down))
        return "current-\(milliseconds)-\(UUID().uuidString.lowercased()).json"
    }

    private static func isBackupFilename(_ filename: String) -> Bool {
        backupComponents(from: filename) != nil
    }

    private static func backupCreatedAt(from filename: String) -> Date? {
        guard let components = backupComponents(from: filename) else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(components.milliseconds) / 1_000)
    }

    private static func backupComponents(
        from filename: String
    ) -> (milliseconds: Int64, id: UUID)? {
        guard filename.hasPrefix("backup-"), filename.hasSuffix(".json") else {
            return nil
        }

        let withoutPrefix = filename.dropFirst("backup-".count)
        let withoutSuffix = withoutPrefix.dropLast(".json".count)
        guard let separator = withoutSuffix.firstIndex(of: "-") else {
            return nil
        }

        let timestampText = withoutSuffix[..<separator]
        let uuidText = withoutSuffix[withoutSuffix.index(after: separator)...]
        guard let milliseconds = Int64(timestampText),
              let id = UUID(uuidString: String(uuidText))
        else {
            return nil
        }
        return (milliseconds, id)
    }
}
