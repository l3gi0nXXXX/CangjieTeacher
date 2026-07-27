package cangjie_teacher

import std.fs.*
import std.posix.*

private let TEACHER_TRANSPORT_LOCK_EX: Int32 = 2
private let TEACHER_TRANSPORT_LOCK_NB: Int32 = 4

@When[os != "Windows"]
foreign {
    func flock(fd: Int32, operation: Int32): Int32
}

public class TeacherTransportLease {
    public let path: String
    private let fd: Int32
    private var held = true

    internal init(path: String, fd: Int32) {
        this.path = path
        this.fd = fd
    }

    @When[os != "Windows"]
    public func release(): Unit {
        if (!held || fd < 0) {
            throw IllegalArgumentException("teacher_transport_lease_owner_mismatch")
        }
        let result = close(fd)
        held = false
        if (result != 0) {
            throw IllegalArgumentException("teacher_transport_lease_release_failed")
        }
    }

    @When[os == "Windows"]
    public func release(): Unit {
        throw IllegalArgumentException("teacher_transport_lease_unsupported")
    }
}

@When[os != "Windows"]
public func acquireTeacherTransportLease(path: String): TeacherTransportLease {
    if (path.isEmpty()) { throw IllegalArgumentException("teacher_transport_lease_path_invalid") }
    let lockPath = Path(path)
    try {
        if (!exists(lockPath.parent)) { Directory.create(lockPath.parent, recursive: true) }
        if (exists(lockPath) && FileInfo(lockPath).isSymbolicLink()) {
            throw IllegalArgumentException("teacher_transport_lease_unavailable")
        }
    } catch (e: IllegalArgumentException) {
        throw e
    } catch (_: Exception) {
        throw IllegalArgumentException("teacher_transport_lease_unavailable")
    }
    // Deliberately omit O_CLOEXEC: the model process and its descendants own this lease too.
    let fd = open(path, O_RDWR | O_CREAT, UInt32(0o600))
    if (fd < 0) { throw IllegalArgumentException("teacher_transport_lease_unavailable") }
    if (unsafe { flock(fd, TEACHER_TRANSPORT_LOCK_EX | TEACHER_TRANSPORT_LOCK_NB) } != 0) {
        _ = close(fd)
        throw IllegalArgumentException("teacher_transport_still_running")
    }
    TeacherTransportLease(path, fd)
}

@When[os == "Windows"]
public func acquireTeacherTransportLease(path: String): TeacherTransportLease {
    if (path.isEmpty()) { throw IllegalArgumentException("teacher_transport_lease_path_invalid") }
    throw IllegalArgumentException("teacher_transport_lease_unsupported")
}

public func probeTeacherTransportLease(path: String): Unit {
    let lease = acquireTeacherTransportLease(path)
    releaseTeacherTransportLease(lease)
}

public func releaseTeacherTransportLease(lease: TeacherTransportLease): Unit {
    lease.release()
}
