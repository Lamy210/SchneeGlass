import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassPOSIXSupport

struct DropSourceInspection: Sendable {
    let candidate: DropCandidate
    let availability: DropCandidateAvailability
    let sourceLeaseToken: UUID?
    let planningRejection: DropRejection?

    init(
        candidate: DropCandidate,
        availability: DropCandidateAvailability,
        sourceLeaseToken: UUID? = nil,
        planningRejection: DropRejection? = nil
    ) {
        self.candidate = candidate
        self.availability = availability
        self.sourceLeaseToken = sourceLeaseToken
        self.planningRejection = planningRejection
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
    private let runtimeIdentityReader: any RuntimeDirectoryIdentityReading

    init(
        fileManager: FileManager = .default,
        sourceLeases: SourceFileLeaseRegistry? = nil,
        runtimeIdentityReader: any RuntimeDirectoryIdentityReading = POSIXRuntimeDirectoryIdentityReader()
    ) {
        self.fileManager = fileManager
        self.sourceLeases = sourceLeases
        self.runtimeIdentityReader = runtimeIdentityReader
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
        } catch let error as SourceFileLeaseError {
            if let preparedToken, let sourceLeases {
                await sourceLeases.releasePrepared(tokens: [preparedToken])
            }

            if case let .capacityExceeded(maximum) = error {
                return DropSourceInspection(
                    candidate: DropCandidate(url: source, kind: .unsupported),
                    availability: .sourceUnavailable,
                    planningRejection: .sourceCapacityReached(maximum: maximum)
                )
            }

            return DropSourceInspection(
                candidate: DropCandidate(url: source, kind: .unsupported),
                availability: .sourceUnavailable
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

    func destinationDescriptor(for access: FolderAccessHandle) async -> DestinationDescriptor? {
        let destination = access.url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return nil
        }

        let expectedRuntimeIdentity = access.runtimeDirectoryIdentity
        if let expectedRuntimeIdentity {
            guard await runtimeIdentityMatches(
                expected: expectedRuntimeIdentity,
                url: destination
            ) else {
                return nil
            }
        }

        do {
            var resourceKeys: Set<URLResourceKey> = [
                .volumeIsLocalKey,
                .volumeIsRemovableKey,
                .volumeIsReadOnlyKey,
                .volumeSupportsCaseSensitiveNamesKey,
                .volumeSupportsExclusiveRenamingKey,
            ]
            if expectedRuntimeIdentity == nil,
               access.fingerprint?.resourceIdentifier != nil
            {
                resourceKeys.insert(.fileResourceIdentifierKey)
            }

            let values = try destination.resourceValues(forKeys: resourceKeys)

            if let expectedRuntimeIdentity {
                // Bracket path-based capability reads with the identity captured when the
                // security-scoped access was acquired. Preview/planning may fail conservatively,
                // while the execution lease remains the final mutation authority.
                guard await runtimeIdentityMatches(
                    expected: expectedRuntimeIdentity,
                    url: destination
                ) else {
                    return nil
                }
            }

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

            let fallbackResourceIdentifier: String?
            if expectedRuntimeIdentity == nil,
               let expectedResourceIdentifier = access.fingerprint?.resourceIdentifier
            {
                guard let observedResourceIdentifier = values.fileResourceIdentifier.map({
                    String(describing: $0)
                }),
                observedResourceIdentifier == expectedResourceIdentifier
                else {
                    return nil
                }
                fallbackResourceIdentifier = observedResourceIdentifier
            } else {
                fallbackResourceIdentifier = nil
            }

            let hasDirectoryIdentity = expectedRuntimeIdentity != nil
                || fallbackResourceIdentifier != nil
            let supportsSafeDestinationCommit = hasDirectoryIdentity
                && values.volumeSupportsExclusiveRenaming == true

            return DestinationDescriptor(
                glassID: access.glassID,
                folderIdentity: FolderIdentity(
                    resourceIdentifier: fallbackResourceIdentifier,
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

    private func runtimeIdentityMatches(
        expected: RuntimeDirectoryIdentity,
        url: URL
    ) async -> Bool {
        guard let observed = await runtimeIdentityReader.identity(for: url) else {
            return false
        }
        return observed.device == expected.deviceIdentifier
            && observed.inode == expected.objectIdentifier
    }
}

public actor NativeDropPlanningAdapter: DropPlanning {
    /// Each accepted source is kept open from authoritative planning through copy execution.
    /// One plan and the shared source registry use the same conservative ceiling so parallel Glasses
    /// cannot multiply pinned source descriptors beyond the process-wide source budget.
    static let maximumSourceItemsPerPlan = SourceFileLeaseRegistry.defaultMaximumActiveLeases

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
        guard sourceURLs.count <= Self.maximumSourceItemsPerPlan else {
            return .reject(.tooManyItems(maximum: Self.maximumSourceItemsPerPlan))
        }

        return await makePlan(
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
        guard sourceURLs.count <= Self.maximumSourceItemsPerPlan else {
            return .reject(.tooManyItems(maximum: Self.maximumSourceItemsPerPlan))
        }

        return await makePlan(
            sourceURLs: sourceURLs,
            destinationAccess: destinationAccess,
            inspector: inspector,
            sourceLeases: sourceLeases
        )
    }

    public func abandon(_ request: AuthorizedCopyBatchRequest) async {
        guard let sourceLeases else {
            return
        }
        await sourceLeases.releaseBound(
            operationIDs: request.plan.items.map(\.operationID)
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
        var preparedTokens: [UUID] = []
        preparedTokens.reserveCapacity(sourceURLs.count)
        var candidates: [DropCandidate] = []
        candidates.reserveCapacity(sourceURLs.count)
        var availability: [URL: DropCandidateAvailability] = [:]
        var collisions: Set<URL> = []

        for rawURL in sourceURLs {
            let sourceURL = rawURL.standardizedFileURL
            let inspection = await inspector.inspectSource(at: sourceURL)
            inspections.append(inspection)
            if let token = inspection.sourceLeaseToken {
                preparedTokens.append(token)
            }

            if let rejection = inspection.planningRejection {
                if let sourceLeases {
                    await sourceLeases.releasePrepared(tokens: preparedTokens)
                }
                return .reject(rejection)
            }

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
