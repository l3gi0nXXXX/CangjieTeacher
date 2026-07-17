package cangjie_teacher

import std.collection.*
import std.convert.Parsable
import std.fs.*

private let TEACHER_ATTEMPT_SCHEMA = "teacher-attempt/v1"

public class TeacherAttemptEvidence {
    public let runId: String
    public let caseId: String
    public let promptHash: String
    public let attempt: Int64
    public let status: String
    public let preSolutionHash: String
    public let solutionHash: String
    public let generationDiagnostic: String
    public let verifierDiagnostic: String
    public let repeatCount: Int64
    public let previousEvidenceHash: String
    public let snapshotHash: String
    public init(runId: String, caseId: String, promptHash: String, attempt: Int64, status: String,
        preSolutionHash: String, solutionHash: String, generationDiagnostic: String,
        verifierDiagnostic: String, repeatCount: Int64, previousEvidenceHash: String, snapshotHash: String) {
        this.runId = runId; this.caseId = caseId; this.promptHash = promptHash; this.attempt = attempt
        this.status = status; this.preSolutionHash = preSolutionHash; this.solutionHash = solutionHash
        this.generationDiagnostic = generationDiagnostic; this.verifierDiagnostic = verifierDiagnostic
        this.repeatCount = repeatCount; this.previousEvidenceHash = previousEvidenceHash
        this.snapshotHash = snapshotHash
    }
}

private func teacherAttemptEscape(value: String): String {
    if (value.isEmpty()) { "%00" }
    else { value.replace("%", "%25").replace("\t", "%09").replace("\n", "%0A") }
}

private func teacherAttemptUnescape(value: String): String {
    if (value == "%00") { "" }
    else { value.replace("%0A", "\n").replace("%09", "\t").replace("%25", "%") }
}

public func renderTeacherAttemptEvidence(value: TeacherAttemptEvidence): String {
    teacherJoin([TEACHER_ATTEMPT_SCHEMA, value.runId, value.caseId, value.promptHash, value.attempt.toString(),
        value.status, value.preSolutionHash, value.solutionHash, value.generationDiagnostic,
        value.verifierDiagnostic, value.repeatCount.toString(), value.previousEvidenceHash, value.snapshotHash]
        .map({field: String => teacherAttemptEscape(field)}), "\t")
}

public func parseTeacherAttemptEvidence(raw: String): TeacherAttemptEvidence {
    let fields = raw.trimAscii().split("\t").map({field: String => teacherAttemptUnescape(field)}).toArray()
    if (fields.size != 13 || fields[0] != TEACHER_ATTEMPT_SCHEMA) {
        throw IllegalArgumentException("teacher_attempt_evidence_invalid")
    }
    try {
        TeacherAttemptEvidence(fields[1], fields[2], fields[3], Int64.parse(fields[4]), fields[5], fields[6],
            fields[7], fields[8], fields[9], Int64.parse(fields[10]), fields[11], fields[12])
    } catch (_: Exception) { throw IllegalArgumentException("teacher_attempt_evidence_invalid") }
}

public func teacherAttemptEvidenceHash(value: TeacherAttemptEvidence): String {
    "sha256:${teacherStableHash(renderTeacherAttemptEvidence(value))}"
}

public func teacherAttemptManifestPath(root: String, runId: String, caseId: String, attempt: Int64): String {
    "${root}/runs/${runId}/attempts/${caseId}/attempt-${attempt}.manifest"
}

public func teacherAttemptSnapshotPath(root: String, runId: String, caseId: String, attempt: Int64): String {
    "${teacherAttemptSnapshotRoot(root, runId, caseId, attempt)}/solution.cj"
}

private func teacherAttemptSnapshotRoot(root: String, runId: String, caseId: String, attempt: Int64): String {
    "${root}/runs/${runId}/attempts/${caseId}/attempt-${attempt}/src"
}

