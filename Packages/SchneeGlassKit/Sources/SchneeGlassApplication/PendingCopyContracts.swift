import Foundation
import SchneeGlassDomain

public enum PendingCopyState: String, Codable, Hashable, Sendable {
    case recorded
    case staging
    case verifying
    case committing
}

public struct PendingCopyRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID { operationID }

    public let operationID: UUID
    public let batchID: UUID
    public let destinationGlassID: GlassID
    public let stagingFilename: String
    public let finalFilename: String
    public let expectedSize: Int64?
    public let createdAt: Date
    public let state: PendingCopyState

    public init(
        operationID: UUID,
        batchID: UUID,
        destinationGlassID: GlassID,
        stagingFilename: String,
        finalFilename: String,
        expectedSize: Int64?,
        createdAt: Date = Date(),
        state: PendingCopyState
    ) {
        self.operationID = operationID
        self.batchID = batchID
        self.destinationGlassID = destinationGlassID
        self.stagingFilename = stagingFilename
        self.finalFilename = finalFilename
        self.expectedSize = expectedSize
        self.createdAt = createdAt
        self.state = state
    }

    public func updating(state: PendingCopyState) -> PendingCopyRecord {
        PendingCopyRecord(
            operationID: operationID,
            batchID: batchID,
            destinationGlassID: destinationGlassID,
            stagingFilename: stagingFilename,
            finalFilename: finalFilename,
            expectedSize: expectedSize,
            createdAt: createdAt,
            state: state
        )
    }
}

public protocol PendingCopyRecording: Sendable {
    func records() async throws -> [PendingCopyRecord]
    func upsert(_ record: PendingCopyRecord) async throws
    func remove(operationID: UUID) async throws
}
