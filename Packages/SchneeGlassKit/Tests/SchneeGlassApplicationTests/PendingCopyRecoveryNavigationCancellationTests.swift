import Foundation
import SchneeGlassDomain
import Testing

@testable import SchneeGlassApplication

private enum RecoveryNavigationCancellationAccessMode: Sendable {
  case normal
  case throwCancellation
  case cancelAndReturn
}

private actor RecoveryNavigationCancellationRecordStore: PendingCopyRecording {
  private let values: [PendingCopyRecord]
  private let cancelOnCall: Int?
  private var callCount = 0

  init(
    records: [PendingCopyRecord],
    cancelOnCall: Int? = nil
  ) {
    self.values = records
    self.cancelOnCall = cancelOnCall
  }

  func records() async throws -> [PendingCopyRecord] {
    callCount += 1
    if callCount == cancelOnCall {
      throw CancellationError()
    }
    return values
  }

  func upsert(_ record: PendingCopyRecord) async throws {
    _ = record
  }

  func remove(operationID: UUID) async throws {
    _ = operationID
  }

  func calls() -> Int {
    callCount
  }
}

private actor RecoveryNavigationCancellationConfigurationStore: ConfigurationPersisting {
  private let values: [GlassConfiguration]
  private let cancelOnCall: Int?
  private var callCount = 0

  init(
    configurations: [GlassConfiguration],
    cancelOnCall: Int? = nil
  ) {
    self.values = configurations
    self.cancelOnCall = cancelOnCall
  }

  func load() async throws -> [GlassConfiguration] {
    callCount += 1
    if callCount == cancelOnCall {
      throw CancellationError()
    }
    return values
  }

  func save(_ configurations: [GlassConfiguration]) async throws {
    _ = configurations
  }

  func calls() -> Int {
    callCount
  }
}

private actor RecoveryNavigationCancellationAccessController: FolderAccessControlling {
  private let mode: RecoveryNavigationCancellationAccessMode
  private var acquisitionCount = 0
  private var releaseCount = 0

  init(mode: RecoveryNavigationCancellationAccessMode = .normal) {
    self.mode = mode
  }

  func acquire(
    source: FolderSource,
    glassID: GlassID
  ) async throws -> FolderAccessAcquisition {
    acquisitionCount += 1

    switch mode {
    case .normal:
      break
    case .throwCancellation:
      throw CancellationError()
    case .cancelAndReturn:
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
    }

    return FolderAccessAcquisition(
      handle: FolderAccessHandle(
        glassID: glassID,
        url: URL(fileURLWithPath: source.lastKnownPath, isDirectory: true)
      )
    )
  }

  func release(handleID: UUID) async {
    _ = handleID
    releaseCount += 1
  }

  func counts() -> (acquired: Int, released: Int) {
    (acquisitionCount, releaseCount)
  }
}

private actor RecoveryNavigationCancellationInspector: PendingCopyRecoveryInspecting {
  private let disposition: PendingCopyRecoveryDisposition
  private let cancelOnAssessment: Int?
  private var assessmentCount = 0

  init(
    disposition: PendingCopyRecoveryDisposition,
    cancelOnAssessment: Int? = nil
  ) {
    self.disposition = disposition
    self.cancelOnAssessment = cancelOnAssessment
  }

  func assess(
    _ record: PendingCopyRecord,
    destinationAccess: FolderAccessHandle
  ) async -> PendingCopyRecoveryAssessment {
    _ = destinationAccess
    assessmentCount += 1

    if assessmentCount == cancelOnAssessment {
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
    }

    return PendingCopyRecoveryAssessment(
      record: record,
      disposition: disposition
    )
  }

  func count() -> Int {
    assessmentCount
  }
}

@MainActor
private final class RecoveryNavigationCancellationFileActor: WorkspaceFileActing {
  private let cancelDuringReveal: Bool
  private(set) var revealedURLs: [URL] = []

  init(cancelDuringReveal: Bool = false) {
    self.cancelDuringReveal = cancelDuringReveal
  }

