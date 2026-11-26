import CoreServices
import Testing

@testable import SchneeGlassFileSystemAdapter

@Test(
  "external volume and FSEvents history changes always require an authoritative rescan",
  arguments: [
    FSEventStreamEventFlags(kFSEventStreamEventFlagMount),
    FSEventStreamEventFlags(kFSEventStreamEventFlagUnmount),
    FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped),
    FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs),
    FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped),
    FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped),
  ]
)
func interruptedFSEventsHistoryRequiresFullRescan(
  flags: FSEventStreamEventFlags
) {
  #expect(FileEventFlagMapper.map(flags) == .requiresFullRescan)
}

@Test("root replacement must outrank a simultaneous mount or dropped event")
func rootReplacementHasPriorityOverRescanIndicators() {
  let rootChanged = FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)
  let rescanIndicators: [FSEventStreamEventFlags] = [
    FSEventStreamEventFlags(kFSEventStreamEventFlagMount),
    FSEventStreamEventFlags(kFSEventStreamEventFlagUnmount),
    FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped),
    FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped),
  ]
  for flags in rescanIndicators {
    #expect(FileEventFlagMapper.map(rootChanged | flags) == .rootChanged)
  }
}

@Test("ordinary per-file changes must not be misclassified as a root replacement")
func ordinaryNativeFileEventsRemainChanged() {
  let regularEvents: [FSEventStreamEventFlags] = [
    FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated),
    FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved),
    FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified),
  ]
  for flags in regularEvents {
    #expect(FileEventFlagMapper.map(flags) == .changed)
  }
}
