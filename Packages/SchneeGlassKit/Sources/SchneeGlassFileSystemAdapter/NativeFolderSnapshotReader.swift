import FileDomain
import Foundation
import SchneeGlassApplication

public enum NativeFolderSnapshotReaderError: Error, Hashable, Sendable {
    case enumerationUnavailable
    case enumerationFailed
    case folderMetadataUnavailable
    case itemMetadataUnavailable
}

public actor NativeFolderSnapshotReader: FolderSnapshotReading {
    public static let maximumDisplayedItems = 500

    private let fileManager: FileManager

    public init() {
        self.fileManager = .default
    }

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    public func snapshot(
        for access: FolderAccessHandle,
        generation: UInt64
    ) async throws -> FolderSnapshot {
        let folderIdentity = try folderIdentity(for: access.url)

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

        items.sort(by: Self.itemSortOrder)

        return FolderSnapshot(
            folderIdentity: folderIdentity,
            items: items,
            isTruncated: isTruncated,
            observedAt: Date(),
            generation: generation
        )
    }

    private func folderIdentity(for url: URL) throws -> FolderIdentity {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.fileResourceIdentifierKey])
        } catch {
            throw NativeFolderSnapshotReaderError.folderMetadataUnavailable
        }

        return FolderIdentity(
            resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) },
            standardizedURL: url
        )
    }

    private func makeItem(
        for url: URL,
        resourceKeys: [URLResourceKey]
    ) throws -> GlassItem {
        let values = try url.resourceValues(forKeys: Set(resourceKeys))
        let kind = Self.classify(values)

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

    private static func classify(_ values: URLResourceValues) -> FileKind {
        if values.isAliasFile == true {
            return .alias
        }

        if values.fileResourceType == .symbolicLink {
            return .symbolicLink
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
