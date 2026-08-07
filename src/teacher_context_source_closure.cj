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

private func teacherRenderSourceClosureWitness(manifestHash: String,
    hashes: Array<String>, closureHash: String): String {
    let evidence = "{\"schemaVersion\":\"teacher-context-source-closure-v1\"," +
        "\"sourceEvidenceManifestHash\":\"${manifestHash}\",\"sourceHashes\":[${teacherClosureHashArray(hashes)}]}"
    let expected = "sha256:${teacherStableHash(evidence)}"
    if (closureHash != expected) { throw IllegalArgumentException("candidate_set_hash_mismatch") }
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

private func teacherClosureCollect(root: Path, values: ArrayList<String>): Unit {
    if (FileInfo(root).isSymbolicLink() || !FileInfo(root).isDirectory()) {
        throw IllegalArgumentException("artifact_input_invalid")
    }
    for (entry in Directory.readFrom(root)) {
        if (entry.isSymbolicLink()) { throw IllegalArgumentException("artifact_input_invalid") }
        if (entry.isDirectory()) { teacherClosureCollect(entry.path, values) }
        else if (entry.isRegular()) { values.add(teacherReadUtf8File(entry.path.toString())) }
        else { throw IllegalArgumentException("artifact_input_invalid") }
    }
}

private func teacherClosureReadFiles(allowedRoot: String, root: String): Array<String> {
    let canonical = teacherResolveArtifactInput(allowedRoot, root, directory: true)
    let values = ArrayList<String>(); teacherClosureCollect(Path(canonical), values)
    if (values.isEmpty()) { throw IllegalArgumentException("candidate_set_schema_invalid") }
    values.toArray()
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
    let sourceValues = teacherClosureReadFiles(canonicalAllowed, sourcesPath)
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
    let sourceEvidence = "{\"schemaVersion\":\"teacher-context-source-closure-v1\"," +
        "\"sourceEvidenceManifestHash\":\"${manifest.sourceManifestHash}\",\"sourceHashes\":[${teacherClosureHashArray(sourceHashes)}]}"
    let sourceHash = "sha256:${teacherStableHash(sourceEvidence)}"

    let protectedValues = teacherClosureReadFiles(allowedRoot, protectedRoot)
    let protectedHashes = teacherClosureHashes(protectedValues)
    let protectedEvidence = "{\"schemaVersion\":\"teacher-context-protected-closure-v1\"," +
        "\"protectedHashes\":[${teacherClosureHashArray(protectedHashes)}]}"
    let protectedHash = "sha256:${teacherStableHash(protectedEvidence)}"
    TeacherContextSourceClosure(manifest, sourceHash, protectedHash, protectedValues, [
        TeacherArtifactFile("source-closure.json",
            teacherRenderSourceClosureWitness(manifest.sourceManifestHash, sourceHashes, sourceHash) + "\n"),
        TeacherArtifactFile("protected-closure.json",
            teacherRenderProtectedClosureWitness(protectedHashes, protectedHash) + "\n")
    ])
}
