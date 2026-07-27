package cangjie_teacher

import std.convert.Parsable
import std.env.getProcessId
import std.fs.*
import std.process.findProcess
import std.random.Random
import std.time.DateTime

private let TEACHER_RUN_LOCK_VERSION = "teacher-run-lock-v1"

@When[os != "Windows"]
foreign {
    func kill(pid: Int32, signal: Int32): Int32
}

public class TeacherRunLock {
    public let path: String
    public let pid: Int64
    public let token: String
    public init(path: String, pid: Int64, token: String) {
        this.path = path
        this.pid = pid
        this.token = token
    }
}

private class TeacherRunLockOwner {
    let pid: Int64
    let token: String
    init(pid: Int64, token: String) {
        this.pid = pid
        this.token = token
    }
}

public func teacherCurrentProcessId(): Int64 {
    Int64(getProcessId())
}

public func teacherRunLockPath(root: String, runId: String): String {
    "${root}/runs/${runId}/.batch.lock"
}

private func teacherRunLockTokenValid(token: String): Bool {
    if (token.size != 64) { return false }
    for (value in token.toRuneArray()) {
        if (!((value >= r'0' && value <= r'9') || (value >= r'a' && value <= r'f'))) { return false }
    }
    true
}

private func teacherRunLockToken(root: String, runId: String, pid: Int64): String {
    let random = Random()
    teacherStableHash("${root}\t${runId}\t${pid}\t${DateTime.now().toUnixTimeStamp().toNanoseconds()}\t" +
        "${random.nextInt64()}\t${random.nextInt64()}\t${random.nextInt64()}\t${random.nextInt64()}")
}

public func renderTeacherRunLockOwner(pid: Int64, token: String): String {
    "${TEACHER_RUN_LOCK_VERSION}\t${pid}\t${token}\n"
}

private func parseTeacherRunLockOwner(text: String): TeacherRunLockOwner {
    let fields = text.trimAscii().split("\t")
    if (fields.size != 3 || fields[0] != TEACHER_RUN_LOCK_VERSION ||
        !teacherRunLockTokenValid(fields[2])) {
        throw IllegalArgumentException("teacher_run_lock_owner_invalid")
    }
    let pid = try { Int64.parse(fields[1]) } catch (_: Exception) {
        throw IllegalArgumentException("teacher_run_lock_owner_invalid")
    }
    if (pid <= 0 || pid > 2147483647) {
        throw IllegalArgumentException("teacher_run_lock_owner_invalid")
    }
    TeacherRunLockOwner(pid, fields[2])
}

private func loadTeacherRunLockOwner(path: String): TeacherRunLockOwner {
    try {
        parseTeacherRunLockOwner(teacherReadUtf8File("${path}/owner"))
    } catch (_: Exception) {
        throw IllegalArgumentException("teacher_run_lock_owner_invalid")
    }
}

@When[os != "Windows"]
private func teacherRunLockOwnerAlive(pid: Int64): Bool {
    if (pid == teacherCurrentProcessId()) { return true }
    unsafe { kill(Int32(pid), Int32(0)) == 0 }
}

@When[os == "Windows"]
private func teacherRunLockOwnerAlive(pid: Int64): Bool {
    if (pid == teacherCurrentProcessId()) { return true }
    try { findProcess(pid).isAlive() } catch (_: Exception) { false }
}

private func teacherRemoveRunLockArtifact(path: String): Unit {
    try {
        if (exists(Path(path))) { remove(Path(path), recursive: true) }
    } catch (_: Exception) {}
}

public func acquireTeacherRunLock(root: String, runId: String): TeacherRunLock {
    if (root.isEmpty() || runId.isEmpty() || runId.contains("/") || runId.contains("\\") || runId.contains("..")) {
        throw IllegalArgumentException("teacher_run_lock_identity_invalid")
    }
    let runRoot = Path("${root}/runs/${runId}")
    try {
        if (!exists(runRoot)) { Directory.create(runRoot, recursive: true) }
    } catch (_: Exception) {
        throw IllegalArgumentException("teacher_run_lock_unavailable")
    }
    let pid = teacherCurrentProcessId()
    let token = teacherRunLockToken(root, runId, pid)
    let stage = runRoot.join(".batch.lock.stage-${token}").toString()
    let lockPath = teacherRunLockPath(root, runId)
    var quarantine = ""
    var published = false
    try {
        Directory.create(Path(stage), recursive: false)
        _ = teacherAtomicWrite("${stage}/owner", renderTeacherRunLockOwner(pid, token))
        try {
            rename(Path(stage), to: Path(lockPath), overwrite: false)
            published = true
        } catch (_: Exception) {
            if (!exists(Path(lockPath))) {
                throw IllegalArgumentException("teacher_run_lock_unavailable")
            }
            let owner = loadTeacherRunLockOwner(lockPath)
            if (teacherRunLockOwnerAlive(owner.pid)) {
                throw IllegalArgumentException("teacher_run_locked")
            }
            quarantine = runRoot.join(".batch.lock.stale-${token}").toString()
            try {
                rename(Path(lockPath), to: Path(quarantine), overwrite: false)
            } catch (_: Exception) {
                throw IllegalArgumentException("teacher_run_locked")
            }
            let movedOwner = loadTeacherRunLockOwner(quarantine)
            if (movedOwner.pid != owner.pid || movedOwner.token != owner.token) {
                try { rename(Path(quarantine), to: Path(lockPath), overwrite: false) } catch (_: Exception) {}
                quarantine = ""
                throw IllegalArgumentException("teacher_run_locked")
            }
            try {
                rename(Path(stage), to: Path(lockPath), overwrite: false)
                published = true
            } catch (_: Exception) {
                throw IllegalArgumentException("teacher_run_locked")
            }
        }
        TeacherRunLock(lockPath, pid, token)
    } finally {
        if (!published) { teacherRemoveRunLockArtifact(stage) }
        if (!quarantine.isEmpty()) { teacherRemoveRunLockArtifact(quarantine) }
    }
}

public func releaseTeacherRunLock(lock: TeacherRunLock): Unit {
    if (!exists(Path(lock.path))) { throw IllegalArgumentException("teacher_run_lock_owner_mismatch") }
    let owner = loadTeacherRunLockOwner(lock.path)
    if (owner.pid != lock.pid || owner.token != lock.token) {
        throw IllegalArgumentException("teacher_run_lock_owner_mismatch")
    }
    let quarantine = "${lock.path}.release-${teacherRunLockToken(lock.path, lock.token, lock.pid)}"
    try {
        rename(Path(lock.path), to: Path(quarantine), overwrite: false)
    } catch (_: Exception) {
        throw IllegalArgumentException("teacher_run_lock_owner_mismatch")
    }
    let movedOwner = loadTeacherRunLockOwner(quarantine)
    if (movedOwner.pid != lock.pid || movedOwner.token != lock.token) {
        try { rename(Path(quarantine), to: Path(lock.path), overwrite: false) } catch (_: Exception) {}
        throw IllegalArgumentException("teacher_run_lock_owner_mismatch")
    }
    try {
        remove(Path(quarantine), recursive: true)
    } catch (_: Exception) {
        throw IllegalArgumentException("teacher_run_lock_release_failed")
    }
}
