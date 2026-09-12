import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import SchneeGlassPOSIXSupport
import Testing
@testable import SchneeGlassFileSystemAdapter

private actor FakeDropInspector: DropFileSystemInspecting {
    var destination: DestinationDescriptor?
    var inspections: [URL: DropSourceInspection]
    var existingItems: Set<URL>

    init(
        destination: DestinationDescriptor?,
        inspections: [URL: DropSourceInspection],
        existingItems: Set<URL> = []
    ) {
        self.destination = destination
        self.inspections = Dictionary(
            uniqueKeysWithValues: inspections.map { ($0.key.standardizedFileURL, $0.value) }
        )
        self.existingItems = Set(existingItems.map(\.standardizedFileURL))
    }

    func inspectSource(at url: URL) async -> DropSourceInspection {
        inspections[url.standardizedFileURL]
            ?? DropSourceInspection(
                candidate: DropCandidate(url: url.standardizedFileURL, kind: .unsupported),
                availability: .sourceUnavailable
            )
    }

    func destinationDescriptor(for access: FolderAccessHandle) async -> DestinationDescriptor? {
        _ = access
        return destination
    }

    func itemExists(at url: URL) async -> Bool {
        existingItems.contains(url.standardizedFileURL)
    }
}

private actor DropRuntimeIdentityReader: RuntimeDirectoryIdentityReading {
    private let values: [POSIXDirectoryIdentity?]
    private var index = 0
    private(set) var observedURLs: [URL] = []

    init(_ values: [POSIXDirectoryIdentity?]) {
        self.values = values
    }

    func identity(for url: URL) async -> POSIXDirectoryIdentity? {
        observedURLs.append(url.standardizedFileURL)
        guard !values.isEmpty else {
            return nil
        }
        let current = min(index, values.count - 1)
        index += 1
        return values[current]
    }

    func urls() -> [URL] {
        observedURLs
    }
}

private func dropDestination(
    url: URL = URL(fileURLWithPath: "/tmp/DropDestination", isDirectory: true),
    locationKind: StorageLocationKind = .localFixed,
    isWritable: Bool = true,
    supportsCaseSensitiveNames: Bool? = false,
    supportsSafeDestinationCommit: Bool? = true
) -> (FolderAccessHandle, DestinationDescriptor) {
    let glassID = GlassID()
    let access = FolderAccessHandle(glassID: glassID, url: url)
    let descriptor = DestinationDescriptor(
        glassID: glassID,
        folderIdentity: FolderIdentity(resourceIdentifier: "destination", standardizedURL: url),
        url: url,
        capabilities: StorageCapabilities(
            locationKind: locationKind,
            isWritable: isWritable,
            supportsCaseSensitiveNames: supportsCaseSensitiveNames,
            supportsSafeDestinationCommit: supportsSafeDestinationCommit
        )
    )
    return (access, descriptor)
}

private func makeDropDestinationRoot(_ name: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "schneeglass-drop-destination-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func acquiredRuntimeIdentity(for url: URL) throws -> RuntimeDirectoryIdentity {
    let identity = try #require(POSIXDirectoryIdentityReader.identity(at: url))
    return RuntimeDirectoryIdentity(
        deviceIdentifier: identity.device,
        objectIdentifier: identity.inode
    )
}

@Test
func nativeDropPlanningBuildsCopyPlanForRegularFile() async throws {
    let source = URL(fileURLWithPath: "/tmp/Source/report.txt")
    let (access, descriptor) = dropDestination()
    let inspector = FakeDropInspector(
        destination: descriptor,
        inspections: [
            source: DropSourceInspection(
                candidate: DropCandidate(url: source, kind: .regular, size: 42),
                availability: .available
            )
        ]
    )
    let planner = NativeDropPlanningAdapter(inspector: inspector)

    let result = await planner.plan(sourceURLs: [source], destinationAccess: access)

    guard case let .copy(plan) = result else {
        Issue.record("Expected copy plan")
        return
    }
    #expect(plan.destination == descriptor)
    #expect(plan.items.count == 1)
    #expect(plan.items[0].sourceURL == source.standardizedFileURL)
    #expect(plan.items[0].destinationFilename == "report.txt")
    #expect(plan.items[0].expectedSize == 42)
}

@Test
func nativeDropPreviewAndPlanningRejectUnsafeDestinationCommit() async {
    let source = URL(fileURLWithPath: "/tmp/Source/report.txt")
    let (access, descriptor) = dropDestination(supportsSafeDestinationCommit: false)
    let inspector = FakeDropInspector(
        destination: descriptor,
        inspections: [
            source: DropSourceInspection(
                candidate: DropCandidate(url: source, kind: .regular, size: 42),
                availability: .available
            )
        ]
    )
    let planner = NativeDropPlanningAdapter(inspector: inspector)

    #expect(
        await planner.preview(sourceURLs: [source], destinationAccess: access)
            == .reject(.destinationCopySafetyUnsupported)
    )
    #expect(
        await planner.plan(sourceURLs: [source], destinationAccess: access)
            == .reject(.destinationCopySafetyUnsupported)
    )
}

