import FileDomain
import Foundation
import SchneeGlassApplication

struct DropSourceInspection: Sendable {
    let candidate: DropCandidate
    let availability: DropCandidateAvailability
    let sourceLeaseToken: UUID?

    init(
        candidate: DropCandidate,
        availability: DropCandidateAvailability,
        sourceLeaseToken: UUID? = nil
    ) {
        self.candidate = candidate
        self.availability = availability
        self.sourceLeaseToken = sourceLeaseToken
    }
}

protocol DropFileSystemInspecting: Sendable {
    func inspectSource(at url: URL) async -> DropSourceInspection
    func destinationDescriptor(for access: FolderAccessHandle) async -> DestinationDescriptor?
    func itemExists(at url: URL) async -> Bool
}

actor FoundationDropFileSystemInspector: DropFileSystemInspecting {
    private let fileManager: FileManager
    private let sourceLeases: SourceFileLeaseRegistry?

    init(
        fileManager: FileManager = .default,
        sourceLeases: SourceFileLeaseRegistry? = nil
    ) {
        self.fileManager = fileManager
        self.sourceLeases = sourceLeases
    }

    func inspectSource(at url: URL) async -> DropSourceInspection {
        let source = url.standardizedFileURL
        let didStart = source.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                source.stopAccessingSecurityScopedResource()
            }
        }

        var preparedToken: UUID?
        do {
            let attributes = try fileManager.attributesOfItem(atPath: source.path)
            let values = try source.resourceValues(forKeys: [
                .isAliasFileKey,
                .isPackageKey,
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey,
            ])

            let kind: FileKind
            if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                kind = .symbolicLink
            } else if values.isAliasFile == true {
                kind = .alias
            } else if values.isPackage == true {
                kind = .package
            } else if attributes[.type] as? FileAttributeType == .typeDirectory {
                kind = .directory
            } else if attributes[.type] as? FileAttributeType == .typeRegular {
                kind = .regular
            } else {
                kind = .unsupported
            }

            let availability: DropCandidateAvailability
            if values.isUbiquitousItem == true,
               values.ubiquitousItemDownloadingStatus != .current
            {
                availability = .cloudPlaceholderUnavailable
            } else {
                availability = .available
            }

            guard kind == .regular,
                  availability == .available,
                  let sourceLeases
            else {
                return DropSourceInspection(
                    candidate: DropCandidate(
                        url: source,
                        kind: kind,
                        size: (attributes[.size] as? NSNumber)?.int64Value
                    ),
                    availability: availability
                )
            }

            let prepared = try await sourceLeases.prepareSource(at: source)
            preparedToken = prepared.token

            // Re-read path-level flags while the original file descriptor is pinned, then verify
            // the path still names that same inode. Because the original descriptor remains open,
            // an unlinked inode cannot be immediately recycled underneath this comparison.
            let pinnedValues = try source.resourceValues(forKeys: [
                .isAliasFileKey,
                .isPackageKey,
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey,
            ])
            guard await sourceLeases.preparedSourceStillMatchesPath(token: prepared.token) else {
                throw SourceFileLeaseError.sourceChanged
            }

            if pinnedValues.isAliasFile == true {
                await sourceLeases.releasePrepared(tokens: [prepared.token])
                preparedToken = nil
                return DropSourceInspection(
                    candidate: DropCandidate(url: source, kind: .alias),
                    availability: .available
                )
            }
            if pinnedValues.isPackage == true {
                await sourceLeases.releasePrepared(tokens: [prepared.token])
                preparedToken = nil
                return DropSourceInspection(
                    candidate: DropCandidate(url: source, kind: .package),
                    availability: .available
                )
            }
            if pinnedValues.isUbiquitousItem == true,
               pinnedValues.ubiquitousItemDownloadingStatus != .current
            {
                await sourceLeases.releasePrepared(tokens: [prepared.token])
                preparedToken = nil
                return DropSourceInspection(
                    candidate: DropCandidate(url: source, kind: .regular, size: prepared.size),
                    availability: .cloudPlaceholderUnavailable
                )
            }

            return DropSourceInspection(
                candidate: DropCandidate(
                    url: prepared.standardizedURL,
                    kind: .regular,
                    size: prepared.size
                ),
                availability: .available,
                sourceLeaseToken: prepared.token
            )
        } catch {
            if let preparedToken, let sourceLeases {
                await sourceLeases.releasePrepared(tokens: [preparedToken])
            }
            return DropSourceInspection(
                candidate: DropCandidate(url: source, kind: .unsupported),
                availability: .sourceUnavailable
            )
        }
    }

    func destinationDescriptor(for access: FolderAccessHandle) -> DestinationDescriptor? {
        let destination = access.url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return nil
        }

        do {
            let values = try destination.resourceValues(forKeys: [
                .fileResourceIdentifierKey,
                .volumeIsLocalKey,
                .volumeIsRemovableKey,
                .volumeIsReadOnlyKey,
                .volumeSupportsCaseSensitiveNamesKey,
                .volumeSupportsExclusiveRenamingKey,
            ])

            let locationKind: StorageLocationKind
            if values.volumeIsLocal == false {
                locationKind = .network
            } else if values.volumeIsRemovable == true {
                locationKind = .localRemovable
            } else {
                locationKind = .localFixed
            }

            let isWritable = values.volumeIsReadOnly != true
                && fileManager.isWritableFile(atPath: destination.path)
            let hasDirectoryIdentity = values.fileResourceIdentifier != nil
            let supportsSafeDestinationCommit = hasDirectoryIdentity
                && values.volumeSupportsExclusiveRenaming == true

            return DestinationDescriptor(
                glassID: access.glassID,
                folderIdentity: FolderIdentity(
                    resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) },
                    standardizedURL: destination
                ),
                url: destination,
                capabilities: StorageCapabilities(
                    locationKind: locationKind,
                    isWritable: isWritable,
                    supportsCaseSensitiveNames: values.volumeSupportsCaseSensitiveNames,
                    supportsSafeDestinationCommit: supportsSafeDestinationCommit
                )
            )
        } catch {
            return nil
        }
    }

    func itemExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.standardizedFileURL.path)
    }
}

