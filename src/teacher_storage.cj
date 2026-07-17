package cangjie_teacher

import std.fs.*
import std.collection.*
import std.sort.*
import stdx.crypto.digest.SHA256
import std.core.StringBuilder

public func teacherReadUtf8File(path: String): String {
    if (!exists(Path(path))) { throw IllegalArgumentException("file_not_found") }
    try { String.fromUtf8(File.readFrom(Path(path))) } catch (_: Exception) {
        throw IllegalArgumentException("invalid_response_encoding")
    }
}

public func teacherAtomicWrite(path: String, content: String): String {
    let target = Path(path)
    if (!exists(target.parent)) { Directory.create(target.parent, recursive: true) }
    let tmp = Path(path + ".tmp-" + teacherStableHash(path + content))
    try {
        File.writeTo(tmp, content.toArray())
        rename(tmp, to: target, overwrite: true)
    } catch (e: Exception) {
        try { remove(tmp) } catch (_: Exception) {}
        throw e
    }
    teacherStableHash(content)
}

public func teacherCopyFile(source: String, target: String): Unit {
    let bytes = File.readFrom(Path(source))
    let output = Path(target)
    if (!exists(output.parent)) { Directory.create(output.parent, recursive: true) }
    File.writeTo(output, bytes)
}

public func teacherDirectoryHash(root: String): String {
    let base = Path(root)
    if (!exists(base)) { return "" }
    let files = ArrayList<String>()
    teacherCollectDirectoryFiles(base, "", files)
    sort(files)
    let digest = SHA256()
    for (relative in files) {
        let bytes = File.readFrom(base.join(relative))
        digest.write("${relative.size}:${relative}:${bytes.size}:".toArray()); digest.write(bytes)
    }
    let out = StringBuilder()
    for (byte in digest.finish()) {
        let hi = byte / UInt8(16); let lo = byte % UInt8(16)
        out.append(if (hi < UInt8(10)) { "${hi}" } else { ["a","b","c","d","e","f"][Int64(hi - UInt8(10))] })
        out.append(if (lo < UInt8(10)) { "${lo}" } else { ["a","b","c","d","e","f"][Int64(lo - UInt8(10))] })
    }
    "sha256:${out.toString()}"
}

private func teacherCollectDirectoryFiles(current: Path, relativeRoot: String, files: ArrayList<String>): Unit {
    for (entry in Directory.readFrom(current)) {
        let relative = if (relativeRoot.isEmpty()) { entry.name } else { "${relativeRoot}/${entry.name}" }
        if (entry.isDirectory()) { teacherCollectDirectoryFiles(entry.path, relative, files) }
        else if (entry.isRegular()) { files.add(relative) }
    }
}

public func teacherSanitizeEvidence(value: String): String {
    let safeLines = ArrayList<String>()
    for (line in value.split("\n")) {
        let trimmed = line.trimAscii()
        if (trimmed.startsWith("package ") || trimmed.startsWith("func ") || trimmed.startsWith("public func ") ||
            trimmed.contains("return ") || trimmed.contains("=>")) { safeLines.add("[solution_content_redacted]") }
        else { safeLines.add(line) }
    }
    var sanitized = teacherJoin(safeLines.toArray(), "\n")
    var runes = sanitized.toRuneArray()
    let boundary = teacherEvidenceSensitiveBoundary(sanitized)
    if (boundary < runes.size) {
        let publicPrefix = if (boundary == 0) { "" } else { String(runes[..boundary]).trimAscii() }
        sanitized = if (publicPrefix.isEmpty()) { "[redacted]" } else { "${publicPrefix} [redacted]" }
        runes = sanitized.toRuneArray()
    }
    if (runes.size <= 4000) { return sanitized }
    String(runes[..4000]) + "..."
}

private func teacherEvidenceSensitiveBoundary(value: String): Int64 {
    let valueRunes = value.toAsciiLower().toRuneArray()
    var earliest = valueRunes.size
    for (rawMarker in ["/users/", "/home/", "/private/", "~/", "authorization", "token", "password",
        "proxy", "secret"]) {
        let marker = rawMarker.toRuneArray()
        if (marker.size > valueRunes.size) { continue }
        let lastStart = valueRunes.size - marker.size
        for (start in 0..=lastStart) {
            var matches = true
            for (offset in 0..marker.size) {
                if (valueRunes[start + offset] != marker[offset]) { matches = false; break }
            }
            if (matches && start < earliest) { earliest = start; break }
        }
    }
    earliest
}

public func persistTeacherRunArtifacts(root: String, run: TeacherRunManifest, processEvidence: String,
    verifierEvidence: String): Array<TeacherEvidenceEntry> {
    let base = "${root}/runs/${run.runId}/evidence/${run.caseId}"
    let processPath = "${base}/generation.txt"
    let verifierPath = "${base}/verification.txt"
    let manifestPath = "${base}/run.manifest"
    let entries = [
        TeacherEvidenceEntry("generation.txt", teacherAtomicWrite(processPath, teacherSanitizeEvidence(processEvidence))),
        TeacherEvidenceEntry("verification.txt", teacherAtomicWrite(verifierPath, teacherSanitizeEvidence(verifierEvidence))),
        TeacherEvidenceEntry("run.manifest", teacherAtomicWrite(manifestPath, renderTeacherRunManifest(run)))
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

public func persistTeacherSolutionBinding(root:String,run:TeacherRunManifest):String {
    let hash=teacherDirectoryHash(TeacherPaths(root).solution(run.caseId))
    if(hash==""){throw IllegalArgumentException("solution_hash_missing")}
    teacherAtomicWrite("${root}/runs/${run.runId}/evidence/${run.caseId}/solution.binding",
        "${hash}\t${run.evidenceHash}\t${run.promptHash}\n")
}

public func validateTeacherSolutionBinding(root:String,run:TeacherRunManifest):Bool {
    let path="${root}/runs/${run.runId}/evidence/${run.caseId}"
    try {
        let persisted=parseTeacherRunManifest(teacherReadUtf8File("${path}/run.manifest").trimAscii())
        if(renderTeacherRunManifest(persisted)!=renderTeacherRunManifest(run)||!validateTeacherPersistedEvidenceIndex(path)){return false}
        let fields=teacherReadUtf8File("${path}/solution.binding").trimAscii().split("\t")
        fields.size==3&&fields[0]==teacherDirectoryHash(TeacherPaths(root).solution(run.caseId))&&fields[1]==run.evidenceHash&&fields[2]==run.promptHash
    }catch(_:Exception){false}
}

private func validateTeacherPersistedEvidenceIndex(base:String):Bool {
    try {
        let lines=teacherReadUtf8File("${base}/index.tsv").split("\n")
        let names=["generation.txt","verification.txt","run.manifest"]
        if(lines.size!=names.size){return false}
        for(i in 0..names.size){let name=names[i];let path="${base}/${name}";let expected="${name}\t${teacherStableHash(teacherReadUtf8File(path))}";if(lines[i]!=expected){return false}}
        true
    }catch(_:Exception){false}
}