@Test
func nativeDropPlanningRejectsExistingDestinationCollision() async {
    let source = URL(fileURLWithPath: "/tmp/Source/report.txt")
    let (access, descriptor) = dropDestination()
    let collision = descriptor.url.appendingPathComponent("report.txt")
    let inspector = FakeDropInspector(
        destination: descriptor,
        inspections: [
            source: DropSourceInspection(
                candidate: DropCandidate(url: source, kind: .regular, size: 42),
                availability: .available
            )
        ],
        existingItems: [collision]
    )
    let planner = NativeDropPlanningAdapter(inspector: inspector)

    #expect(await planner.plan(sourceURLs: [source], destinationAccess: access) == .reject(.collision))
}

@Test
func nativeDropPlanningRejectsUnsupportedFolderBeforeMutation() async {
    let source = URL(fileURLWithPath: "/tmp/Source/Folder", isDirectory: true)
    let (access, descriptor) = dropDestination()
    let inspector = FakeDropInspector(
        destination: descriptor,
        inspections: [
            source: DropSourceInspection(
                candidate: DropCandidate(url: source, kind: .directory),
                availability: .available
            )
        ]
    )
    let planner = NativeDropPlanningAdapter(inspector: inspector)

    #expect(await planner.plan(sourceURLs: [source], destinationAccess: access) == .reject(.unsupportedFolder))
}

@Test
func nativeDropPlanningRejectsCloudPlaceholderWithoutDownloadingIt() async {
    let source = URL(fileURLWithPath: "/tmp/Source/cloud.txt")
    let (access, descriptor) = dropDestination()
    let inspector = FakeDropInspector(
        destination: descriptor,
        inspections: [
            source: DropSourceInspection(
                candidate: DropCandidate(url: source, kind: .regular),
                availability: .cloudPlaceholderUnavailable
            )
        ]
    )
    let planner = NativeDropPlanningAdapter(inspector: inspector)

    #expect(await planner.plan(sourceURLs: [source], destinationAccess: access) == .reject(.cloudPlaceholderUnavailable))
}

@Test
func nativeDropPlanningRejectsUnavailableDestination() async {
    let source = URL(fileURLWithPath: "/tmp/Source/report.txt")
    let access = FolderAccessHandle(
        glassID: GlassID(),
        url: URL(fileURLWithPath: "/tmp/MissingDestination", isDirectory: true)
    )
    let inspector = FakeDropInspector(destination: nil, inspections: [:])
    let planner = NativeDropPlanningAdapter(inspector: inspector)

    #expect(await planner.plan(sourceURLs: [source], destinationAccess: access) == .reject(.destinationUnavailable))
}

@Test
func dropInspectorAcceptsDestinationMatchingAcquiredRuntimeIdentity() async throws {
    let destination = try makeDropDestinationRoot("runtime-match")
    defer { try? FileManager.default.removeItem(at: destination) }

    let observed = POSIXDirectoryIdentity(device: 7, inode: 41)
    let identityReader = DropRuntimeIdentityReader([observed, observed])
    let inspector = FoundationDropFileSystemInspector(runtimeIdentityReader: identityReader)
    let access = FolderAccessHandle(
        glassID: GlassID(),
        url: destination,
        fingerprint: nil,
        runtimeDirectoryIdentity: RuntimeDirectoryIdentity(
            deviceIdentifier: observed.device,
            objectIdentifier: observed.inode
        )
    )

    let descriptor = try #require(await inspector.destinationDescriptor(for: access))

    #expect(descriptor.folderIdentity.resourceIdentifier == nil)
    #expect(descriptor.capabilities.supportsSafeDestinationCommit == true)
    #expect(await identityReader.urls() == [destination.standardizedFileURL, destination.standardizedFileURL])
}

@Test
func dropInspectorRejectsDestinationThatDoesNotMatchAcquiredRuntimeIdentity() async throws {
    let destination = try makeDropDestinationRoot("runtime-mismatch")
    defer { try? FileManager.default.removeItem(at: destination) }

    let identityReader = DropRuntimeIdentityReader([
        POSIXDirectoryIdentity(device: 7, inode: 99),
    ])
    let inspector = FoundationDropFileSystemInspector(runtimeIdentityReader: identityReader)
    let access = FolderAccessHandle(
        glassID: GlassID(),
        url: destination,
        fingerprint: nil,
        runtimeDirectoryIdentity: RuntimeDirectoryIdentity(
            deviceIdentifier: 7,
            objectIdentifier: 41
        )
    )

    #expect(await inspector.destinationDescriptor(for: access) == nil)
    #expect(await identityReader.urls() == [destination.standardizedFileURL])
}