private func validateTeacherAttemptEvidence(value: TeacherAttemptEvidence, runId: String,
    caseValue: TeacherCaseManifest, expectedAttempt: Int64, previousHash: String): Bool {
    let statuses = ["started", "interrupted", "transport_failed", "verification_failed", "verified"]
    value.runId == runId && value.caseId == caseValue.caseId && value.promptHash == caseValue.promptHash &&
        value.attempt == expectedAttempt && statuses.contains(value.status) && !value.preSolutionHash.isEmpty() &&
        !value.solutionHash.isEmpty() && value.repeatCount >= 0 && value.previousEvidenceHash == previousHash &&
        (value.status == "started" || !value.snapshotHash.isEmpty())
}

public func loadTeacherAttemptEvidence(root: String, runId: String,
    caseValue: TeacherCaseManifest): Array<TeacherAttemptEvidence> {
    let out = ArrayList<TeacherAttemptEvidence>()
    var attempt: Int64 = 1
    var previousHash = ""
    while (true) {
        let path = teacherAttemptManifestPath(root, runId, caseValue.caseId, attempt)
        if (!exists(Path(path))) { break }
        try {
            if (FileInfo(Path(path)).isSymbolicLink()) { throw IllegalArgumentException("teacher_attempt_evidence_invalid") }
            let value = parseTeacherAttemptEvidence(teacherReadUtf8File(path))
            if (!validateTeacherAttemptEvidence(value, runId, caseValue, attempt, previousHash)) {
                throw IllegalArgumentException("teacher_attempt_evidence_invalid")
            }
            if (value.status == "started" && exists(Path(teacherAttemptManifestPath(root, runId, caseValue.caseId, attempt + 1)))) {
                throw IllegalArgumentException("teacher_attempt_evidence_invalid")
            }
            if (value.status != "started") {
                let snapshot = teacherAttemptSnapshotRoot(root, runId, caseValue.caseId, attempt)
                if (!exists(Path(snapshot)) || teacherDirectoryHash(snapshot) != value.snapshotHash ||
                    value.snapshotHash != value.solutionHash) {
                    throw IllegalArgumentException("teacher_attempt_evidence_invalid")
                }
            }
            out.add(value); previousHash = teacherAttemptEvidenceHash(value); attempt += 1
        } catch (_: Exception) { throw IllegalArgumentException("teacher_attempt_evidence_invalid") }
    }
    let base = Path("${root}/runs/${runId}/attempts/${caseValue.caseId}")
    if (exists(base)) {
        var manifests: Int64 = 0
        for (entry in Directory.readFrom(base)) { if (entry.name.startsWith("attempt-") && entry.name.endsWith(".manifest")) { manifests += 1 } }
        if (manifests != out.size) { throw IllegalArgumentException("teacher_attempt_evidence_invalid") }
    }
    out.toArray()
}

public func hasTeacherAttemptEvidence(root: String, runId: String, caseId: String): Bool {
    exists(Path(teacherAttemptManifestPath(root, runId, caseId, 1)))
}

public func persistTeacherAttemptStarted(root: String, runId: String, caseValue: TeacherCaseManifest,
    attempt: Int64, previousEvidenceHash: String, preSolutionHash: String): String {
    let value = TeacherAttemptEvidence(runId, caseValue.caseId, caseValue.promptHash, attempt, "started",
        preSolutionHash, preSolutionHash, "", "", 0, previousEvidenceHash, "")
    teacherAtomicWrite(teacherAttemptManifestPath(root, runId, caseValue.caseId, attempt),
        renderTeacherAttemptEvidence(value) + "\n")
}

public func teacherAttemptSafeDiagnostic(raw: String): String {
    let words = ArrayList<String>()
    for (word in raw.replace("\n", " \n ").split(" ")) {
        let lower = word.toAsciiLower()
        if (word.contains("/Users") || lower.contains("authorization") || lower.contains("token") ||
            lower.contains("secret") || lower.contains("hidden") || lower.contains("reference")) {
            words.add("[redacted]")
        } else { words.add(word) }
    }
    let sanitized = teacherSanitizeEvidence(teacherJoin(words.toArray(), " "))
    let runes = sanitized.toRuneArray()
    if (runes.size <= 512) { sanitized } else { String(runes[..512]) + "..." }
}

