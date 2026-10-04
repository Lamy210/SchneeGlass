import Darwin
import Foundation

public enum ApplicationProcessLockError: Error, Hashable, Sendable {
  case alreadyLocked
  case lockFileUnavailable(Int32)
}

/// Holds an advisory process-wide ownership lock for app-owned persistent state.
///
/// The lock is intentionally backed by an open file descriptor instead of a PID file. The kernel
/// releases the lock when the descriptor/process exits, so an abnormal termination cannot leave a
/// stale ownership claim that blocks the next launch.
public final class ApplicationProcessLock {
  private let descriptor: Int32

  public init(lockFileURL: URL) throws {
    let candidate = lockFileURL.standardizedFileURL

    guard let path = candidate.withUnsafeFileSystemRepresentation({ $0.map(String.init(cString:)) })
    else {
      throw ApplicationProcessLockError.lockFileUnavailable(EINVAL)
    }

    let descriptor = open(
      path,
      O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
      mode_t(S_IRUSR | S_IWUSR)
    )
    guard descriptor >= 0 else {
      throw ApplicationProcessLockError.lockFileUnavailable(errno)
    }

    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      let observedErrno = errno
      close(descriptor)

      if observedErrno == EWOULDBLOCK || observedErrno == EAGAIN {
        throw ApplicationProcessLockError.alreadyLocked
      }
      throw ApplicationProcessLockError.lockFileUnavailable(observedErrno)
    }

    self.descriptor = descriptor
  }

  deinit {
    _ = flock(descriptor, LOCK_UN)
    close(descriptor)
  }
}
