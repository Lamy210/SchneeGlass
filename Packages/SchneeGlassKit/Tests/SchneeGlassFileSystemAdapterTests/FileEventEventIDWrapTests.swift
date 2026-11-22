import CoreServices
import SchneeGlassApplication
import Testing

@testable import SchneeGlassFileSystemAdapter

@Test("wrapped FSEvent IDs require an authoritative snapshot")
func wrappedEventIDsRequireFullRescan() {
  let flags = FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped)
  #expect(FileEventFlagMapper.map(flags) == .requiresFullRescan)
}

@Test("ordinary change cannot weaken a wrapped-ID rescan")
func wrappedEventIDsOverrideOrdinaryChange() {
  let flags =
    FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped)
    | FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)
  #expect(FileEventFlagMapper.map(flags) == .requiresFullRescan)
}

@Test("watched root replacement takes priority over wrapped IDs")
func rootChangePrecedesWrappedEventIDs() {
  let flags =
    FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)
    | FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped)
  #expect(FileEventFlagMapper.map(flags) == .rootChanged)
}
