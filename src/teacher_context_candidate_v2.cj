package cangjie_teacher

import std.collection.*
import std.fs.*
import std.sort.*
import stdx.encoding.json.*

public class TeacherArtifactFile {
    public let path: String
    public let content: String
    public init(path: String, content: String) { this.path = path; this.content = content }
}

public class TeacherContextLaneV2 {
    public let eligible: Bool
    public let hash: String
    public let treeHash: String
    public let count: Int64
    public let lineage: String
    public let visibleContent: String
    public let files: Array<TeacherArtifactFile>
    public init(eligible: Bool, hash: String, treeHash: String, count: Int64, lineage: String,
        visibleContent: String, files: Array<TeacherArtifactFile>) {
        this.eligible = eligible; this.hash = hash; this.treeHash = treeHash; this.count = count
        this.lineage = lineage; this.visibleContent = visibleContent; this.files = files
    }
}

public class TeacherContextCandidateSetV2 {
    public let candidateSetId: String
    public let baseCompositeHash: String
    public let validationLevel: String
    public let sourceEvidenceManifestHash: String
    public let classificationManifestHash: String
    public let sourceClosureHash: String
    public let protectedClosureHash: String
    public let rules: TeacherContextLaneV2
    public let skills: TeacherContextLaneV2
    public let knowledge: TeacherContextLaneV2
    public let knowledgeTargetVersion: String
    public let assetInventoryHash: String
    public let combinationAuditHash: String
    public let candidateSetHash: String
    public init(candidateSetId: String, baseCompositeHash: String, validationLevel: String,
        sourceEvidenceManifestHash: String, classificationManifestHash: String,
        sourceClosureHash: String, protectedClosureHash: String, rules: TeacherContextLaneV2,
        skills: TeacherContextLaneV2, knowledge: TeacherContextLaneV2,
        knowledgeTargetVersion: String, assetInventoryHash: String,
        combinationAuditHash: String, candidateSetHash: String) {
        this.candidateSetId = candidateSetId; this.baseCompositeHash = baseCompositeHash
        this.validationLevel = validationLevel; this.sourceEvidenceManifestHash = sourceEvidenceManifestHash
        this.classificationManifestHash = classificationManifestHash
        this.sourceClosureHash = sourceClosureHash; this.protectedClosureHash = protectedClosureHash
        this.rules = rules; this.skills = skills; this.knowledge = knowledge
        this.knowledgeTargetVersion = knowledgeTargetVersion; this.assetInventoryHash = assetInventoryHash
        this.combinationAuditHash = combinationAuditHash; this.candidateSetHash = candidateSetHash
    }
}

private func teacherV2Hash(value: String): Bool {
    let runes = value.toRuneArray()
    if (!value.startsWith("sha256:") || runes.size != 71) { return false }
    for (i in 7..runes.size) {
        let rune = runes[i]
        if (!((rune >= r'0' && rune <= r'9') || (rune >= r'a' && rune <= r'f'))) { return false }
    }
    true
}

private func teacherV2RelativePath(value: String): Bool {
    if (value.isEmpty() || value.startsWith("/") || value.endsWith("/") || value.contains("\\")) {
        return false
    }
    for (component in value.split("/")) {
        if (component.isEmpty() || component == "." || component == ".." || component.contains("..")) {
            return false
        }
        for (rune in component.toRuneArray()) {
            if (!((rune >= r'a' && rune <= r'z') || (rune >= r'A' && rune <= r'Z') ||
                (rune >= r'0' && rune <= r'9') ||
                rune == r'-' || rune == r'_' || rune == r'.')) { return false }
        }
    }
    true
}

private func teacherV2SortedFiles(files: Array<TeacherArtifactFile>): Array<TeacherArtifactFile> {
    let paths = files.map({file: TeacherArtifactFile => file.path}); sort(paths)
    let out = ArrayList<TeacherArtifactFile>(); let seen = HashSet<String>()
    for (path in paths) {
        if (!teacherV2RelativePath(path) || seen.contains(path)) {
            throw IllegalArgumentException("candidate_set_schema_invalid")
        }
        seen.add(path)
        for (file in files) { if (file.path == path) { out.add(file); break } }
    }
    out.toArray()
}

