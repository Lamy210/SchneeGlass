import CoreServices
import SchneeGlassApplication
import Testing

@testable import SchneeGlassFileSystemAdapter

@Test(
  "mount and unmount notifications revalidate the watched folder",
  arguments: [
    FSEventStreamEventFlags(kFSEventStreamEventFlagMount),
    FSEventStreamEventFlags(kFSEventStreamEventFlagUnmount),
  ]
)
func volumeTransitionRequiresFullRescan(flags: FSEventStreamEventFlags) {
  #expect(FileEventFlagMapper.map(flags) == .requiresFullRescan)
}

@Test(
  "ordinary change cannot override a mount or unmount",
  arguments: [
    FSEventStreamEventFlags(kFSEventStreamEventFlagMount),
    FSEventStreamEventFlags(kFSEventStreamEventFlagUnmount),
  ]
)
func volumeTransitionOverridesOrdinaryChange(flags: FSEventStreamEventFlags) {
  let changed = FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)
  #expect(FileEventFlagMapper.map(flags | changed) == .requiresFullRescan)
}

@Test("root change stays stronger than volume transitions")
func rootChangePrecedesVolumeTransition() {
  let flags =
    FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)
    | FSEventStreamEventFlags(kFSEventStreamEventFlagUnmount)
  #expect(FileEventFlagMapper.map(flags) == .rootChanged)
}
