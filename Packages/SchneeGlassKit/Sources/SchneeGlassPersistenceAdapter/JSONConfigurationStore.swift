import Darwin
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

    private enum BackupReadFailure: Error {
        case openFailed(Int32)
        case metadataFailed(Int32)
        case readFailed(Int32)
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

        // Finish fallible backup housekeeping before replacing the current configuration. Once
        // the atomic replacement succeeds, save must not report failure for unrelated cleanup
        // after the committed configuration state has already changed.
        try rotateBackups()
        try newData.write(to: configurationURL, options: .atomic)
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
                guard let data = try Self.readPhysicalRegularFile(at: url) else {
                    continue
                }
                _ = try decodeEnvelope(data)
                descriptors.append(
                    ConfigurationBackupDescriptor(
                        id: url.lastPathComponent,
                        createdAt: createdAt
                    )
                )
            } catch {
                // Corrupt, unreadable, replaced, or non-regular backups are intentionally not surfaced.
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

        let backupData: Data
        do {
            guard let data = try Self.readPhysicalRegularFile(at: backupURL) else {
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

        try createDirectories()
        try preserveOrBackupCurrentBeforeExplicitRestore()

        // Complete fallible backup housekeeping before replacing the current configuration. Once
        // the atomic replacement succeeds, this method must not report failure for work that is
        // unrelated to the committed configuration state.
        try rotateBackups()
        try backupData.write(to: configurationURL, options: .atomic)
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
            // Recovery must not overwrite current state that it could not read and therefore could
            // not preserve. Treat the current configuration as unavailable/corrupt and fail closed.
            throw ConfigurationPersistenceError.corruptCurrent
        }

        do {
            _ = try decodeEnvelope(currentData)
        } catch let failure as DecodingFailure {
            switch failure {
            case .corrupt:
                // Malformed but readable bytes may still be useful for manual recovery. Preserve
                // them byte-for-byte before replacing current state with the explicitly selected backup.
                let preservedURL = preservedDirectoryURL.appendingPathComponent(
                    Self.makePreservedFilename(),
                    isDirectory: false
                )
                try currentData.write(to: preservedURL, options: .atomic)
                return
            case let .unsupportedSchema(version):
                // A newer/future schema is not corruption. An older app must never overwrite data
                // it does not understand, even as part of an explicit backup restore.
                throw ConfigurationPersistenceError.unsupportedSchemaVersion(version)
            }
        } catch {
            throw ConfigurationPersistenceError.corruptCurrent
        }

        // The current configuration is valid and supported. Backup I/O failures are not corruption
        // and therefore propagate unchanged while still blocking the restore before current mutation.
        try writeBackup(data: currentData)
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
        .filter {
            Self.isBackupFilename($0.lastPathComponent)
                && Self.isPhysicalRegularFile($0)
        }
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
            backups.dropFirst(Self.maximumBackupCount)
        )
    }

    private static func isPhysicalRegularFile(_ url: URL) -> Bool {
        var metadata = stat()
        let result = url.standardizedFileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return Int32(-1)
            }
            return lstat(path, &metadata)
        }
        guard result == 0 else {
            return false
        }
        return (metadata.st_mode & S_IFMT) == S_IFREG
    }

    /// Opens the directory entry itself with O_NOFOLLOW and reads bytes from that pinned FD.
    /// Returning nil means the entry is missing or non-regular; thrown errors mean a regular-file
    /// candidate could not be read safely. This closes the lstat -> Data(contentsOf:) symlink race.
    private static func readPhysicalRegularFile(at url: URL) throws -> Data? {
        let candidate = url.standardizedFileURL
        let openResult = candidate.withUnsafeFileSystemRepresentation { path -> (descriptor: Int32, error: Int32)? in
            guard let path else {
                return nil
            }
            let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
            return (descriptor, descriptor >= 0 ? 0 : errno)
        }

        guard let openResult else {
            throw BackupReadFailure.openFailed(EINVAL)
        }
        guard openResult.descriptor >= 0 else {
            if openResult.error == ENOENT || openResult.error == ELOOP {
                return nil
            }
            throw BackupReadFailure.openFailed(openResult.error)
        }

        let descriptor = openResult.descriptor
        defer { close(descriptor) }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else {
            throw BackupReadFailure.metadataFailed(errno)
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG else {
            return nil
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)

        while true {
            var observedErrno = Int32(0)
            let count = buffer.withUnsafeMutableBytes { bytes -> Int in
                let result = Darwin.read(descriptor, bytes.baseAddress, bytes.count)
                if result < 0 {
                    observedErrno = errno
                }
                return result
            }

            if count == 0 {
                break
            }
            if count < 0 {
                if observedErrno == EINTR {
                    continue
                }
                throw BackupReadFailure.readFailed(observedErrno)
            }

            data.append(contentsOf: buffer.prefix(count))
        }

        return data
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