private func teacherV2Inventory(files: Array<TeacherArtifactFile>, prefix!: String = ""): String {
    var out = ""
    for (file in teacherV2SortedFiles(files)) {
        let path = if (prefix.isEmpty()) { file.path } else { "${prefix}/${file.path}" }
        out += "${teacherStableHash(file.content)}  ${path}\n"
    }
    out
}

public func teacherContextLaneTreeHashV2(files: Array<TeacherArtifactFile>): String {
    "sha256:${teacherStableHash(teacherV2Inventory(files))}"
}

private func teacherV2AllFiles(rules: Array<TeacherArtifactFile>, skills: Array<TeacherArtifactFile>,
    knowledge: Array<TeacherArtifactFile>): Array<TeacherArtifactFile> {
    let out = ArrayList<TeacherArtifactFile>()
    for (file in rules) { out.add(TeacherArtifactFile("rules/${file.path}", file.content)) }
    for (file in skills) { out.add(TeacherArtifactFile("skills/${file.path}", file.content)) }
    for (file in knowledge) { out.add(TeacherArtifactFile("knowledge/${file.path}", file.content)) }
    out.toArray()
}

public func teacherContextAssetInventoryHashV2(rules: Array<TeacherArtifactFile>,
    skills: Array<TeacherArtifactFile>, knowledge: Array<TeacherArtifactFile>): String {
    "sha256:${teacherStableHash(teacherV2Inventory(teacherV2AllFiles(rules, skills, knowledge)))}"
}

private func teacherV2ManifestEvidence(value: TeacherContextCandidateSetV2): String {
    "{\"schemaVersion\":\"teacher-student-context-candidate-set-v2\"," +
        "\"candidateSetId\":\"${value.candidateSetId}\",\"baseCompositeHash\":\"${value.baseCompositeHash}\"," +
        "\"validationLevel\":\"${value.validationLevel}\",\"sourceEvidenceManifestHash\":\"${value.sourceEvidenceManifestHash}\"," +
        "\"classificationManifestHash\":\"${value.classificationManifestHash}\",\"sourceClosureHash\":\"${value.sourceClosureHash}\"," +
        "\"protectedClosureHash\":\"${value.protectedClosureHash}\",\"rulesEligible\":${value.rules.eligible}," +
        "\"rulesHash\":\"${value.rules.hash}\",\"rulesTreeHash\":\"${value.rules.treeHash}\",\"rulesCount\":${value.rules.count}," +
        "\"rulesAssetLineage\":\"${value.rules.lineage}\",\"skillsEligible\":${value.skills.eligible}," +
        "\"skillsHash\":\"${value.skills.hash}\",\"skillsTreeHash\":\"${value.skills.treeHash}\",\"skillsCount\":${value.skills.count}," +
        "\"skillAssetLineage\":\"${value.skills.lineage}\",\"knowledgeEligible\":${value.knowledge.eligible}," +
        "\"knowledgeCandidateHash\":\"${value.knowledge.hash}\",\"knowledgeTreeHash\":\"${value.knowledge.treeHash}\"," +
        "\"knowledgeTargetVersion\":\"${value.knowledgeTargetVersion}\",\"knowledgeAssetLineage\":\"${value.knowledge.lineage}\"," +
        "\"assetInventoryHash\":\"${value.assetInventoryHash}\",\"combinationAuditHash\":\"${value.combinationAuditHash}\"}"
}

