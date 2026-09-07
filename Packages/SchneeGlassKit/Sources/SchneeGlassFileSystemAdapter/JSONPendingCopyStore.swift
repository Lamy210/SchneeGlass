import Foundation
import SchneeGlassApplication

public actor JSONPendingCopyStore: PendingCopyRecording {
    public static let filename = "pending-copies.json"

    private let directoryURL: URL
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseDirectory: URL) {
        self.directoryURL = baseDirectory.standardizedFileURL
        self.fileURL = baseDirectory
            .appendingPathComponent(Self.filename, isDirectory: false)
            .standardizedFileURL
        self.fileManager = .default

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
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([PendingCopyRecord].self, from: data)
    }

    private func persist(_ records: [PendingCopyRecord]) throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let sorted = records.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.operationID.uuidString < $1.operationID.uuidString
            }
            return $0.createdAt < $1.createdAt
        }
        let data = try encoder.encode(sorted)
        try data.write(to: fileURL, options: .atomic)
    }
}