  func open(url: URL) -> Bool {
    _ = url
    return true
  }

  func reveal(url: URL) {
    revealedURLs.append(url.standardizedFileURL)
    if cancelDuringReveal {
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
    }
  }
}

private func recoveryNavigationCancellationConfiguration(
  glassID: GlassID
) throws -> GlassConfiguration {
  try GlassConfiguration(
    id: glassID,
    title: "Documents",
    source: FolderSource(
      bookmarkData: Data([1]),
      lastKnownPath: "/tmp/RecoveryNavigation"
    ),
    placement: GlassPlacement(x: 0, y: 0)
  )
}

private func recoveryNavigationCancellationRecord(
  glassID: GlassID
) -> PendingCopyRecord {
  let operationID = UUID()
  return PendingCopyRecord(
    operationID: operationID,
    batchID: UUID(),
    destinationGlassID: glassID,
    stagingFilename: ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial",
    finalFilename: "report.txt",
    expectedSize: 7,
    stagingResourceIdentifier: "identity",
    state: .staging
  )
}

private func recoveryNavigationCancellationDisposition() -> PendingCopyRecoveryDisposition {
  .finalPresent(
    PendingCopyFileVerification(
      size: .sizeMismatch(expected: 7, actual: 9),
      resourceIdentity: .mismatchesRecordedIdentity
    )
  )
}

@MainActor
private func recoveryNavigationCancellationFixture(
  cancelRecordsOnCall: Int? = nil,
  cancelConfigurationOnCall: Int? = nil,
  accessMode: RecoveryNavigationCancellationAccessMode = .normal,
  cancelOnAssessment: Int? = nil,
  cancelDuringReveal: Bool = false
) throws -> (
  useCase: PendingCopyRecoveryNavigationUseCase,
  record: PendingCopyRecord,
  recordStore: RecoveryNavigationCancellationRecordStore,
  configurationStore: RecoveryNavigationCancellationConfigurationStore,
  access: RecoveryNavigationCancellationAccessController,
  inspector: RecoveryNavigationCancellationInspector,
  fileActor: RecoveryNavigationCancellationFileActor
) {
  let glassID = GlassID()
  let record = recoveryNavigationCancellationRecord(glassID: glassID)
  let configuration = try recoveryNavigationCancellationConfiguration(glassID: glassID)
  let recordStore = RecoveryNavigationCancellationRecordStore(
    records: [record],
    cancelOnCall: cancelRecordsOnCall
  )
  let configurationStore = RecoveryNavigationCancellationConfigurationStore(
    configurations: [configuration],
    cancelOnCall: cancelConfigurationOnCall
  )
  let access = RecoveryNavigationCancellationAccessController(mode: accessMode)
  let inspector = RecoveryNavigationCancellationInspector(
    disposition: recoveryNavigationCancellationDisposition(),
    cancelOnAssessment: cancelOnAssessment
  )
  let fileActor = RecoveryNavigationCancellationFileActor(
    cancelDuringReveal: cancelDuringReveal
  )
  let useCase = PendingCopyRecoveryNavigationUseCase(
    pendingCopyStore: recordStore,
    configurationStore: configurationStore,
    accessController: access,
    recoveryInspector: inspector,
    fileActor: fileActor
  )

  return (
    useCase,
    record,
    recordStore,
    configurationStore,
    access,
    inspector,
    fileActor
  )
}