private func teacherV2CombinationHash(rules: TeacherContextLaneV2, skills: TeacherContextLaneV2,
    knowledge: TeacherContextLaneV2, sourceClosureHash: String, protectedClosureHash: String): String {
    let rulesBinding = if (rules.eligible) { rules.visibleContent } else { rules.hash }
    let skillsBinding = if (skills.eligible) { skills.visibleContent } else { skills.hash }
    let knowledgeBinding = if (knowledge.eligible) { knowledge.visibleContent } else { knowledge.hash }
    let evidence = "${rulesBinding.toArray().size}:${rulesBinding}" +
        "${skillsBinding.toArray().size}:${skillsBinding}" +
        "${knowledgeBinding.toArray().size}:${knowledgeBinding}" +
        "${sourceClosureHash}${protectedClosureHash}"
    "sha256:${teacherStableHash(evidence)}"
}

public func sealTeacherContextCandidateSetV2(candidateSetId: String, baseCompositeHash: String,
    validationLevel: String, sourceEvidenceManifestHash: String, classificationManifestHash: String,
    sourceClosureHash: String, protectedClosureHash: String, rules: TeacherContextLaneV2,
    skills: TeacherContextLaneV2, knowledge: TeacherContextLaneV2,
    knowledgeTargetVersion: String): TeacherContextCandidateSetV2 {
    if (!teacherArtifactSafeComponent(candidateSetId) ||
        !(baseCompositeHash == "none" || teacherV2Hash(baseCompositeHash)) ||
        !["scaffold_contract", "student_validated"].contains(validationLevel) ||
        !teacherV2Hash(sourceEvidenceManifestHash) || !teacherV2Hash(sourceClosureHash) ||
        !teacherV2Hash(protectedClosureHash) || knowledgeTargetVersion.isEmpty() ||
        !(classificationManifestHash.isEmpty() || teacherV2Hash(classificationManifestHash))) {
        throw IllegalArgumentException("candidate_set_schema_invalid")
    }
    for (lane in [rules, skills, knowledge]) {
        if (!teacherV2Hash(lane.hash) || !teacherV2Hash(lane.treeHash) || lane.count < 0 ||
            !["independent", "humaneval_164_derived"].contains(lane.lineage) ||
            lane.treeHash != teacherContextLaneTreeHashV2(lane.files)) {
            throw IllegalArgumentException("candidate_lane_hash_mismatch")
        }
    }
    let inventoryHash = teacherContextAssetInventoryHashV2(rules.files, skills.files, knowledge.files)
    let combinationHash = teacherV2CombinationHash(rules, skills, knowledge,
        sourceClosureHash, protectedClosureHash)
    let provisional = TeacherContextCandidateSetV2(candidateSetId, baseCompositeHash, validationLevel,
        sourceEvidenceManifestHash, classificationManifestHash, sourceClosureHash, protectedClosureHash,
        rules, skills, knowledge, knowledgeTargetVersion, inventoryHash, combinationHash, "")
    TeacherContextCandidateSetV2(candidateSetId, baseCompositeHash, validationLevel,
        sourceEvidenceManifestHash, classificationManifestHash, sourceClosureHash, protectedClosureHash,
        rules, skills, knowledge, knowledgeTargetVersion, inventoryHash, combinationHash,
        "sha256:${teacherStableHash(teacherV2ManifestEvidence(provisional))}")
}

public func renderTeacherContextCandidateSetManifestV2(value: TeacherContextCandidateSetV2): String {
    let resealed = sealTeacherContextCandidateSetV2(value.candidateSetId, value.baseCompositeHash,
        value.validationLevel, value.sourceEvidenceManifestHash, value.classificationManifestHash,
        value.sourceClosureHash, value.protectedClosureHash, value.rules, value.skills, value.knowledge,
        value.knowledgeTargetVersion)
    if (value.assetInventoryHash != resealed.assetInventoryHash ||
        value.combinationAuditHash != resealed.combinationAuditHash ||
        value.candidateSetHash != resealed.candidateSetHash) {
        throw IllegalArgumentException("candidate_set_hash_mismatch")
    }
    let evidence = teacherV2ManifestEvidence(value); let runes = evidence.toRuneArray()
    String(runes[..runes.size - 1]) + ",\"candidateSetHash\":\"${value.candidateSetHash}\"}"
}

