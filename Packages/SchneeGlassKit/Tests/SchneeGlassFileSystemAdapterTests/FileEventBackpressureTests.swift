import SchneeGlassApplication
import Testing

@testable import SchneeGlassFileSystemAdapter

@Test
func fileEventBufferCoalescesOrdinaryBursts() async {
  let pair = AsyncStream<FileEvent>.makeStream(bufferingPolicy: .bufferingNewest(1))
  let box = FSEventCallbackBox(continuation: pair.continuation)

  for _ in 0..<1_000 {
    box.yield(.changed)
  }
  pair.continuation.finish()

  var iterator = pair.stream.makeAsyncIterator()
  #expect(await iterator.next() == .changed)
  #expect(await iterator.next() == nil)
}

@Test
func weakerEventCannotReplacePendingFullRescan() async {
  let pair = AsyncStream<FileEvent>.makeStream(bufferingPolicy: .bufferingNewest(1))
  let box = FSEventCallbackBox(continuation: pair.continuation)

  box.yield(.requiresFullRescan)
  box.yield(.changed)
  pair.continuation.finish()

  var iterator = pair.stream.makeAsyncIterator()
  #expect(await iterator.next() == .requiresFullRescan)
  #expect(await iterator.next() == nil)
}

@Test
func rootChangeRemainsStrongestPendingEvent() async {
  let pair = AsyncStream<FileEvent>.makeStream(bufferingPolicy: .bufferingNewest(1))
  let box = FSEventCallbackBox(continuation: pair.continuation)

  box.yield(.changed)
  box.yield(.rootChanged)
  box.yield(.requiresFullRescan)
  box.yield(.changed)
  pair.continuation.finish()

  var iterator = pair.stream.makeAsyncIterator()
  #expect(await iterator.next() == .rootChanged)
  #expect(await iterator.next() == nil)
}