public actor NativeDropPlanningAdapter: DropPlanning {
    private let inspector: any DropFileSystemInspecting
    private let previewInspector: any DropFileSystemInspecting
    private let sourceLeases: SourceFileLeaseRegistry?

    /// Standalone construction is intentionally module-internal. Executable native Drop plans must
    /// be paired with a copier that consumes the same source lease authority; production callers
    /// should use `PinnedDropCopyPipeline` instead.
    init() {
        let sourceLeases = SourceFileLeaseRegistry()
        self.sourceLeases = sourceLeases
        self.inspector = FoundationDropFileSystemInspector(sourceLeases: sourceLeases)
        self.previewInspector = FoundationDropFileSystemInspector()
    }

    init(sourceLeases: SourceFileLeaseRegistry) {
        self.sourceLeases = sourceLeases
        self.inspector = FoundationDropFileSystemInspector(sourceLeases: sourceLeases)
        self.previewInspector = FoundationDropFileSystemInspector()
    }

    init(inspector: any DropFileSystemInspecting) {
        self.inspector = inspector
        self.previewInspector = inspector
        self.sourceLeases = nil
    }

    public func preview(
        sourceURLs: [URL],
        destinationAccess: FolderAccessHandle
    ) async -> DropPlan {
        await makePlan(
            sourceURLs: sourceURLs,
            destinationAccess: destinationAccess,
            inspector: previewInspector,
            sourceLeases: nil
        )
    }

    public func plan(
        sourceURLs: [URL],
        destinationAccess: FolderAccessHandle
    ) async -> DropPlan {
        await makePlan(
            sourceURLs: sourceURLs,
            destinationAccess: destinationAccess,
            inspector: inspector,
            sourceLeases: sourceLeases
        )
    }

    private func makePlan(
        sourceURLs: [URL],
        destinationAccess: FolderAccessHandle,
        inspector: any DropFileSystemInspecting,
        sourceLeases: SourceFileLeaseRegistry?
    ) async -> DropPlan {
        guard let destination = await inspector.destinationDescriptor(for: destinationAccess) else {
            return .reject(.destinationUnavailable)
        }

        var inspections: [DropSourceInspection] = []
        inspections.reserveCapacity(sourceURLs.count)
        var candidates: [DropCandidate] = []
        candidates.reserveCapacity(sourceURLs.count)
        var availability: [URL: DropCandidateAvailability] = [:]
        var collisions: Set<URL> = []

        for rawURL in sourceURLs {
            let sourceURL = rawURL.standardizedFileURL
            let inspection = await inspector.inspectSource(at: sourceURL)
            inspections.append(inspection)
            candidates.append(inspection.candidate)
            availability[sourceURL] = inspection.availability

            let finalURL = destination.url
                .appendingPathComponent(sourceURL.lastPathComponent, isDirectory: false)
                .standardizedFileURL
            if await inspector.itemExists(at: finalURL) {
                collisions.insert(sourceURL)
            }
        }

        let result = DropPlanner.plan(
            DropPlanningContext(
                candidates: candidates,
                destination: destination,
                availabilityBySourceURL: availability,
                collidingSourceURLs: collisions
            )
        )

        guard let sourceLeases else {
            return result
        }

        let preparedTokens = inspections.compactMap(\.sourceLeaseToken)
        guard case let .copy(plan) = result else {
            await sourceLeases.releasePrepared(tokens: preparedTokens)
            return result
        }

        guard plan.items.count == inspections.count else {
            await sourceLeases.releasePrepared(tokens: preparedTokens)
            return .reject(.sourceUnavailable)
        }

        var boundOperationIDs: [UUID] = []
        boundOperationIDs.reserveCapacity(plan.items.count)

        do {
            for (item, inspection) in zip(plan.items, inspections) {
                guard let token = inspection.sourceLeaseToken else {
                    throw SourceFileLeaseError.sourceUnavailable
                }
                try await sourceLeases.bind(token: token, operationID: item.operationID)
                boundOperationIDs.append(item.operationID)
            }
            return result
        } catch {
            await sourceLeases.releasePrepared(tokens: preparedTokens)
            await sourceLeases.releaseBound(operationIDs: boundOperationIDs)
            return .reject(.sourceUnavailable)
        }
    }
}