private func teacherV2String(object: JsonObject, name: String): String {
    match (object.get(name)) { case Some(value) => value.asString().getValue(); case None => "" }
}

private func teacherV2Bool(object: JsonObject, name: String): Bool {
    match (object.get(name)) { case Some(value) => value.asBool().getValue(); case None => false }
}

private func teacherV2Int(object: JsonObject, name: String): Int64 {
    match (object.get(name)) { case Some(value) => value.asInt().getValue(); case None => Int64(-1) }
}

private func teacherV2CollectFiles(current: Path, relative: String,
    files: ArrayList<TeacherArtifactFile>): Unit {
    if (FileInfo(current).isSymbolicLink() || !FileInfo(current).isDirectory()) {
        throw IllegalArgumentException("candidate_set_schema_invalid")
    }
    for (entry in Directory.readFrom(current)) {
        if (entry.isSymbolicLink()) { throw IllegalArgumentException("candidate_set_schema_invalid") }
        let child = if (relative.isEmpty()) { entry.name } else { "${relative}/${entry.name}" }
        if (!teacherV2RelativePath(child)) { throw IllegalArgumentException("candidate_set_schema_invalid") }
        if (entry.isDirectory()) { teacherV2CollectFiles(entry.path, child, files) }
        else if (entry.isRegular()) { files.add(TeacherArtifactFile(child, teacherReadUtf8File(entry.path.toString()))) }
        else { throw IllegalArgumentException("candidate_set_schema_invalid") }
    }
}

private func teacherV2ReadLane(root: Path, name: String): Array<TeacherArtifactFile> {
    let files = ArrayList<TeacherArtifactFile>(); teacherV2CollectFiles(root.join(name), "", files)
    teacherV2SortedFiles(files.toArray())
}

private func teacherV2LaneFromManifest(object: JsonObject, name: String,
    files: Array<TeacherArtifactFile>, visibleContent: String): TeacherContextLaneV2 {
    let prefix = if (name == "skills") { "skill" } else { name }
    TeacherContextLaneV2(teacherV2Bool(object, "${name}Eligible"),
        teacherV2String(object, if (name == "knowledge") { "knowledgeCandidateHash" } else { "${name}Hash" }),
        teacherV2String(object, "${name}TreeHash"),
        if (name == "knowledge") { Int64(1) } else { teacherV2Int(object, "${name}Count") },
        teacherV2String(object, "${prefix}AssetLineage"), visibleContent, files)
}

