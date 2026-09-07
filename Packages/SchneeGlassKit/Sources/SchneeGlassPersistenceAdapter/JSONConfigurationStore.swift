import Foundation
import SchneeGlassApplication
import SchneeGlassDomain

public actor JSONConfigurationStore: ConfigurationPersisting, ConfigurationRecoveryProviding {
    public static let schemaVersion = 1
    public static let maximumBackupCount = 5

    private struct Envelope: Codable, Sendable {
        let schemaVersion: Int
        let glasses: [GlassConfiguration]
    }

    private enum DecodingFailure: Error {
        case corrupt
        case unsupportedSchema(Int)
    }

    private let configurationDirectoryURL: URL
    private let backupDirectoryURL: URL
    private let preservedDirectoryURL: URL
    private let configurationURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseDirectory: URL) {
        let root = baseDirectory.standardizedFileURL
        self.configurationDirectoryURL = root.appendingPathComponent("Configuration", isDirectory: true)
        self.backupDirectoryURL = root
            .appendingPathComponent("Configuration", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
        self.preservedDirectoryURL = root
            .appendingPathComponent("Configuration", isDirectory: true)
            .appendingPathComponent("Preserved", isDirectory: true)
        self.configurationURL = root
            .appendingPathComponent("Configuration", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
        self.fileManager = .default

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public func load() async throws -> [GlassConfiguration] {
        guard fileManager.fileExists(atPath: configurationURL.path) else {
            return []
        }

        let data: Data
        do {
            data = try Data(contentsOf: configurationURL)
        } catch {
            throw ConfigurationPersistenceError.corruptCurrent
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
        try createDirectories()

        if fileManager.fileExists(atPath: configurationURL.path) {
            let currentData: Data
            do {
                currentData = try Data(contentsOf: configurationURL)
            } catch {
                throw ConfigurationPersistenceError.corruptCurrent
            }

            do {
                _ = try decodeEnvelope(currentData)
            } catch let failure as DecodingFailure {
                throw Self.mapCurrentFailure(failure)
            } catch {
                throw ConfigurationPersistenceError.corruptCurrent
            }

            try writeBackup(data: currentData)
        }

        try newData.write(to: configurationURL, options: .atomic)
        try rotateBackups()
    }

    public func availableBackups() async throws -> [ConfigurationBackupDescriptor] {
        guard fileManager.fileExists(atPath: backupDirectoryURL.path) else {
            return []
        }

        let urls = try fileManager.contentsOfDirectory(
            at: backupDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        var descriptors: [ConfigurationBackupDescriptor] = []
        descriptors.reserveCapacity(urls.count)

        for url in urls where Self.isBackupFilename(url.lastPathComponent) {
            guard let createdAt = Self.backupCreatedAt(from: url.lastPathComponent) else {
                continue
            }

            do {
                let data = try Data(contentsOf: url)
                _ = try decodeEnvelope(data)
                descriptors.append(
                    ConfigurationBackupDescriptor(
                        id: url.lastPathComponent,
                        createdAt: createdAt
                    )
                )
            } catch {
                // Corrupt backups are intentionally not surfaced as restorable candidates.
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

        let backupURL = backupDirectoryURL.appendingPathComponent(id, isDirectory: false)
        guard fileManager.fileExists(atPath: backupURL.path) else {
            throw ConfigurationPersistenceError.backupNotFound
        }

        let backupData: Data
        let backupEnvelope: Envelope
        do {
            backupData = try Data(contentsOf: backupURL)
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

        try createDirectories()
        try preserveOrBackupCurrentBeforeExplicitRestore()
        try backupData.write(to: configurationURL, options: .atomic)
        try rotateBackups()
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

    private func createDirectories() throws {
        try fileManager.createDirectory(
            at: configurationDirectoryURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: backupDirectoryURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: preservedDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    private func writeBackup(data: Data) throws {
        let url = backupDirectoryURL.appendingPathComponent(
            Self.makeBackupFilename(),
            isDirectory: false
        )
        try data.write(to: url, options: .atomic)
    }

    private func preserveOrBackupCurrentBeforeExplicitRestore() throws {
        guard fileManager.fileExists(atPath: configurationURL.path) else {
            return
        }

        let currentData: Data
        do {
            currentData = try Data(contentsOf: configurationURL)
        } catch {
            return
        }

        if (try? decodeEnvelope(currentData)) != nil {
            try writeBackup(data: currentData)
            return
        }

        let preservedURL = preservedDirectoryURL.appendingPathComponent(
            Self.makePreservedFilename(),
            isDirectory: false
        )
        try currentData.write(to: preservedURL, options: .atomic)
    }

    private func rotateBackups() throws {
        guard fileManager.fileExists(atPath: backupDirectoryURL.path) else {
            return
        }

        let backups = try fileManager.contentsOfDirectory(
            at: backupDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { Self.isBackupFilename($0.lastPathComponent) }
        .sorted { lhs, rhs in
            let lhsDate = Self.backupCreatedAt(from: lhs.lastPathComponent) ?? .distantPast
            let rhsDate = Self.backupCreatedAt(from: rhs.lastPathComponent) ?? .distantPast
            if lhsDate == rhsDate {
                return lhs.lastPathComponent > rhs.lastPathComponent
            }
            return lhsDate > rhsDate
        }

        guard backups.count > Self.maximumBackupCount else {
            return
        }

        try ConfigurationBackupRotator.removeBackups(
            backups.dropFirst(Self.maximumBackupCount),
            fileManager: fileManager
        )
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
