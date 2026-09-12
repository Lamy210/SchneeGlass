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

public actor NativeFolderSnapshotReader: FolderSnapshotReading {
    public static let maximumDisplayedItems = 500

    private struct ObservedFolderFingerprint: Equatable, Sendable {
        let volumeIdentifier: String?
        let resourceIdentifier: String?
    }

    private let fileManager: FileManager
    private let runtimeIdentityReader: any RuntimeDirectoryIdentityReading

    public init() {
        self.fileManager = .default
        self.runtimeIdentityReader = POSIXRuntimeDirectoryIdentityReader()
    }

    init(
        fileManager: FileManager,
        runtimeIdentityReader: any RuntimeDirectoryIdentityReading = POSIXRuntimeDirectoryIdentityReader()
    ) {
        self.fileManager = fileManager
        self.runtimeIdentityReader = runtimeIdentityReader
    }

    public func snapshot(
        for access: FolderAccessHandle,
        generation: UInt64
    ) async throws -> FolderSnapshot {
        let initialRuntimeIdentity = await runtimeIdentityReader.identity(for: access.url)
        let initialFingerprint = try folderFingerprint(for: access.url)
        try Self.validate(
            observed: initialFingerprint,
            expectedVolumeIdentifier: access.fingerprint?.volumeIdentifier,
            expectedResourceIdentifier: access.fingerprint?.resourceIdentifier
        )
        let folderIdentity = FolderIdentity(
            resourceIdentifier: initialFingerprint.resourceIdentifier,
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

        // The root pathname can be replaced while enumeration is suspended in Foundation. Prefer
        // descriptor-derived device/inode identity for the before/after boundary and retain the
        // Foundation fingerprint checks as compatibility/authorization defense in depth.
        let finalRuntimeIdentity = await runtimeIdentityReader.identity(for: access.url)
        if let initialRuntimeIdentity {
            guard let finalRuntimeIdentity,
                  finalRuntimeIdentity == initialRuntimeIdentity
            else {
                throw FolderSnapshotReadError.rootIdentityMismatch
            }
        }

        let finalFingerprint = try folderFingerprint(for: access.url)
        try Self.validate(
            observed: finalFingerprint,
            expectedVolumeIdentifier: access.fingerprint?.volumeIdentifier,
            expectedResourceIdentifier: access.fingerprint?.resourceIdentifier
        )
        guard finalFingerprint == initialFingerprint else {
            throw FolderSnapshotReadError.rootIdentityMismatch
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

    private func folderFingerprint(for url: URL) throws -> ObservedFolderFingerprint {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [
                .volumeIdentifierKey,
                .fileResourceIdentifierKey,
            ])
        } catch {
            throw NativeFolderSnapshotReaderError.folderMetadataUnavailable
        }

        return ObservedFolderFingerprint(
            volumeIdentifier: values.volumeIdentifier.map { String(describing: $0) },
            resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) }
        )
    }

    private static func validate(
        observed: ObservedFolderFingerprint,
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