public func parseTeacherContextCandidateSetDirectoryV2(path: String): TeacherContextCandidateSetV2 {
    let root = Path(path)
    try {
        if (!exists(root) || FileInfo(root).isSymbolicLink() || !FileInfo(root).isDirectory()) {
            throw IllegalArgumentException("candidate_set_schema_invalid")
        }
        let expected = HashSet<String>(["candidate-set-manifest.json", "rules", "skills", "knowledge"])
        for (entry in Directory.readFrom(root)) {
            if (!expected.contains(entry.name) || entry.isSymbolicLink()) {
                throw IllegalArgumentException("candidate_set_schema_invalid")
            }
            expected.remove(entry.name)
        }
        if (!expected.isEmpty()) { throw IllegalArgumentException("candidate_set_schema_invalid") }
        let raw = teacherReadUtf8File(root.join("candidate-set-manifest.json").toString()).trimAscii()
        let object = JsonValue.fromStr(raw).asObject()
        if (object.getFields().size != 26 ||
            teacherV2String(object, "schemaVersion") != "teacher-student-context-candidate-set-v2") {
            throw IllegalArgumentException("candidate_set_schema_invalid")
        }
        let rulesFiles = teacherV2ReadLane(root, "rules")
        let skillsFiles = teacherV2ReadLane(root, "skills")
        let knowledgeFiles = teacherV2ReadLane(root, "knowledge")
        var rulesVisible = ""; for (file in rulesFiles) { if (file.path.endsWith("/AGENTS.md")) { rulesVisible += file.content } }
        var skillsVisible = ""; for (file in skillsFiles) { if (file.path.endsWith("/SKILL.md")) { skillsVisible += file.content } }
        var knowledgeVisible = ""; for (file in knowledgeFiles) {
            if (file.path == "knowledge-candidate-reference.json") { knowledgeVisible = file.content }
        }
        let rules = teacherV2LaneFromManifest(object, "rules", rulesFiles, rulesVisible)
        let skills = teacherV2LaneFromManifest(object, "skills", skillsFiles, skillsVisible)
        let knowledge = teacherV2LaneFromManifest(object, "knowledge", knowledgeFiles, knowledgeVisible)
        let sealed = sealTeacherContextCandidateSetV2(teacherV2String(object, "candidateSetId"),
            teacherV2String(object, "baseCompositeHash"), teacherV2String(object, "validationLevel"),
            teacherV2String(object, "sourceEvidenceManifestHash"),
            teacherV2String(object, "classificationManifestHash"),
            teacherV2String(object, "sourceClosureHash"), teacherV2String(object, "protectedClosureHash"),
            rules, skills, knowledge, teacherV2String(object, "knowledgeTargetVersion"))
        if (teacherV2String(object, "assetInventoryHash") != sealed.assetInventoryHash ||
            teacherV2String(object, "combinationAuditHash") != sealed.combinationAuditHash ||
            teacherV2String(object, "candidateSetHash") != sealed.candidateSetHash ||
            raw != renderTeacherContextCandidateSetManifestV2(sealed)) {
            throw IllegalArgumentException("candidate_set_hash_mismatch")
        }
        sealed
    } catch (e: IllegalArgumentException) { throw e }
    catch (_: Exception) { throw IllegalArgumentException("candidate_set_schema_invalid") }
}

private func teacherV2WriteFiles(root: String, prefix: String, files: Array<TeacherArtifactFile>): Unit {
    for (file in teacherV2SortedFiles(files)) {
        _ = teacherAtomicWrite("${root}/${prefix}/${file.path}", file.content)
    }
}

public func exportTeacherContextCandidateSetV2(value: TeacherContextCandidateSetV2,
    allowedRoot: String, outputRoot: String): String {
    let output = teacherResolveArtifactInput(allowedRoot, outputRoot, directory: true)
    if (!teacherArtifactSafeComponent(value.candidateSetId)) {
        throw IllegalArgumentException("candidate_set_id_invalid")
    }
    let manifest = renderTeacherContextCandidateSetManifestV2(value)
    let target = "${output}/${value.candidateSetId}"
    if (exists(Path(target))) {
        let parsed = parseTeacherContextCandidateSetDirectoryV2(target)
        if (parsed.candidateSetHash != value.candidateSetHash) {
            throw IllegalArgumentException("candidate_set_hash_mismatch")
        }
        return manifest
    }
    let nonce = teacherStableHash(manifest)
    let stage = teacherArtifactStagePath(output, value.candidateSetId, nonce)
    if (exists(Path(stage))) { throw IllegalArgumentException("artifact_stage_invalid") }
    var created = false
    try {
        Directory.create(Path("${stage}/rules"), recursive: true); created = true
        Directory.create(Path("${stage}/skills"), recursive: true)
        Directory.create(Path("${stage}/knowledge"), recursive: true)
        teacherV2WriteFiles(stage, "rules", value.rules.files)
        teacherV2WriteFiles(stage, "skills", value.skills.files)
        teacherV2WriteFiles(stage, "knowledge", value.knowledge.files)
        _ = teacherAtomicWrite("${stage}/candidate-set-manifest.json", manifest + "\n")
        _ = parseTeacherContextCandidateSetDirectoryV2(stage)
        rename(Path(stage), to: Path(target), overwrite: false); created = false
    } catch (e: Exception) {
        if (created) { try { teacherRemoveCreatedArtifactStage(output, stage) } catch (_: Exception) {} }
        throw e
    }
    manifest
}

