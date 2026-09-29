import Foundation
import SchneeGlassDomain
import Testing

@testable import SchneeGlassApplication

private enum RecoveryCenterCancellationAccessMode: Sendable {
  case normal
  case throwCancellation
  case cancelAndReturn
}

private actor RecoveryCenterCancellationStore: PendingCopyRecording {
  private var values: [PendingCopyRecord]
  private let cancelRecordsOnCall: Int?
  private let cancelRemoveBeforeCommit: Bool
  private let cancelTaskAfterRemoveCommit: Bool
  private var recordsCount = 0
  private var removeCount = 0

  init(
    records: [PendingCopyRecord],
    cancelRecordsOnCall: Int? = nil,
    cancelRemoveBeforeCommit: Bool = false,
    cancelTaskAfterRemoveCommit: Bool = false
  ) {
    self.values = records
    self.cancelRecordsOnCall = cancelRecordsOnCall
    self.cancelRemoveBeforeCommit = cancelRemoveBeforeCommit
    self.cancelTaskAfterRemoveCommit = cancelTaskAfterRemoveCommit
  }

  func records() async throws -> [PendingCopyRecord] {
    recordsCount += 1
    if recordsCount == cancelRecordsOnCall {
      throw CancellationError()
    }
    return values
  }

  func upsert(_ record: PendingCopyRecord) async throws {
    values.removeAll { $0.operationID == record.operationID }
    values.append(record)
  }

  func remove(operationID: UUID) async throws {
    removeCount += 1
    if cancelRemoveBeforeCommit {
      throw CancellationError()
    }

    values.removeAll { $0.operationID == operationID }
    if cancelTaskAfterRemoveCommit {
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
    }
  }

  func counts() -> (records: Int, removes: Int) {
    (recordsCount, removeCount)
  }

  func current() -> [PendingCopyRecord] {
    values
  }
}

private actor RecoveryCenterCancellationConfigurationStore: ConfigurationPersisting {
  private let configurations: [GlassConfiguration]
  private let cancelLoadOnCall: Int?
  private var loadCount = 0

  init(
    configurations: [GlassConfiguration],
    cancelLoadOnCall: Int? = nil
  ) {
    self.configurations = configurations
    self.cancelLoadOnCall = cancelLoadOnCall
  }

  func load() async throws -> [GlassConfiguration] {
    loadCount += 1
    if loadCount == cancelLoadOnCall {
      throw CancellationError()
    }
    return configurations
  }

  func save(_ configurations: [GlassConfiguration]) async throws {
    _ = configurations
  }

  func loads() -> Int {
    loadCount
  }
}

