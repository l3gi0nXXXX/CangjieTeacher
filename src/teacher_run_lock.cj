package cangjie_teacher

import std.fs.*
import std.posix.*

private let TEACHER_F_ULOCK: Int32 = 0
private let TEACHER_F_TLOCK: Int32 = 2
private let TEACHER_F_SETFD: Int32 = 2
private let TEACHER_FD_CLOEXEC: Int32 = 1

@When[os != "Windows"]
foreign {
    // Process-owned record locks are not inherited across fork and are released when the owner exits.
    func lockf(fd: Int32, function: Int32, size: Int64): Int32
    func fcntl(fd: Int32, command: Int32, argument: Int32): Int32
}

public class TeacherRunLock {
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
            throw IllegalArgumentException("teacher_run_lock_owner_mismatch")
        }
        let unlockResult = unsafe { lockf(fd, TEACHER_F_ULOCK, Int64(0)) }
        let closeResult = close(fd)
        held = false
        if (unlockResult != 0 || closeResult != 0) {
            throw IllegalArgumentException("teacher_run_lock_release_failed")
        }
    }

    @When[os == "Windows"]
    public func release(): Unit {
        throw IllegalArgumentException("teacher_run_lock_unsupported")
    }
}

public func teacherRunLockPath(root: String, runId: String): String {
    "${root}/runs/${runId}/.batch.lock"
}

private func validateTeacherRunLockIdentity(root: String, runId: String): Unit {
    if (root.isEmpty() || runId.isEmpty() || runId.contains("/") || runId.contains("\\") ||
        runId.contains("..")) {
        throw IllegalArgumentException("teacher_run_lock_identity_invalid")
    }
}

@When[os != "Windows"]
public func acquireTeacherRunLock(root: String, runId: String): TeacherRunLock {
    validateTeacherRunLockIdentity(root, runId)
    let runRoot = Path("${root}/runs/${runId}")
    try {
        if (!exists(runRoot)) { Directory.create(runRoot, recursive: true) }
    } catch (_: Exception) {
        throw IllegalArgumentException("teacher_run_lock_unavailable")
    }
    let lockPath = teacherRunLockPath(root, runId)
    let fd = open(lockPath, O_RDWR | O_CREAT | O_CLOEXEC, UInt32(0o600))
    if (fd < 0) {
        throw IllegalArgumentException("teacher_run_lock_unavailable")
    }
    if (unsafe { fcntl(fd, TEACHER_F_SETFD, TEACHER_FD_CLOEXEC) } != 0) {
        _ = close(fd)
        throw IllegalArgumentException("teacher_run_lock_unavailable")
    }
    if (unsafe { lockf(fd, TEACHER_F_TLOCK, Int64(0)) } != 0) {
        _ = close(fd)
        throw IllegalArgumentException("teacher_run_locked")
    }
    TeacherRunLock(lockPath, fd)
}

@When[os == "Windows"]
public func acquireTeacherRunLock(root: String, runId: String): TeacherRunLock {
    validateTeacherRunLockIdentity(root, runId)
    throw IllegalArgumentException("teacher_run_lock_unsupported")
}

public func releaseTeacherRunLock(lock: TeacherRunLock): Unit {
    lock.release()
}