private func teacherV2ApprovalEscape(value: String): String {
    value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
        .replace("\r", "\\r").replace("\t", "\\t")
}

public func renderTeacherContextApprovalV2(candidate: TeacherContextCandidateSetV2,
    decision: String, reviewer: String, reason: String, approvedAtUtc: String): String {
    if (!["approve", "reject"].contains(decision) || reviewer.isEmpty() || reason.isEmpty() ||
        approvedAtUtc.isEmpty()) { throw IllegalArgumentException("candidate_approval_rejected") }
    "{\"schemaVersion\":\"teacher-student-context-approval-v2\"," +
        "\"candidateSetHash\":\"${candidate.candidateSetHash}\",\"assetInventoryHash\":\"${candidate.assetInventoryHash}\"," +
        "\"rulesHash\":\"${candidate.rules.hash}\",\"rulesTreeHash\":\"${candidate.rules.treeHash}\"," +
        "\"skillsHash\":\"${candidate.skills.hash}\",\"skillsTreeHash\":\"${candidate.skills.treeHash}\"," +
        "\"knowledgeCandidateHash\":\"${candidate.knowledge.hash}\",\"knowledgeTreeHash\":\"${candidate.knowledge.treeHash}\"," +
        "\"sourceClosureHash\":\"${candidate.sourceClosureHash}\",\"protectedClosureHash\":\"${candidate.protectedClosureHash}\"," +
        "\"combinationAuditHash\":\"${candidate.combinationAuditHash}\",\"decision\":\"${decision}\"," +
        "\"reviewer\":\"${teacherV2ApprovalEscape(reviewer)}\",\"reason\":\"${teacherV2ApprovalEscape(reason)}\"," +
        "\"approvedAtUtc\":\"${teacherV2ApprovalEscape(approvedAtUtc)}\"}"
}

public func validateTeacherContextApprovalV2(raw: String,
    candidate: TeacherContextCandidateSetV2): String {
    try {
        let object = JsonValue.fromStr(raw).asObject()
        if (object.getFields().size != 16 ||
            teacherV2String(object, "schemaVersion") != "teacher-student-context-approval-v2") {
            throw IllegalArgumentException("candidate_approval_hash_mismatch")
        }
        let decision = teacherV2String(object, "decision")
        let expected = renderTeacherContextApprovalV2(candidate, decision,
            teacherV2String(object, "reviewer"), teacherV2String(object, "reason"),
            teacherV2String(object, "approvedAtUtc"))
        if (raw != expected || teacherV2String(object, "candidateSetHash") != candidate.candidateSetHash ||
            teacherV2String(object, "assetInventoryHash") != candidate.assetInventoryHash ||
            teacherV2String(object, "rulesHash") != candidate.rules.hash ||
            teacherV2String(object, "rulesTreeHash") != candidate.rules.treeHash ||
            teacherV2String(object, "skillsHash") != candidate.skills.hash ||
            teacherV2String(object, "skillsTreeHash") != candidate.skills.treeHash ||
            teacherV2String(object, "knowledgeCandidateHash") != candidate.knowledge.hash ||
            teacherV2String(object, "knowledgeTreeHash") != candidate.knowledge.treeHash ||
            teacherV2String(object, "sourceClosureHash") != candidate.sourceClosureHash ||
            teacherV2String(object, "protectedClosureHash") != candidate.protectedClosureHash ||
            teacherV2String(object, "combinationAuditHash") != candidate.combinationAuditHash) {
            throw IllegalArgumentException("candidate_approval_hash_mismatch")
        }
        decision
    } catch (e: IllegalArgumentException) { throw e }
    catch (_: Exception) { throw IllegalArgumentException("candidate_approval_hash_mismatch") }
}
