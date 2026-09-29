import Foundation
import SchneeGlassDomain
import Testing

@testable import SchneeGlassApplication

private enum DestinationReconnectCancellationAccessMode: Sendable {
  case normal
  case throwCancellation
  case cancelAndReturn
}

private actor DestinationReconnectCancellationRecordStore: PendingCopyRecording {
  private let record: PendingCopyRecord
  private let cancelOnCall: Int?
  private var callCount = 0

  init(record: PendingCopyRecord, cancelOnCall: Int? = nil) {
    self.record = record
    self.cancelOnCall = cancelOnCall
  }

  func records() async throws -> [PendingCopyRecord] {
    callCount += 1
    if callCount == cancelOnCall {
      throw CancellationError()
    }
    return [record]
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

private actor DestinationReconnectCancellationConfigurationStore:
  ConditionalConfigurationPersisting
{
  private var values: [GlassConfiguration]
  private let cancelLoadOnCall: Int?
  private let cancelSaveBeforeCommit: Bool
  private let cancelTaskAfterCommit: Bool
  private var loadCount = 0
  private var saveCount = 0

  init(
    configuration: GlassConfiguration,
    cancelLoadOnCall: Int? = nil,
    cancelSaveBeforeCommit: Bool = false,
    cancelTaskAfterCommit: Bool = false
  ) {
    self.values = [configuration]
    self.cancelLoadOnCall = cancelLoadOnCall
    self.cancelSaveBeforeCommit = cancelSaveBeforeCommit
    self.cancelTaskAfterCommit = cancelTaskAfterCommit
  }

  func load() async throws -> [GlassConfiguration] {
    loadCount += 1
    if loadCount == cancelLoadOnCall {
      throw CancellationError()
    }
    return values
  }

  func save(_ configurations: [GlassConfiguration]) async throws {
    values = configurations
  }

  func save(
    _ configurations: [GlassConfiguration],
    ifCurrentMatches expectedCurrent: [GlassConfiguration]
  ) async throws -> Bool {
    saveCount += 1
    if cancelSaveBeforeCommit {
      throw CancellationError()
    }
    guard values == expectedCurrent else {
      return false
    }
    values = configurations
    if cancelTaskAfterCommit {
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
    }
    return true
  }

  func counts() -> (loads: Int, saves: Int) {
    (loadCount, saveCount)
  }

  func current() -> [GlassConfiguration] {
    values
  }
}

@MainActor
private final class DestinationReconnectCancellationSelector: FolderSelecting {
  private let selectedURL: URL?
  private let cancelAfterSelection: Bool

  init(
    selectedURL: URL?,
    cancelAfterSelection: Bool = false
  ) {
    self.selectedURL = selectedURL
    self.cancelAfterSelection = cancelAfterSelection
  }

  func selectFolder() async -> URL? {
    if cancelAfterSelection {
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
    }
    return selectedURL
  }
}

private actor DestinationReconnectCancellationSourceCreator: FolderSourceCreating {
  private let source: FolderSource
  private let cancel: Bool
  private var createCount = 0

  init(source: FolderSource, cancel: Bool = false) {
    self.source = source
    self.cancel = cancel
  }

  func createSource(for selectedURL: URL) async throws -> FolderSource {
    _ = selectedURL
    createCount += 1
    if cancel {
      throw CancellationError()
    }
    return source
  }

  func count() -> Int {
    createCount
  }
}

private actor DestinationReconnectCancellationAccess: FolderAccessControlling {
  private let mode: DestinationReconnectCancellationAccessMode
  private var acquireCount = 0
  private var releaseCount = 0

  init(mode: DestinationReconnectCancellationAccessMode = .normal) {
    self.mode = mode
  }

  func acquire(
    source: FolderSource,
    glassID: GlassID
  ) async throws -> FolderAccessAcquisition {
    acquireCount += 1
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
    (acquireCount, releaseCount)
  }
}

private func destinationReconnectCancellationIdentity() -> PersistentFolderIdentity {
  PersistentFolderIdentity(
    volumeUUIDString: "volume-uuid-A",
    documentIdentifier: 101
  )
}

private func destinationReconnectCancellationConfiguration(
  glassID: GlassID
) throws -> GlassConfiguration {
  try GlassConfiguration(
    id: glassID,
    title: "Documents",
    source: FolderSource(
      bookmarkData: Data([1]),
      lastKnownPath: "/old/Documents",
      persistentIdentity: destinationReconnectCancellationIdentity()
    ),
    placement: GlassPlacement(x: 10, y: 20),
    showOnAllSpaces: false,
    createdAt: Date(timeIntervalSince1970: 1_700_000_000)
  )
}

private func destinationReconnectCancellationRecord(
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
    stagingResourceIdentifier: "staging-identity",
    state: .staging
  )
}

@MainActor
private func destinationReconnectCancellationFixture(
  selectorCancels: Bool = false,
  sourceCancels: Bool = false,
  recordCancelOnCall: Int? = nil,
  configurationCancelLoadOnCall: Int? = nil,
  cancelSaveBeforeCommit: Bool = false,
  cancelTaskAfterCommit: Bool = false,
  accessMode: DestinationReconnectCancellationAccessMode = .normal
) throws -> (
  useCase: PendingCopyDestinationReconnectUseCase,
  record: PendingCopyRecord,
  recordStore: DestinationReconnectCancellationRecordStore,
  store: DestinationReconnectCancellationConfigurationStore,
  sourceCreator: DestinationReconnectCancellationSourceCreator,
  access: DestinationReconnectCancellationAccess,
  gate: FileOperationActivityGate
) {
  let glassID = GlassID()
  let record = destinationReconnectCancellationRecord(glassID: glassID)
  let configuration = try destinationReconnectCancellationConfiguration(glassID: glassID)
  let selectedSource = FolderSource(
    bookmarkData: Data([9]),
    lastKnownPath: "/new/Documents",
    persistentIdentity: destinationReconnectCancellationIdentity()
  )
  let recordStore = DestinationReconnectCancellationRecordStore(
    record: record,
    cancelOnCall: recordCancelOnCall
  )
  let store = DestinationReconnectCancellationConfigurationStore(
    configuration: configuration,
    cancelLoadOnCall: configurationCancelLoadOnCall,
    cancelSaveBeforeCommit: cancelSaveBeforeCommit,
    cancelTaskAfterCommit: cancelTaskAfterCommit
  )
  let sourceCreator = DestinationReconnectCancellationSourceCreator(
    source: selectedSource,
    cancel: sourceCancels
  )
  let access = DestinationReconnectCancellationAccess(mode: accessMode)
  let gate = FileOperationActivityGate()
  let useCase = PendingCopyDestinationReconnectUseCase(
    pendingCopyStore: recordStore,
    configurationStore: store,
    folderSelector: DestinationReconnectCancellationSelector(
      selectedURL: URL(fileURLWithPath: "/new/Documents", isDirectory: true),
      cancelAfterSelection: selectorCancels
    ),
    sourceCreator: sourceCreator,
    accessController: access,
    activityGate: gate
  )
  return (useCase, record, recordStore, store, sourceCreator, access, gate)
}

@Test
@MainActor
func preCancelledReconnectStopsBeforeRecoveryStateRead() async throws {
  let fixture = try destinationReconnectCancellationFixture()

  let task = Task {
    withUnsafeCurrentTask { current in
      current?.cancel()
    }
    return try await fixture.useCase.execute(operationID: fixture.record.operationID)
  }

  let result = try await task.value

  #expect(!result)
  #expect(await fixture.recordStore.calls() == 0)
  #expect(await fixture.store.counts().loads == 0)
  #expect(await fixture.sourceCreator.count() == 0)
  #expect(!(await fixture.gate.hasActiveRecoveryMutation()))
}

@Test
@MainActor
func taskCancellationAfterDestinationSelectionStopsBeforeSourceCreation() async throws {
  let fixture = try destinationReconnectCancellationFixture(selectorCancels: true)

  let result = try await fixture.useCase.execute(operationID: fixture.record.operationID)

  #expect(!result)
  #expect(await fixture.sourceCreator.count() == 0)
  #expect(await fixture.store.counts().saves == 0)
  #expect(!(await fixture.gate.hasActiveRecoveryMutation()))
}

@Test
@MainActor
func sourceCreationCancellationIsANoop() async throws {
  let fixture = try destinationReconnectCancellationFixture(sourceCancels: true)

  let result = try await fixture.useCase.execute(operationID: fixture.record.operationID)

  #expect(!result)
  #expect(await fixture.sourceCreator.count() == 1)
  #expect(await fixture.access.counts().acquired == 0)
  #expect(!(await fixture.gate.hasActiveRecoveryMutation()))
}

@Test
@MainActor
func commitReloadCancellationReleasesRecoveryLease() async throws {
  let fixture = try destinationReconnectCancellationFixture(
    configurationCancelLoadOnCall: 2
  )

  let result = try await fixture.useCase.execute(operationID: fixture.record.operationID)

  #expect(!result)
  #expect(await fixture.access.counts().acquired == 0)
  #expect(await fixture.store.counts().saves == 0)
  #expect(!(await fixture.gate.hasActiveRecoveryMutation()))
  #expect(await fixture.gate.beginCopy())
  await fixture.gate.endCopy()
}

@Test
@MainActor
func accessCancellationReleasesRecoveryLeaseWithoutSave() async throws {
  let fixture = try destinationReconnectCancellationFixture(
    accessMode: .throwCancellation
  )

  let result = try await fixture.useCase.execute(operationID: fixture.record.operationID)

  #expect(!result)
  #expect(await fixture.access.counts().acquired == 1)
  #expect(await fixture.access.counts().released == 0)
  #expect(await fixture.store.counts().saves == 0)
  #expect(!(await fixture.gate.hasActiveRecoveryMutation()))
}

@Test
@MainActor
func cancellationObservedAfterAccessAcquisitionReleasesHandle() async throws {
  let fixture = try destinationReconnectCancellationFixture(
    accessMode: .cancelAndReturn
  )

  let result = try await fixture.useCase.execute(operationID: fixture.record.operationID)

  #expect(!result)
  #expect(await fixture.access.counts().acquired == 1)
  #expect(await fixture.access.counts().released == 1)
  #expect(await fixture.store.counts().saves == 0)
  #expect(!(await fixture.gate.hasActiveRecoveryMutation()))
}

@Test
@MainActor
func finalConfigurationReloadCancellationDoesNotSave() async throws {
  let fixture = try destinationReconnectCancellationFixture(
    configurationCancelLoadOnCall: 3
  )

  let result = try await fixture.useCase.execute(operationID: fixture.record.operationID)

  #expect(!result)
  #expect(await fixture.access.counts().acquired == 1)
  #expect(await fixture.access.counts().released == 1)
  #expect(await fixture.store.counts().saves == 0)
  #expect(!(await fixture.gate.hasActiveRecoveryMutation()))
}

@Test
@MainActor
func saveCancellationBeforeCommitIsANoop() async throws {
  let fixture = try destinationReconnectCancellationFixture(
    cancelSaveBeforeCommit: true
  )

  let result = try await fixture.useCase.execute(operationID: fixture.record.operationID)

  #expect(!result)
  #expect(await fixture.store.counts().saves == 1)
  #expect(await fixture.access.counts().released == 1)
  #expect(!(await fixture.gate.hasActiveRecoveryMutation()))
}

@Test
@MainActor
func cancellationAfterSuccessfulCommitDoesNotRollBackResult() async throws {
  let fixture = try destinationReconnectCancellationFixture(
    cancelTaskAfterCommit: true
  )

  let result = try await fixture.useCase.execute(operationID: fixture.record.operationID)

  #expect(result)
  #expect(await fixture.store.counts().saves == 1)
  #expect(await fixture.access.counts().released == 1)
  #expect(!(await fixture.gate.hasActiveRecoveryMutation()))

  let current = try #require(await fixture.store.current().first)
  #expect(current.source.bookmarkData == Data([9]))
}
