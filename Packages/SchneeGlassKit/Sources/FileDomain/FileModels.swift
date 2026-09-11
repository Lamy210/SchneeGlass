import Foundation
import SchneeGlassDomain

public struct FileIdentity: Hashable, Sendable {
    public let resourceIdentifier: String?
    public let standardizedURL: URL

    public init(resourceIdentifier: String?, standardizedURL: URL) {
        self.resourceIdentifier = resourceIdentifier
        self.standardizedURL = standardizedURL.standardizedFileURL
    }
}

public struct FolderIdentity: Hashable, Sendable {
    public let resourceIdentifier: String?
    public let standardizedURL: URL

    public init(resourceIdentifier: String?, standardizedURL: URL) {
        self.resourceIdentifier = resourceIdentifier
        self.standardizedURL = standardizedURL.standardizedFileURL
    }
}

public enum FileKind: String, Codable, Sendable {
    case regular
    case directory
    case package
    case alias
    case symbolicLink
    case unsupported
}

public struct GlassItem: Identifiable, Hashable, Sendable {
    public let id: FileIdentity
    public let url: URL
    public let displayName: String
    public let kind: FileKind
    public let modificationDate: Date?
    public let fileSize: Int64?
    public let isHidden: Bool

    public init(
        id: FileIdentity,
        url: URL,
        displayName: String,
        kind: FileKind,
        modificationDate: Date? = nil,
        fileSize: Int64? = nil,
        isHidden: Bool
    ) {
        self.id = id
        self.url = url
        self.displayName = displayName
        self.kind = kind
        self.modificationDate = modificationDate
        self.fileSize = fileSize
        self.isHidden = isHidden
    }
}

public struct FolderSnapshot: Hashable, Sendable {
    public let folderIdentity: FolderIdentity
    public let items: [GlassItem]
    public let isTruncated: Bool
    public let observedAt: Date
    public let generation: UInt64

    public init(
        folderIdentity: FolderIdentity,
        items: [GlassItem],
        isTruncated: Bool,
        observedAt: Date = Date(),
        generation: UInt64
    ) {
        self.folderIdentity = folderIdentity
        self.items = items
        self.isTruncated = isTruncated
        self.observedAt = observedAt
        self.generation = generation
    }
}

public enum StorageLocationKind: Hashable, Sendable {
    case localFixed
    case localRemovable
    case network
}

public struct StorageCapabilities: Hashable, Sendable {
    public let locationKind: StorageLocationKind
    public let isWritable: Bool
    public let supportsCaseSensitiveNames: Bool?
    public let supportsSafeDestinationCommit: Bool?

    public init(
        locationKind: StorageLocationKind,
        isWritable: Bool,
        supportsCaseSensitiveNames: Bool? = nil,
        supportsSafeDestinationCommit: Bool? = nil
    ) {
        self.locationKind = locationKind
        self.isWritable = isWritable
        self.supportsCaseSensitiveNames = supportsCaseSensitiveNames
        self.supportsSafeDestinationCommit = supportsSafeDestinationCommit
    }
}

public struct DropCandidate: Hashable, Sendable {
    public let url: URL
    public let kind: FileKind
    public let size: Int64?

    public init(url: URL, kind: FileKind, size: Int64? = nil) {
        self.url = url
        self.kind = kind
        self.size = size
    }
}

public struct DestinationDescriptor: Hashable, Sendable {
    public let glassID: GlassID
    public let folderIdentity: FolderIdentity
    public let url: URL
    public let capabilities: StorageCapabilities

    public init(
        glassID: GlassID,
        folderIdentity: FolderIdentity,
        url: URL,
        capabilities: StorageCapabilities
    ) {
        self.glassID = glassID
        self.folderIdentity = folderIdentity
        self.url = url
        self.capabilities = capabilities
    }
}

public struct CopyItemPlan: Hashable, Sendable {
    public let operationID: UUID
    public let sourceURL: URL
    public let originalFilename: String
    public let destinationFilename: String
    public let expectedSize: Int64?

    public init(
        operationID: UUID = UUID(),
        sourceURL: URL,
        originalFilename: String,
        destinationFilename: String,
        expectedSize: Int64? = nil
    ) {
        self.operationID = operationID
        self.sourceURL = sourceURL
        self.originalFilename = originalFilename
        self.destinationFilename = destinationFilename
        self.expectedSize = expectedSize
    }
}

public enum CopyBatchPlanValidationError: Error, Hashable, Sendable {
    case emptyItems
}

public struct CopyBatchPlan: Hashable, Sendable {
    public let batchID: UUID
    public let destination: DestinationDescriptor
    public let items: [CopyItemPlan]
    public let createdAt: Date

    public init(
        batchID: UUID = UUID(),
        destination: DestinationDescriptor,
        items: [CopyItemPlan],
        createdAt: Date = Date()
    ) throws {
        guard !items.isEmpty else {
            throw CopyBatchPlanValidationError.emptyItems
        }
        self.batchID = batchID
        self.destination = destination
        self.items = items
        self.createdAt = createdAt
    }
}

public enum DropRejection: Error, Hashable, Sendable {
    case unsupportedFolder
    case unsupportedPackage
    case unsupportedSymbolicLink
    case unsupportedItem
    case tooManyItems
    case collision
    case containsSameDirectoryItem
    case destinationUnavailable
    case destinationReadOnly
    case destinationCopySafetyUnsupported
    case networkDestinationUnsupported
    case sourceUnavailable
    case cloudPlaceholderUnavailable
}

public enum DropPlan: Hashable, Sendable {
    case copy(CopyBatchPlan)
    case noOperation
    case reject(DropRejection)
}