private actor RecoveryCenterCancellationAccessController: FolderAccessControlling {
  private let mode: RecoveryCenterCancellationAccessMode
  private var acquisitionCount = 0
  private var releaseCount = 0

  init(mode: RecoveryCenterCancellationAccessMode = .normal) {
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

private actor RecoveryCenterCancellationInspector: PendingCopyRecoveryInspecting {
  private let disposition: PendingCopyRecoveryDisposition
  private let cancelDuringAssessment: Bool
  private var assessmentCount = 0

  init(
    disposition: PendingCopyRecoveryDisposition,
    cancelDuringAssessment: Bool = false
  ) {
    self.disposition = disposition
    self.cancelDuringAssessment = cancelDuringAssessment
  }

  func assess(
    _ record: PendingCopyRecord,
    destinationAccess: FolderAccessHandle
  ) async -> PendingCopyRecoveryAssessment {
    _ = destinationAccess
    assessmentCount += 1

    if cancelDuringAssessment {
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

private actor RecoveryCenterCancellationCleaner: PendingCopyOwnedStagingCleaning {
  private let cancelBeforeCommit: Bool
  private var cleanupCount = 0

  init(cancelBeforeCommit: Bool = false) {
    self.cancelBeforeCommit = cancelBeforeCommit
  }

  func removeOwnedStaging(
    record: PendingCopyRecord,
    destinationAccess: FolderAccessHandle
  ) async throws {
    _ = record
    _ = destinationAccess
    cleanupCount += 1

    if cancelBeforeCommit {
      throw CancellationError()
    }
  }

  func count() -> Int {
    cleanupCount
  }
}

private func recoveryCenterCancellationConfiguration(
  glassID: GlassID
) throws -> GlassConfiguration {
  try GlassConfiguration(
    id: glassID,
    title: "Documents",
    source: FolderSource(
      bookmarkData: Data([1]),
      lastKnownPath: "/tmp/Documents"
    ),
    placement: GlassPlacement(x: 0, y: 0)
  )
}

private func recoveryCenterCancellationRecord(
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
    createdAt: Date(timeIntervalSince1970: 1_700_000_000),
    state: .staging
  )
}

private func recoveryCenterCancellationFixture(
  disposition: PendingCopyRecoveryDisposition = .metadataOnly,
  cancelRecordsOnCall: Int? = nil,
  cancelConfigurationLoadOnCall: Int? = nil,
  cancelRemoveBeforeCommit: Bool = false,
  cancelTaskAfterRemoveCommit: Bool = false,
  accessMode: RecoveryCenterCancellationAccessMode = .normal,
  cancelDuringAssessment: Bool = false,
  cancelCleanerBeforeCommit: Bool = false
) throws -> (
  useCase: PendingCopyRecoveryCenterUseCase,
  record: PendingCopyRecord,
  store: RecoveryCenterCancellationStore,
  configurationStore: RecoveryCenterCancellationConfigurationStore,
  access: RecoveryCenterCancellationAccessController,
  inspector: RecoveryCenterCancellationInspector,
  cleaner: RecoveryCenterCancellationCleaner,
  gate: FileOperationActivityGate
) {
  let glassID = GlassID()
  let record = recoveryCenterCancellationRecord(glassID: glassID)
  let configuration = try recoveryCenterCancellationConfiguration(glassID: glassID)
  let store = RecoveryCenterCancellationStore(
    records: [record],
    cancelRecordsOnCall: cancelRecordsOnCall,
    cancelRemoveBeforeCommit: cancelRemoveBeforeCommit,
    cancelTaskAfterRemoveCommit: cancelTaskAfterRemoveCommit
  )
  let configurationStore = RecoveryCenterCancellationConfigurationStore(
    configurations: [configuration],
    cancelLoadOnCall: cancelConfigurationLoadOnCall
  )
  let access = RecoveryCenterCancellationAccessController(mode: accessMode)
  let inspector = RecoveryCenterCancellationInspector(
    disposition: disposition,
    cancelDuringAssessment: cancelDuringAssessment
  )
  let cleaner = RecoveryCenterCancellationCleaner(
    cancelBeforeCommit: cancelCleanerBeforeCommit
  )
  let gate = FileOperationActivityGate()
  let execution = PendingCopyRecoveryExecutionUseCase(
    pendingCopyStore: store,
    recoveryInspector: inspector,
    ownedStagingCleaner: cleaner
  )
  let useCase = PendingCopyRecoveryCenterUseCase(
    pendingCopyStore: store,
    configurationStore: configurationStore,
    accessController: access,
    recoveryInspector: inspector,
    recoveryExecution: execution,
    activityGate: gate
  )

  return (
    useCase,
    record,
    store,
    configurationStore,
    access,
    inspector,
    cleaner,
    gate
  )
}

@Test
func preCancelledRecoveryCenterListingStopsBeforeStoreRead() async throws {
  let fixture = try recoveryCenterCancellationFixture()

  let task = Task {
    withUnsafeCurrentTask { current in
      current?.cancel()
    }
    return try await fixture.useCase.loadItems()
  }

  do {
    _ = try await task.value
    Issue.record("Expected cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  #expect(await fixture.store.counts().records == 0)
  #expect(await fixture.configurationStore.loads() == 0)
  #expect(await fixture.access.counts().acquired == 0)
}

@Test
func recoveryCenterListingPropagatesRecordLoadCancellation() async throws {
  let fixture = try recoveryCenterCancellationFixture(cancelRecordsOnCall: 1)

  do {
    _ = try await fixture.useCase.loadItems()
    Issue.record("Expected cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  #expect(await fixture.configurationStore.loads() == 0)
  #expect(await fixture.access.counts().acquired == 0)
}

@Test
func recoveryCenterListingPropagatesConfigurationLoadCancellation() async throws {
  let fixture = try recoveryCenterCancellationFixture(
    cancelConfigurationLoadOnCall: 1
  )

  do {
    _ = try await fixture.useCase.loadItems()
    Issue.record("Expected cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  #expect(await fixture.access.counts().acquired == 0)
}

@Test
func recoveryCenterListingDoesNotConvertAccessCancellationToUnavailable() async throws {
  let fixture = try recoveryCenterCancellationFixture(
    accessMode: .throwCancellation
  )

  do {
    _ = try await fixture.useCase.loadItems()
    Issue.record("Expected cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  #expect(await fixture.access.counts().acquired == 1)
  #expect(await fixture.access.counts().released == 0)
}

@Test
func recoveryCenterListingReleasesAccessWhenCancellationAppearsAfterAcquire() async throws {
  let fixture = try recoveryCenterCancellationFixture(
    accessMode: .cancelAndReturn
  )

  do {
    _ = try await fixture.useCase.loadItems()
    Issue.record("Expected cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  #expect(await fixture.access.counts().acquired == 1)
  #expect(await fixture.access.counts().released == 1)
  #expect(await fixture.inspector.count() == 0)
}

@Test
func recoveryCenterListingReleasesAccessWhenAssessmentCancelsTask() async throws {
  let fixture = try recoveryCenterCancellationFixture(
    cancelDuringAssessment: true
  )

  do {
    _ = try await fixture.useCase.loadItems()
    Issue.record("Expected cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  #expect(await fixture.access.counts().acquired == 1)
  #expect(await fixture.access.counts().released == 1)
  #expect(await fixture.inspector.count() == 1)
}

@Test
func recoveryCenterMutationCancellationReleasesLeaseBeforeAnyAccess() async throws {
  let fixture = try recoveryCenterCancellationFixture(cancelRecordsOnCall: 1)

  do {
    try await fixture.useCase.executeMutation(
      action: .discardMetadata,
      operationID: fixture.record.operationID
    )
    Issue.record("Expected cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  #expect(await fixture.access.counts().acquired == 0)
  #expect(!(await fixture.gate.hasActiveRecoveryMutation()))
  #expect(await fixture.gate.beginCopy())
  await fixture.gate.endCopy()
}

@Test
func metadataMutationCancellationPropagatesAndReleasesAccessAndLease() async throws {
  let fixture = try recoveryCenterCancellationFixture(
    cancelRemoveBeforeCommit: true
  )

  do {
    try await fixture.useCase.executeMutation(
      action: .discardMetadata,
      operationID: fixture.record.operationID
    )
    Issue.record("Expected cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  #expect(await fixture.store.counts().removes == 1)
  #expect(await fixture.access.counts().released == 1)
  #expect(!(await fixture.gate.hasActiveRecoveryMutation()))
}

@Test
func ownedStagingCleanupCancellationPropagatesAndReleasesAccessAndLease() async throws {
  let verification = PendingCopyFileVerification(
    size: .matchesExpectedSize,
    resourceIdentity: .matchesRecordedIdentity
  )
  let fixture = try recoveryCenterCancellationFixture(
    disposition: .stagingPresent(verification),
    cancelCleanerBeforeCommit: true
  )

  do {
    try await fixture.useCase.executeMutation(
      action: .removeOwnedStaging,
      operationID: fixture.record.operationID
    )
    Issue.record("Expected cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  #expect(await fixture.cleaner.count() == 1)
  #expect(await fixture.access.counts().released == 1)
  #expect(!(await fixture.gate.hasActiveRecoveryMutation()))
}

@Test
func cancellationAfterSuccessfulMetadataCommitDoesNotRollBackResult() async throws {
  let fixture = try recoveryCenterCancellationFixture(
    cancelTaskAfterRemoveCommit: true
  )

  try await fixture.useCase.executeMutation(
    action: .discardMetadata,
    operationID: fixture.record.operationID
  )

  #expect(await fixture.store.counts().removes == 1)
  #expect(await fixture.store.current().isEmpty)
  #expect(await fixture.access.counts().released == 1)
  #expect(!(await fixture.gate.hasActiveRecoveryMutation()))
}
