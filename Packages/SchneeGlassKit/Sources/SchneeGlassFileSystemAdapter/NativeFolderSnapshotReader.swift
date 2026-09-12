import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassPOSIXSupport

public enum NativeFolderSnapshotReaderError: Error, Hashable, Sendable {
    case enumerationUnavailable
    case enumerationFailed
    case folderMetadataUnavailable
    case itemMetadataUnavailable
}

struct SnapshotFolderFingerprint: Equatable, Sendable {
    let volumeIdentifier: String?
    let resourceIdentifier: String?
}

protocol SnapshotFolderFingerprintReading: Sendable {
    func fingerprint(for url: URL) throws -> SnapshotFolderFingerprint
}

struct FoundationSnapshotFolderFingerprintReader: SnapshotFolderFingerprintReading {
    func fingerprint(for url: URL) throws -> SnapshotFolderFingerprint {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [
                .volumeIdentifierKey,
                .fileResourceIdentifierKey,
            ])
        } catch {
            throw NativeFolderSnapshotReaderError.folderMetadataUnavailable
        }

        return SnapshotFolderFingerprint(
            volumeIdentifier: values.volumeIdentifier.map { String(describing: $0) },
            resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) }
        )
    }
}

public actor NativeFolderSnapshotReader: FolderSnapshotReading {
    public static let maximumDisplayedItems = 500

    private let fileManager: FileManager
    private let runtimeIdentityReader: any RuntimeDirectoryIdentityReading
    private let folderFingerprintReader: any SnapshotFolderFingerprintReading

    public init() {
        self.fileManager = .default
        self.runtimeIdentityReader = POSIXRuntimeDirectoryIdentityReader()
        self.folderFingerprintReader = FoundationSnapshotFolderFingerprintReader()
    }

    init(
        fileManager: FileManager,
        runtimeIdentityReader: any RuntimeDirectoryIdentityReading = POSIXRuntimeDirectoryIdentityReader(),
        folderFingerprintReader: any SnapshotFolderFingerprintReading = FoundationSnapshotFolderFingerprintReader()
    ) {
        self.fileManager = fileManager
        self.runtimeIdentityReader = runtimeIdentityReader
        self.folderFingerprintReader = folderFingerprintReader
    }

    public func snapshot(
        for access: FolderAccessHandle,
        generation: UInt64
    ) async throws -> FolderSnapshot {
        let initialRuntimeIdentity = await runtimeIdentityReader.identity(for: access.url)
        try Self.validate(
            observed: initialRuntimeIdentity,
            expected: access.runtimeDirectoryIdentity
        )

        // A production POSIX-backed access already carries the exact directory device/inode that
        // was authorized. Avoid reading or stringifying Foundation's opaque root identifiers on that
        // path. Legacy/fallback handles keep the previous Foundation comparison contract.
        let initialFingerprint: SnapshotFolderFingerprint?
        if access.runtimeDirectoryIdentity == nil {
            let observed = try folderFingerprintReader.fingerprint(for: access.url)
            try Self.validate(
                observed: observed,
                expectedVolumeIdentifier: access.fingerprint?.volumeIdentifier,
                expectedResourceIdentifier: access.fingerprint?.resourceIdentifier
            )
            initialFingerprint = observed
        } else {
            initialFingerprint = nil
        }

        let folderIdentity = FolderIdentity(
            resourceIdentifier: initialFingerprint?.resourceIdentifier,
            standardizedURL: access.url
        )

        let resourceKeys: [URLResourceKey] = [
            .nameKey,
            .fileResourceTypeKey,
            .fileResourceIdentifierKey,
            .isAliasFileKey,
            .isPackageKey,
            .isHiddenKey,
            .contentModificationDateKey,
            .fileSizeKey,
        ]

        var enumerationFailure: Error?
        guard let enumerator = fileManager.enumerator(
            at: access.url,
            includingPropertiesForKeys: resourceKeys,
            options: [
                .skipsHiddenFiles,
                .skipsSubdirectoryDescendants,
                .skipsPackageDescendants,
            ],
            errorHandler: { _, error in
                enumerationFailure = error
                return false
            }
        ) else {
            throw NativeFolderSnapshotReaderError.enumerationUnavailable
        }

        var items: [GlassItem] = []
        items.reserveCapacity(Self.maximumDisplayedItems)
        var isTruncated = false

        while let candidate = enumerator.nextObject() as? URL {
            if items.count == Self.maximumDisplayedItems {
                isTruncated = true
                break
            }

            let item: GlassItem
            do {
                item = try makeItem(for: candidate, resourceKeys: resourceKeys)
            } catch {
                throw NativeFolderSnapshotReaderError.itemMetadataUnavailable
            }

            items.append(item)
        }

        if enumerationFailure != nil {
            throw NativeFolderSnapshotReaderError.enumerationFailed
        }

        // The root pathname can be replaced while enumeration is suspended in Foundation. The
        // acquired descriptor identity is authoritative on the normal path. A snapshot that began
        // without acquired POSIX proof keeps the previous Foundation fallback comparison.
        let finalRuntimeIdentity = await runtimeIdentityReader.identity(for: access.url)
        if let initialRuntimeIdentity {
            guard let finalRuntimeIdentity,
                  finalRuntimeIdentity == initialRuntimeIdentity
            else {
                throw FolderSnapshotReadError.rootIdentityMismatch
            }
        }
        try Self.validate(
            observed: finalRuntimeIdentity,
            expected: access.runtimeDirectoryIdentity
        )

        if let initialFingerprint {
            let finalFingerprint = try folderFingerprintReader.fingerprint(for: access.url)
            try Self.validate(
                observed: finalFingerprint,
                expectedVolumeIdentifier: access.fingerprint?.volumeIdentifier,
                expectedResourceIdentifier: access.fingerprint?.resourceIdentifier
            )
            guard finalFingerprint == initialFingerprint else {
                throw FolderSnapshotReadError.rootIdentityMismatch
            }
        }

        items.sort(by: Self.itemSortOrder)

        return FolderSnapshot(
            folderIdentity: folderIdentity,
            items: items,
            isTruncated: isTruncated,
            observedAt: Date(),
            generation: generation
        )
    }

    private static func validate(
        observed: POSIXDirectoryIdentity?,
        expected: RuntimeDirectoryIdentity?
    ) throws {
        guard let expected else {
            return
        }
        guard let observed,
              observed.device == expected.deviceIdentifier,
              observed.inode == expected.objectIdentifier
        else {
            throw FolderSnapshotReadError.rootIdentityMismatch
        }
    }

    private static func validate(
        observed: SnapshotFolderFingerprint,
        expectedVolumeIdentifier: String?,
        expectedResourceIdentifier: String?
    ) throws {
        if let expectedVolumeIdentifier,
           observed.volumeIdentifier != expectedVolumeIdentifier
        {
            throw FolderSnapshotReadError.rootIdentityMismatch
        }
        if let expectedResourceIdentifier,
           observed.resourceIdentifier != expectedResourceIdentifier
        {
            throw FolderSnapshotReadError.rootIdentityMismatch
        }
    }

    private func makeItem(
        for url: URL,
        resourceKeys: [URLResourceKey]
    ) throws -> GlassItem {
        let values = try url.resourceValues(forKeys: Set(resourceKeys))
        let kind = try classify(url: url, values: values)

        return GlassItem(
            id: FileIdentity(
                resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) },
                standardizedURL: url
            ),
            url: url.standardizedFileURL,
            displayName: values.name ?? url.lastPathComponent,
            kind: kind,
            modificationDate: values.contentModificationDate,
            fileSize: values.fileSize.map(Int64.init),
            isHidden: values.isHidden ?? false
        )
    }

    private func classify(url: URL, values: URLResourceValues) throws -> FileKind {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            return .symbolicLink
        }

        if values.isAliasFile == true {
            return .alias
        }

        if values.isPackage == true {
            return .package
        }

        switch values.fileResourceType {
        case .directory:
            return .directory
        case .regular:
            return .regular
        default:
            return .unsupported
        }
    }

    private static func itemSortOrder(_ lhs: GlassItem, _ rhs: GlassItem) -> Bool {
        let comparison = lhs.displayName.localizedStandardCompare(rhs.displayName)
        if comparison == .orderedSame {
            return lhs.url.path < rhs.url.path
        }
        return comparison == .orderedAscending
    }
}
