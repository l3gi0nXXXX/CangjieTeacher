package cangjie_teacher

import std.fs.*
import std.collection.*

public func teacherReadUtf8File(path: String): String {
    if (!exists(Path(path))) { throw IllegalArgumentException("file_not_found") }
    try { String.fromUtf8(File.readFrom(Path(path))) } catch (_: Exception) {
        throw IllegalArgumentException("invalid_response_encoding")
    }
}

public func teacherAtomicWrite(path: String, content: String): String {
    let target = Path(path)
    if (!exists(target.parent)) { Directory.create(target.parent, recursive: true) }
    let tmp = Path(path + ".tmp")
    File.writeTo(tmp, content.toArray())
    rename(tmp, to: target, overwrite: true)
    teacherStableHash(content)
}

public func teacherCopyFile(source: String, target: String): Unit {
    let bytes = File.readFrom(Path(source))
    let output = Path(target)
    if (!exists(output.parent)) { Directory.create(output.parent, recursive: true) }
    File.writeTo(output, bytes)
}

public func persistTeacherRunArtifacts(root: String, run: TeacherRunManifest, processEvidence: String,
    verifierEvidence: String): Array<TeacherEvidenceEntry> {
    let base = "${root}/runs/${run.runId}/evidence/${run.caseId}"
    let processPath = "${base}/generation.txt"
    let verifierPath = "${base}/verification.txt"
    let manifestPath = "${base}/run.manifest"
    let entries = [
        TeacherEvidenceEntry(processPath, teacherAtomicWrite(processPath, processEvidence)),
        TeacherEvidenceEntry(verifierPath, teacherAtomicWrite(verifierPath, verifierEvidence)),
        TeacherEvidenceEntry(manifestPath, teacherAtomicWrite(manifestPath, renderTeacherRunManifest(run)))
    ]
    let index = teacherJoin(entries.map({e: TeacherEvidenceEntry => "${e.locator}\t${e.hash}"}), "\n")
    _ = teacherAtomicWrite("${base}/index.tsv", index)
    return entries
}

public func loadCompletedTeacherRuns(path: String): Array<TeacherRunManifest> {
    if (!exists(Path(path))) { return [] }
    let out = ArrayList<TeacherRunManifest>()
    for (line in teacherReadUtf8File(path).split("\n")) {
        if (!line.trimAscii().isEmpty()) { out.add(parseTeacherRunManifest(line)) }
    }
    out.toArray()
}

public func persistCompletedTeacherRuns(path: String, runs: Array<TeacherRunManifest>): String {
    teacherAtomicWrite(path, teacherJoin(runs.map({r: TeacherRunManifest => renderTeacherRunManifest(r)}), "\n") + "\n")
}
