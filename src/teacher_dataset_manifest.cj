package cangjie_teacher

import std.collection.*
import std.core.StringBuilder
import stdx.crypto.digest.SHA256
import stdx.encoding.json.JsonValue

public func parseTeacherModelManifestJson(line: String): TeacherCaseManifest {
    try {
        let value = JsonValue.fromStr(line).asObject()
        let field = {key: String => value.get(key).getOrThrow().asString().getValue()}
        let schema = field("schemaVersion")
        if (schema != "cangjie-humaneval-model-v1" && schema != "cangjie-humaneval-authority-v1") {
            throw IllegalArgumentException("unsupported_manifest_schema")
        }
        let tags = ArrayList<String>()
        for (tag in value.get("requiredKnowledgeTags").getOrThrow().asArray().getItems()) {
            tags.add(tag.asString().getValue())
        }
        TeacherCaseManifest(field("caseId"), field("datasetVersion"), field("promptHash"),
            field("starterHash"), field("signature"), "verifier-owned", prompt: field("prompt"),
            targetVersion: field("targetVersion"), requiredKnowledgeTags: tags.toArray())
    } catch (e: IllegalArgumentException) { throw e } catch (_: Exception) {
        throw IllegalArgumentException("malformed_teacher_manifest_json")
    }
}

public func importTeacherDatasetManifest(lines: Array<String>, expectedChecksum: String): TeacherDatasetManifest {
    let checksum = teacherStableHash(teacherJoin(lines, "\n"))
    if (checksum != expectedChecksum) { throw IllegalArgumentException("manifest_checksum_mismatch") }
    let cases = lines.map({line: String => parseTeacherModelManifestJson(line)})
    if (cases.isEmpty()) { throw IllegalArgumentException("empty_manifest") }
    let manifest = TeacherDatasetManifest(cases[0].datasetVersion, cases)
    if (!validateTeacherDatasetManifest(manifest)) { throw IllegalArgumentException("invalid_manifest") }
    return manifest
}

public func validateTeacherDatasetManifest(manifest: TeacherDatasetManifest): Bool {
    if (manifest.schemaVersion != TEACHER_SCHEMA_VERSION || manifest.datasetVersion.isEmpty() || manifest.cases.size != 164) { return false }
    let ids = HashSet<String>()
    for (i in 0..164) {
        let expected = "CJ-HUMANEVAL-${teacherPad3(i)}"
        let c = manifest.cases[i]
        if (c.caseId != expected || c.datasetVersion != manifest.datasetVersion || !validateTeacherCaseManifest(c) || ids.contains(c.caseId)) { return false }
        ids.add(c.caseId)
    }
    return true
}

public func validateTeacherManifestViewBoundary(modelVisible: Array<String>, verifier: Array<String>): Bool {
    let forbiddenVisible = ["test", "reference", "solution", "verifierPath", "expectedOutput"]
    for (line in modelVisible) { for (word in forbiddenVisible) { if (line.toAsciiLower().contains(word.toAsciiLower())) { return false } } }
    return !verifier.isEmpty()
}

public func teacherPad3(value: Int64): String {
    if (value < 10) { return "00${value}" }
    if (value < 100) { return "0${value}" }
    return "${value}"
}

public func teacherStableHash(value: String): String {
    let digest = SHA256()
    digest.write(value.toArray())
    let out = StringBuilder()
    for (byte in digest.finish()) {
        let hi = byte / UInt8(16); let lo = byte % UInt8(16)
        out.append(teacherHexNibble(hi)); out.append(teacherHexNibble(lo))
    }
    return out.toString()
}

private func teacherHexNibble(value: UInt8): String {
    if (value < UInt8(10)) { return "${value}" }
    if (value == UInt8(10)) { return "a" }; if (value == UInt8(11)) { return "b" }
    if (value == UInt8(12)) { return "c" }; if (value == UInt8(13)) { return "d" }
    if (value == UInt8(14)) { return "e" }; return "f"
}
