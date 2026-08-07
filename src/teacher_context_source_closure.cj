package cangjie_teacher

import std.collection.*
import std.fs.*
import std.sort.*

public class TeacherContextSourceArtifact {
    public let sourceId: String
    public let sourceClass: String
    public let raw: String
    public init(sourceId: String, sourceClass: String, raw: String) {
        this.sourceId = sourceId; this.sourceClass = sourceClass; this.raw = raw
    }
}

public class TeacherContextSourceClosure {
    public let manifest: TeacherContextSourceManifest
    public let sourceClosureHash: String
    public let protectedClosureHash: String
    public let protectedArtifacts: Array<String>
    public let auditFiles: Array<TeacherArtifactFile>
    init(manifest: TeacherContextSourceManifest, sourceClosureHash: String,
        protectedClosureHash: String, protectedArtifacts: Array<String>,
        auditFiles: Array<TeacherArtifactFile>) {
        this.manifest = manifest; this.sourceClosureHash = sourceClosureHash
        this.protectedClosureHash = protectedClosureHash
        this.protectedArtifacts = protectedArtifacts; this.auditFiles = auditFiles
    }
}

private func teacherClosureHashes(values: Array<String>): Array<String> {
    let hashes = values.map({value: String => "sha256:${teacherStableHash(value)}"})
    sort(hashes)
    let seen = HashSet<String>()
    for (hash in hashes) {
        if (seen.contains(hash)) { throw IllegalArgumentException("candidate_set_schema_invalid") }
        seen.add(hash)
    }
    hashes
}

private func teacherClosureHashArray(values: Array<String>): String {
    teacherJoin(values.map({value: String => "\"${value}\""}), ",")
}

private func teacherClosureSortInventory(rows: Array<String>): Array<String> {
    let paths = rows.map({row: String => row.split("  ")[1]}); sort(paths)
    let out = ArrayList<String>()
    for (path in paths) {
        for (row in rows) { if (row.endsWith("  ${path}")) { out.add(row); break } }
    }
    out.toArray()
}

private func teacherClosureRelativePath(value: String): Bool {
    if (value.isEmpty() || value.startsWith("/") || value.contains("\\")) { return false }
    for (component in value.split("/")) {
        if (component.isEmpty() || component == "." || component == ".." || component.contains("..")) {
            return false
        }
        for (rune in component.toRuneArray()) {
            if (!((rune >= r'a' && rune <= r'z') || (rune >= r'A' && rune <= r'Z') ||
                (rune >= r'0' && rune <= r'9') || rune == r'.' || rune == r'-' || rune == r'_')) {
                return false
            }
        }
    }
    true
}

private func teacherRenderSourceClosureWitness(manifestHash: String,
    inventory: Array<String>, closureHash: String): String {
    let evidence = "{\"schemaVersion\":\"teacher-context-source-closure-v2\"," +
        "\"sourceEvidenceManifestHash\":\"${manifestHash}\",\"sourceInventory\":[" +
        teacherClosureHashArray(inventory) + "]}"
    if (closureHash != "sha256:${teacherStableHash(evidence)}") {
        throw IllegalArgumentException("candidate_set_hash_mismatch")
    }
    String(evidence.toRuneArray()[..evidence.toRuneArray().size - 1]) +
        ",\"sourceClosureHash\":\"${closureHash}\"}"
}

private func teacherRenderProtectedClosureWitness(hashes: Array<String>, closureHash: String): String {
    let evidence = "{\"schemaVersion\":\"teacher-context-protected-closure-v1\"," +
        "\"protectedHashes\":[${teacherClosureHashArray(hashes)}]}"
    let expected = "sha256:${teacherStableHash(evidence)}"
    if (closureHash != expected) { throw IllegalArgumentException("candidate_set_hash_mismatch") }
    String(evidence.toRuneArray()[..evidence.toRuneArray().size - 1]) +
        ",\"protectedClosureHash\":\"${closureHash}\"}"
}

private func teacherClosureCollect(root: Path, relativeRoot: String,
    rows: ArrayList<String>, values: ArrayList<String>): Unit {
    if (FileInfo(root).isSymbolicLink() || !FileInfo(root).isDirectory()) {
        throw IllegalArgumentException("artifact_input_invalid")
    }
    for (entry in Directory.readFrom(root)) {
        if (entry.isSymbolicLink()) { throw IllegalArgumentException("artifact_input_invalid") }
        let relative = if (relativeRoot.isEmpty()) { entry.name } else { "${relativeRoot}/${entry.name}" }
        if (!teacherClosureRelativePath(relative)) { throw IllegalArgumentException("artifact_input_invalid") }
        if (entry.isDirectory()) { teacherClosureCollect(entry.path, relative, rows, values) }
        else if (entry.isRegular()) {
            let content = teacherReadUtf8File(entry.path.toString())
            rows.add("${teacherStableHash(content)}  ${relative}"); values.add(content)
        }
        else { throw IllegalArgumentException("artifact_input_invalid") }
    }
}

