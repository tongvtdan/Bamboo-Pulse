import Foundation
import Darwin

/// Advisory ownership for this app's UI process only; never device or action authority.
public final class SingleInstanceLease {
    private let descriptor: Int32

    public init(lockURL: URL) throws {
        let fd = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var admitted = false
        defer { if !admitted { close(fd) } }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(),
              info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o777 == 0o600
        else { throw POSIXError(.EACCES) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        descriptor = fd
        admitted = true
    }

    // Keep the inode in place: deleting a lock file lets a second process bypass it.
    deinit { close(descriptor) }
}