public func teacherAttemptRepeatCount(history: Array<TeacherAttemptEvidence>, solutionHash: String): Int64 {
    var count: Int64 = 1
    for (entry in history) { if (entry.solutionHash == solutionHash) { count += 1 } }
    count
}

public func persistTeacherAttemptCompleted(root: String, caseValue: TeacherCaseManifest,
    value: TeacherAttemptEvidence, workspace: String): TeacherAttemptEvidence {
    let source = "${workspace}/src"
    if (!exists(Path("${source}/solution.cj"))) { throw IllegalArgumentException("teacher_attempt_solution_missing") }
    let snapshot = teacherAttemptSnapshotRoot(root, value.runId, caseValue.caseId, value.attempt)
    let stage = "${snapshot}.tmp-${teacherStableHash(value.solutionHash)}"
    try {
        if (exists(Path(stage))) { remove(Path(stage), recursive: true) }
        if (!exists(Path(snapshot))) {
            teacherCopyTree(source, stage)
            if (teacherDirectoryHash(stage) != value.solutionHash) {
                throw IllegalArgumentException("teacher_attempt_snapshot_mismatch")
            }
            if (!exists(Path(snapshot).parent)) { Directory.create(Path(snapshot).parent, recursive: true) }
            rename(Path(stage), to: Path(snapshot), overwrite: false)
        }
    } catch (e: Exception) {
        try { if (exists(Path(stage))) { remove(Path(stage), recursive: true) } } catch (_: Exception) {}
        throw e
    }
    let snapshotHash = teacherDirectoryHash(snapshot)
    if (snapshotHash != value.solutionHash) { throw IllegalArgumentException("teacher_attempt_snapshot_mismatch") }
    let completed = TeacherAttemptEvidence(value.runId, value.caseId, value.promptHash, value.attempt, value.status,
        value.preSolutionHash, value.solutionHash, value.generationDiagnostic, value.verifierDiagnostic,
        value.repeatCount, value.previousEvidenceHash, snapshotHash)
    _ = teacherAtomicWrite(teacherAttemptManifestPath(root, value.runId, caseValue.caseId, value.attempt),
        renderTeacherAttemptEvidence(completed) + "\n")
    completed
}

private func teacherAttemptHasCycle(history: Array<TeacherAttemptEvidence>): Bool {
    if (history.size < 3) { return false }
    history[history.size - 1].solutionHash == history[history.size - 3].solutionHash
}

public func teacherAttemptProgressGuidance(nextAttempt: Int64, history: Array<TeacherAttemptEvidence>,
    verifierFeedback: String): String {
    var guidance = "Teacher repair attempt ${nextAttempt}. Continue from the exact current workspace. " +
        "Each Codex call is ephemeral, so inspect the current files before editing and do not assume conversation memory."
    if (!verifierFeedback.isEmpty()) { guidance += "\nSanitized public verifier diagnostic: ${teacherAttemptSafeDiagnostic(verifierFeedback)}" }
    if (!history.isEmpty()) {
        let start = if (history.size > 3) { history.size - 3 } else { 0 }
        let hashes = ArrayList<String>()
        for (i in start..history.size) { hashes.add(history[i].solutionHash) }
        guidance += "\nBounded recent solution hashes: ${teacherJoin(hashes.toArray(), ", ")}."
        let last = history[history.size - 1]
        if (last.repeatCount >= 2) {
            guidance += " The latest solution hash was repeated ${last.repeatCount} times; do not repeat that implementation strategy."
        }
        if (teacherAttemptHasCycle(history)) {
            guidance += " A solution hash cycle was detected; diagnose why prior strategies failed and choose a genuinely different strategy."
        }
    }
    let runes = guidance.toRuneArray()
    if (runes.size <= 4000) { guidance } else { String(runes[..4000]) + "..." }
}
