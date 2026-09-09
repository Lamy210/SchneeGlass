import Foundation
import SchneeGlassApplication
import SchneeGlassPOSIXSupport

public actor JSONPendingCopyStore: PendingCopyRecording {
    public static let filename = "pending-copies.json"

    private let stateStore: PhysicalStateStore
    private let directoryComponents: [String]
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Uses `baseDirectory` itself as the app-owned physical root. This initializer remains useful
    /// for isolated tests and callers that already pass the final FileOperations directory.
    public init(baseDirectory: URL) {
        self.stateStore = PhysicalStateStore(rootURL: baseDirectory.standardizedFileURL)
        self.directoryComponents = []

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    /// Production initializer. The application-support bundle directory is the physical trust root,
    /// and `relativeDirectory` is opened beneath it with `O_DIRECTORY | O_NOFOLLOW`.
    public init(applicationSupportRoot: URL, relativeDirectory: String) {
        self.stateStore = PhysicalStateStore(rootURL: applicationSupportRoot.standardizedFileURL)
        self.directoryComponents = [relativeDirectory]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public func records() throws -> [PendingCopyRecord] {
        try loadRecords()
    }

    public func upsert(_ record: PendingCopyRecord) throws {
        var current = try loadRecords()
        if let index = current.firstIndex(where: { $0.operationID == record.operationID }) {
            current[index] = record
        } else {
            current.append(record)
        }
        try persist(current)
    }

    public func remove(operationID: UUID) throws {
        let current = try loadRecords()
        let filtered = current.filter { $0.operationID != operationID }
        guard filtered.count != current.count else {
            return
        }
        try persist(filtered)
    }

    private func loadRecords() throws -> [PendingCopyRecord] {
        guard let data = try stateStore.readRegularFile(
            in: directoryComponents,
            named: Self.filename
        ) else {
            return []
        }
        return try decoder.decode([PendingCopyRecord].self, from: data)
    }

    private func persist(_ records: [PendingCopyRecord]) throws {
        let sorted = records.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.operationID.uuidString < $1.operationID.uuidString
            }
            return $0.createdAt < $1.createdAt
        }
        let data = try encoder.encode(sorted)
        try stateStore.writeAtomically(
            data,
            in: directoryComponents,
            named: Self.filename
        )
    }
}
