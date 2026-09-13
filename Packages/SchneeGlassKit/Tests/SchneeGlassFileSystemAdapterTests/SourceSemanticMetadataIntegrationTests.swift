import Foundation
import Testing
@testable import SchneeGlassFileSystemAdapter

private final class SequenceSourceSemanticMetadataReader: SourceSemanticMetadataReading, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [SourceSemanticMetadata]

    init(_ values: [SourceSemanticMetadata]) {
        self.values = values
    }

    func metadata(at url: URL) throws -> SourceSemanticMetadata {
        _ = url
        lock.lock()
        defer { lock.unlock() }
        guard !values.isEmpty else {
            throw CocoaError(.fileReadUnknown)
        }
        return values.removeFirst()
    }
}

private func makeSemanticMetadataSourceFile() throws -> (root: URL, source: URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-source-semantics-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("payload.txt", isDirectory: false)
    try Data("payload".utf8).write(to: source)
    return (root, source)
}

@Test
func sourceInspectionRejectsUnknownSemanticMetadataBeforePlanningAuthority() async throws {
    let fixture = try makeSemanticMetadataSourceFile()
    defer { try? FileManager.default.removeItem(at: fixture.root) }

    let reader = SequenceSourceSemanticMetadataReader([
        SourceSemanticMetadata(isAlias: nil, isPackage: false),
    ])
    let inspector = FoundationDropFileSystemInspector(
        fileManager: .default,
        sourceSemanticMetadataReader: reader
    )

    let inspection = await inspector.inspectSource(at: fixture.source)

    #expect(inspection.candidate.kind == .unsupported)
    #expect(inspection.availability == .sourceUnavailable)
    #expect(inspection.sourceLeaseToken == nil)
}

@Test
func sourceInspectionReleasesPreparedLeaseWhenPinnedSemanticMetadataBecomesUnknown() async throws {
    let fixture = try makeSemanticMetadataSourceFile()
    defer { try? FileManager.default.removeItem(at: fixture.root) }

    let leases = SourceFileLeaseRegistry()
    let reader = SequenceSourceSemanticMetadataReader([
        SourceSemanticMetadata(isAlias: false, isPackage: false),
        SourceSemanticMetadata(isAlias: nil, isPackage: false),
    ])
    let inspector = FoundationDropFileSystemInspector(
        fileManager: .default,
        sourceLeases: leases,
        sourceSemanticMetadataReader: reader
    )

    let inspection = await inspector.inspectSource(at: fixture.source)

    #expect(inspection.candidate.kind == .unsupported)
    #expect(inspection.availability == .sourceUnavailable)
    #expect(inspection.sourceLeaseToken == nil)
    #expect(await leases.activeLeaseCount() == 0)
}

@Test
func foundationCopySourceMetadataRejectsUnknownSemanticMetadata() async throws {
    let fixture = try makeSemanticMetadataSourceFile()
    defer { try? FileManager.default.removeItem(at: fixture.root) }

    let reader = SequenceSourceSemanticMetadataReader([
        SourceSemanticMetadata(isAlias: false, isPackage: nil),
    ])
    let accessor = FoundationCopyFileSystemAccessor(
        fileManager: .default,
        sourceSemanticMetadataReader: reader
    )

    do {
        _ = try await accessor.sourceMetadata(at: fixture.source)
        Issue.record("Expected unknown source semantic metadata to fail closed")
    } catch let error as CopyFileSystemError {
        #expect(error == .unsupportedItem)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