private func teacherClosureReadFiles(allowedRoot: String, root: String): (Array<String>, Array<String>) {
    let canonical = teacherResolveArtifactInput(allowedRoot, root, directory: true)
    let rows = ArrayList<String>(); let values = ArrayList<String>()
    teacherClosureCollect(Path(canonical), "", rows, values)
    if (values.isEmpty()) { throw IllegalArgumentException("candidate_set_schema_invalid") }
    let inventory = teacherClosureSortInventory(rows.toArray())
    (inventory, values.toArray())
}

// Source root contains source-manifest.json and a non-empty sources/ directory.
// Protected root contains the exact failure/source/base material selected for audit.
public func loadTeacherContextSourceClosure(allowedRoot: String, sourceRoot: String,
    protectedRoot: String): TeacherContextSourceClosure {
    let canonicalAllowed = teacherCanonicalArtifactRoot(allowedRoot)
    let canonicalSource = teacherResolveArtifactInput(allowedRoot, sourceRoot, directory: true)
    let manifestPath = "${canonicalSource}/source-manifest.json"
    let sourcesPath = "${canonicalSource}/sources"
    let manifestRaw = teacherReadUtf8File(teacherResolveArtifactInput(canonicalAllowed, manifestPath)).trimAscii()
    let manifest = parseTeacherContextSourceManifest(manifestRaw)
    let sourceFiles = teacherClosureReadFiles(canonicalAllowed, sourcesPath)
    let sourceValues = sourceFiles[1]
    let sourceHashes = teacherClosureHashes(sourceValues)
    if (manifest.sourceKind == "independent_sources") {
        let expected = manifest.sourceHashes.clone(); sort(expected)
        if (expected != sourceHashes) { throw IllegalArgumentException("candidate_lane_lineage_invalid") }
    } else {
        let evidenceHashes = ArrayList<String>()
        for (raw in sourceValues) {
            let failure = parseTeacherCompletionFailureInput(raw.trimAscii())
            evidenceHashes.add("sha256:${failure.evidenceHash}")
        }
        let expected = evidenceHashes.toArray(); sort(expected)
        if (expected != manifest.sourceHashes) { throw IllegalArgumentException("candidate_lane_lineage_invalid") }
    }
    let sourceRootFiles = teacherClosureReadFiles(canonicalAllowed, canonicalSource)
    let sourceInventory = sourceRootFiles[0]
    let sourceEvidence = "{\"schemaVersion\":\"teacher-context-source-closure-v2\"," +
        "\"sourceEvidenceManifestHash\":\"${manifest.sourceManifestHash}\",\"sourceInventory\":[" +
        teacherClosureHashArray(sourceInventory) + "]}"
    let sourceHash = "sha256:${teacherStableHash(sourceEvidence)}"

    let protectedFiles = teacherClosureReadFiles(allowedRoot, protectedRoot)
    let protectedValues = protectedFiles[1]
    let protectedHashes = teacherClosureHashes(protectedValues)
    let protectedEvidence = "{\"schemaVersion\":\"teacher-context-protected-closure-v1\"," +
        "\"protectedHashes\":[${teacherClosureHashArray(protectedHashes)}]}"
    let protectedHash = "sha256:${teacherStableHash(protectedEvidence)}"
    TeacherContextSourceClosure(manifest, sourceHash, protectedHash, protectedValues, [
        TeacherArtifactFile("source-closure.json",
            teacherRenderSourceClosureWitness(manifest.sourceManifestHash, sourceInventory, sourceHash) + "\n"),
        TeacherArtifactFile("protected-closure.json",
            teacherRenderProtectedClosureWitness(protectedHashes, protectedHash) + "\n")
    ])
}

public func bindTeacherContextSourceClosureToBase(value: TeacherContextSourceClosure,
    baseClosureBindings: Array<String>): TeacherContextSourceClosure {
    let hashes = ArrayList<String>()
    for (hash in teacherClosureHashes(value.protectedArtifacts)) { hashes.add(hash) }
    for (hash in baseClosureBindings) {
        if (!hash.startsWith("sha256:") || hash.toRuneArray().size != 71) {
            throw IllegalArgumentException("candidate_base_composite_mismatch")
        }
        hashes.add(hash)
    }
    let sorted = hashes.toArray(); sort(sorted)
    let seen = HashSet<String>()
    for (hash in sorted) {
        if (seen.contains(hash)) { throw IllegalArgumentException("candidate_base_composite_mismatch") }
        seen.add(hash)
    }
    let evidence = "{\"schemaVersion\":\"teacher-context-protected-closure-v1\"," +
        "\"protectedHashes\":[${teacherClosureHashArray(sorted)}]}"
    let protectedHash = "sha256:${teacherStableHash(evidence)}"
    var sourceWitness = ""
    for (file in value.auditFiles) {
        if (file.path == "source-closure.json") { sourceWitness = file.content }
    }
    if (sourceWitness.isEmpty()) { throw IllegalArgumentException("candidate_set_schema_invalid") }
    TeacherContextSourceClosure(value.manifest, value.sourceClosureHash, protectedHash,
        value.protectedArtifacts, [TeacherArtifactFile("source-closure.json", sourceWitness),
            TeacherArtifactFile("protected-closure.json",
                teacherRenderProtectedClosureWitness(sorted, protectedHash) + "\n")])
}
