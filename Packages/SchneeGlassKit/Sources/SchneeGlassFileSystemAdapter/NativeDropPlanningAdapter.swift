import FileDomain
import Foundation
import SchneeGlassApplication

struct DropSourceInspection: Sendable {
    let candidate: DropCandidate
    let availability: DropCandidateAvailability
}

protocol DropFileSystemInspecting: Sendable {
    func inspectSource(at url: URL) async -> DropSourceInspection
    func destinationDescriptor(for access: FolderAccessHandle) async -> DestinationDescriptor?
    func itemExists(at url: URL) async -> Bool
}

actor FoundationDropFileSystemInspector: DropFileSystemInspecting {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func inspectSource(at url: URL) -> DropSourceInspection {
        let source = url.standardizedFileURL
        let didStart = source.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                source.stopAccessingSecurityScopedResource()
            }
        }

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

            return DropSourceInspection(
                candidate: DropCandidate(
                    url: source,
                    kind: kind,
                    size: (attributes[.size] as? NSNumber)?.int64Value
                ),
                availability: availability
            )
        } catch {
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
                    supportsCaseSensitiveNames: values.volumeSupportsCaseSensitiveNames
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

    public init() {
        self.inspector = FoundationDropFileSystemInspector()
    }

    init(inspector: any DropFileSystemInspecting) {
        self.inspector = inspector
    }

    public func plan(
        sourceURLs: [URL],
        destinationAccess: FolderAccessHandle
    ) async -> DropPlan {
        guard let destination = await inspector.destinationDescriptor(for: destinationAccess) else {
            return .reject(.destinationUnavailable)
        }

        var candidates: [DropCandidate] = []
        candidates.reserveCapacity(sourceURLs.count)
        var availability: [URL: DropCandidateAvailability] = [:]
        var collisions: Set<URL> = []

        for rawURL in sourceURLs {
            let sourceURL = rawURL.standardizedFileURL
            let inspection = await inspector.inspectSource(at: sourceURL)
            candidates.append(inspection.candidate)
            availability[sourceURL] = inspection.availability

            let finalURL = destination.url
                .appendingPathComponent(sourceURL.lastPathComponent, isDirectory: false)
                .standardizedFileURL
            if await inspector.itemExists(at: finalURL) {
                collisions.insert(sourceURL)
            }
        }

        return DropPlanner.plan(
            DropPlanningContext(
                candidates: candidates,
                destination: destination,
                availabilityBySourceURL: availability,
                collidingSourceURLs: collisions
            )
        )
    }
}