@Test
func dropInspectorFailsClosedWhenAcquiredRuntimeIdentityDisappearsDuringInspection() async throws {
    let destination = try makeDropDestinationRoot("runtime-disappears")
    defer { try? FileManager.default.removeItem(at: destination) }

    let observed = POSIXDirectoryIdentity(device: 7, inode: 41)
    let identityReader = DropRuntimeIdentityReader([observed, nil])
    let inspector = FoundationDropFileSystemInspector(runtimeIdentityReader: identityReader)
    let access = FolderAccessHandle(
        glassID: GlassID(),
        url: destination,
        fingerprint: nil,
        runtimeDirectoryIdentity: RuntimeDirectoryIdentity(
            deviceIdentifier: observed.device,
            objectIdentifier: observed.inode
        )
    )

    #expect(await inspector.destinationDescriptor(for: access) == nil)
    #expect(await identityReader.urls() == [destination.standardizedFileURL, destination.standardizedFileURL])
}

@Test
func dropInspectorKeepsExistingDestinationVisibleWithoutAcquiredDirectoryProof() async throws {
    let destination = try makeDropDestinationRoot("missing-proof")
    defer { try? FileManager.default.removeItem(at: destination) }

    let inspector = FoundationDropFileSystemInspector()
    let access = FolderAccessHandle(glassID: GlassID(), url: destination)
    let descriptor = try #require(await inspector.destinationDescriptor(for: access))

    #expect(descriptor.folderIdentity.resourceIdentifier == nil)
    #expect(descriptor.capabilities.supportsSafeDestinationCommit == false)
}

@Test
func dropInspectorUsesFoundationDirectoryIdentifierOnlyAsFallback() async throws {
    let destination = try makeDropDestinationRoot("foundation-fallback")
    defer { try? FileManager.default.removeItem(at: destination) }

    let values = try destination.resourceValues(forKeys: [.fileResourceIdentifierKey])
    let resourceIdentifier = try #require(
        values.fileResourceIdentifier.map { String(describing: $0) }
    )
    let access = FolderAccessHandle(
        glassID: GlassID(),
        url: destination,
        fingerprint: ResourceFingerprint(
            volumeIdentifier: nil,
            resourceIdentifier: resourceIdentifier
        )
    )
    let inspector = FoundationDropFileSystemInspector()

    let descriptor = try #require(await inspector.destinationDescriptor(for: access))

    #expect(descriptor.folderIdentity.resourceIdentifier == resourceIdentifier)
    #expect(descriptor.capabilities.supportsSafeDestinationCommit == true)
}

@Test
func dropInspectorRejectsMismatchedFoundationFallbackIdentity() async throws {
    let destination = try makeDropDestinationRoot("foundation-mismatch")
    defer { try? FileManager.default.removeItem(at: destination) }

    let access = FolderAccessHandle(
        glassID: GlassID(),
        url: destination,
        fingerprint: ResourceFingerprint(
            volumeIdentifier: nil,
            resourceIdentifier: "not-the-selected-directory"
        )
    )
    let inspector = FoundationDropFileSystemInspector()

    #expect(await inspector.destinationDescriptor(for: access) == nil)
}

@Test
func realDropInspectorPlansLocalRegularFileWithoutMutation() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-drop-plan-\(UUID().uuidString)", isDirectory: true)
    let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
    let destinationDirectory = root.appendingPathComponent("destination", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let source = sourceDirectory.appendingPathComponent("payload.txt")
    try Data("payload".utf8).write(to: source)
    let access = FolderAccessHandle(
        glassID: GlassID(),
        url: destinationDirectory,
        runtimeDirectoryIdentity: try acquiredRuntimeIdentity(for: destinationDirectory)
    )
    let planner = NativeDropPlanningAdapter()

    let result = await planner.plan(sourceURLs: [source], destinationAccess: access)

    guard case let .copy(plan) = result else {
        Issue.record("Expected real filesystem copy plan, got \(result)")
        return
    }
    #expect(plan.destination.capabilities.supportsSafeDestinationCommit == true)
    #expect(plan.destination.folderIdentity.resourceIdentifier == nil)
    #expect(plan.items.count == 1)
    #expect(plan.items[0].destinationFilename == "payload.txt")
    #expect(!FileManager.default.fileExists(
        atPath: destinationDirectory.appendingPathComponent("payload.txt").path
    ))
}