@Test
@MainActor
func preCancelledRecoveryNavigationStopsBeforeStoreRead() async throws {
  let fixture = try recoveryNavigationCancellationFixture()

  let task = Task {
    withUnsafeCurrentTask { current in
      current?.cancel()
    }
    try await fixture.useCase.reveal(
      action: .revealFinal,
      operationID: fixture.record.operationID
    )
  }

  do {
    try await task.value
    Issue.record("Expected cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  #expect(await fixture.recordStore.calls() == 0)
  #expect(await fixture.configurationStore.calls() == 0)
  #expect(await fixture.access.counts().acquired == 0)
  #expect(fixture.fileActor.revealedURLs.isEmpty)
}

@Test
@MainActor
func recoveryNavigationPropagatesRecordLoadCancellation() async throws {
  let fixture = try recoveryNavigationCancellationFixture(
    cancelRecordsOnCall: 1
  )

  do {
    try await fixture.useCase.reveal(
      action: .revealFinal,
      operationID: fixture.record.operationID
    )
    Issue.record("Expected cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  #expect(await fixture.configurationStore.calls() == 0)
  #expect(await fixture.access.counts().acquired == 0)
  #expect(fixture.fileActor.revealedURLs.isEmpty)
}

@Test
@MainActor
func recoveryNavigationPropagatesConfigurationLoadCancellation() async throws {
  let fixture = try recoveryNavigationCancellationFixture(
    cancelConfigurationOnCall: 1
  )

  do {
    try await fixture.useCase.reveal(
      action: .revealFinal,
      operationID: fixture.record.operationID
    )
    Issue.record("Expected cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  #expect(await fixture.access.counts().acquired == 0)
  #expect(fixture.fileActor.revealedURLs.isEmpty)
}

@Test
@MainActor
func recoveryNavigationDoesNotConvertAccessCancellationToUnavailable() async throws {
  let fixture = try recoveryNavigationCancellationFixture(
    accessMode: .throwCancellation
  )

  do {
    try await fixture.useCase.reveal(
      action: .revealFinal,
      operationID: fixture.record.operationID
    )
    Issue.record("Expected cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  #expect(await fixture.access.counts().acquired == 1)
  #expect(await fixture.access.counts().released == 0)
  #expect(fixture.fileActor.revealedURLs.isEmpty)
}

@Test
@MainActor
func recoveryNavigationReleasesAccessWhenCancellationAppearsAfterAcquire() async throws {
  let fixture = try recoveryNavigationCancellationFixture(
    accessMode: .cancelAndReturn
  )

  do {
    try await fixture.useCase.reveal(
      action: .revealFinal,
      operationID: fixture.record.operationID
    )
    Issue.record("Expected cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  #expect(await fixture.access.counts().acquired == 1)
  #expect(await fixture.access.counts().released == 1)
  #expect(await fixture.inspector.count() == 0)
  #expect(fixture.fileActor.revealedURLs.isEmpty)
}

@Test
@MainActor
func recoveryNavigationCancellationAfterFirstAssessmentReleasesAccess() async throws {
  let fixture = try recoveryNavigationCancellationFixture(
    cancelOnAssessment: 1
  )

  do {
    try await fixture.useCase.reveal(
      action: .revealFinal,
      operationID: fixture.record.operationID
    )
    Issue.record("Expected cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  #expect(await fixture.inspector.count() == 1)
  #expect(await fixture.access.counts().released == 1)
  #expect(fixture.fileActor.revealedURLs.isEmpty)
}

@Test
@MainActor
func recoveryNavigationCancellationAfterSecondAssessmentPreventsReveal() async throws {
  let fixture = try recoveryNavigationCancellationFixture(
    cancelOnAssessment: 2
  )

  do {
    try await fixture.useCase.reveal(
      action: .revealFinal,
      operationID: fixture.record.operationID
    )
    Issue.record("Expected cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  #expect(await fixture.inspector.count() == 2)
  #expect(await fixture.access.counts().released == 1)
  #expect(fixture.fileActor.revealedURLs.isEmpty)
}

@Test
@MainActor
func cancellationDuringSuccessfulRevealDoesNotTurnCommittedRevealIntoFailure() async throws {
  let fixture = try recoveryNavigationCancellationFixture(
    cancelDuringReveal: true
  )

  let task = Task {
    try await fixture.useCase.reveal(
      action: .revealFinal,
      operationID: fixture.record.operationID
    )
    return true
  }

  let completed = try await task.value

  #expect(completed)
  #expect(
    fixture.fileActor.revealedURLs == [
      URL(fileURLWithPath: "/tmp/RecoveryNavigation/report.txt").standardizedFileURL
    ]
  )
  #expect(await fixture.access.counts().released == 1)
}
