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
    public let auditFiles: Array<TeacherArtifactFile>
    init(candidateSetId: String, baseCompositeHash: String, validationLevel: String,
        sourceEvidenceManifestHash: String, classificationManifestHash: String,
        sourceClosureHash: String, protectedClosureHash: String, rules: TeacherContextLaneV2,
        skills: TeacherContextLaneV2, knowledge: TeacherContextLaneV2,
        knowledgeTargetVersion: String, assetInventoryHash: String,
        combinationAuditHash: String, candidateSetHash: String,
        auditFiles: Array<TeacherArtifactFile>) {
        this.candidateSetId = candidateSetId; this.baseCompositeHash = baseCompositeHash
        this.validationLevel = validationLevel; this.sourceEvidenceManifestHash = sourceEvidenceManifestHash
        this.classificationManifestHash = classificationManifestHash
        this.sourceClosureHash = sourceClosureHash; this.protectedClosureHash = protectedClosureHash
        this.rules = rules; this.skills = skills; this.knowledge = knowledge
        this.knowledgeTargetVersion = knowledgeTargetVersion; this.assetInventoryHash = assetInventoryHash
        this.combinationAuditHash = combinationAuditHash; this.candidateSetHash = candidateSetHash
        this.auditFiles = auditFiles
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
    knowledge: Array<TeacherArtifactFile>, audit: Array<TeacherArtifactFile>): Array<TeacherArtifactFile> {
    let out = ArrayList<TeacherArtifactFile>()
    for (file in rules) { out.add(TeacherArtifactFile("rules/${file.path}", file.content)) }
    for (file in skills) { out.add(TeacherArtifactFile("skills/${file.path}", file.content)) }
    for (file in knowledge) { out.add(TeacherArtifactFile("knowledge/${file.path}", file.content)) }
    for (file in audit) { out.add(TeacherArtifactFile("audit/${file.path}", file.content)) }
    out.toArray()
}

public func teacherContextAssetInventoryHashV2(rules: Array<TeacherArtifactFile>,
    skills: Array<TeacherArtifactFile>, knowledge: Array<TeacherArtifactFile>,
    audit!: Array<TeacherArtifactFile> = []): String {
    "sha256:${teacherStableHash(teacherV2Inventory(teacherV2AllFiles(rules, skills, knowledge, audit)))}"
}

private func teacherV2Escape(value: String): String {
    value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
        .replace("\r", "\\r").replace("\t", "\\t")
}

private func teacherV2SafeVersion(value: String): Bool {
    let runes = value.toRuneArray()
    if (runes.isEmpty() || runes.size > 128) { return false }
    for (rune in runes) {
        if (!((rune >= r'a' && rune <= r'z') || (rune >= r'A' && rune <= r'Z') ||
            (rune >= r'0' && rune <= r'9') || rune == r'.' || rune == r'-' ||
            rune == r'_' || rune == r'+')) { return false }
    }
    true
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
        "\"knowledgeTargetVersion\":\"${teacherV2Escape(value.knowledgeTargetVersion)}\",\"knowledgeAssetLineage\":\"${value.knowledge.lineage}\"," +
        "\"assetInventoryHash\":\"${value.assetInventoryHash}\",\"combinationAuditHash\":\"${value.combinationAuditHash}\"}"
}

private func teacherV2CombinationHash(rules: TeacherContextLaneV2, skills: TeacherContextLaneV2,
    knowledge: TeacherContextLaneV2, sourceClosureHash: String, protectedClosureHash: String): String {
    let knowledgeContentHash = if (knowledge.eligible) {
        parseTeacherFrozenKnowledgeReference(knowledge.visibleContent.trimAscii()).knowledgeContentHash
    } else { knowledge.hash }
    let values = [rules.hash, skills.hash, knowledgeContentHash, sourceClosureHash, protectedClosureHash]
    let evidence = teacherJoin(values.map({value: String => "${value.toArray().size}:${value}"}), "")
    "sha256:${teacherStableHash(evidence)}"
}

private func teacherSealContextCandidateSetV2(candidateSetId: String, baseCompositeHash: String,
    validationLevel: String, sourceEvidenceManifestHash: String, classificationManifestHash: String,
    sourceClosureHash: String, protectedClosureHash: String, rules: TeacherContextLaneV2,
    skills: TeacherContextLaneV2, knowledge: TeacherContextLaneV2,
    knowledgeTargetVersion: String, auditFiles: Array<TeacherArtifactFile>): TeacherContextCandidateSetV2 {
    if (!teacherArtifactSafeComponent(candidateSetId) ||
        !(baseCompositeHash == "none" || teacherV2Hash(baseCompositeHash)) ||
        !["scaffold_contract", "student_validated"].contains(validationLevel) ||
        !teacherV2Hash(sourceEvidenceManifestHash) || !teacherV2Hash(sourceClosureHash) ||
        !teacherV2Hash(protectedClosureHash) || !teacherV2SafeVersion(knowledgeTargetVersion) ||
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
    let inventoryHash = teacherContextAssetInventoryHashV2(rules.files, skills.files, knowledge.files, audit: auditFiles)
    let combinationHash = teacherV2CombinationHash(rules, skills, knowledge,
        sourceClosureHash, protectedClosureHash)
    let provisional = TeacherContextCandidateSetV2(candidateSetId, baseCompositeHash, validationLevel,
        sourceEvidenceManifestHash, classificationManifestHash, sourceClosureHash, protectedClosureHash,
        rules, skills, knowledge, knowledgeTargetVersion, inventoryHash, combinationHash, "", auditFiles)
    TeacherContextCandidateSetV2(candidateSetId, baseCompositeHash, validationLevel,
        sourceEvidenceManifestHash, classificationManifestHash, sourceClosureHash, protectedClosureHash,
        rules, skills, knowledge, knowledgeTargetVersion, inventoryHash, combinationHash,
        "sha256:${teacherStableHash(teacherV2ManifestEvidence(provisional))}", auditFiles)
}

public func sealTeacherContextCandidateSetV2(candidateSetId: String, baseCompositeHash: String,
    validationLevel: String, classificationManifestHash: String,
    sourceClosure: TeacherContextSourceClosure, rules: TeacherContextLaneV2,
    skills: TeacherContextLaneV2, knowledge: TeacherContextLaneV2,
    knowledgeTargetVersion: String): TeacherContextCandidateSetV2 {
    teacherSealContextCandidateSetV2(candidateSetId, baseCompositeHash, validationLevel,
        sourceClosure.manifest.sourceManifestHash, classificationManifestHash,
        sourceClosure.sourceClosureHash, sourceClosure.protectedClosureHash,
        rules, skills, knowledge, knowledgeTargetVersion, sourceClosure.auditFiles)
}

public func renderTeacherContextCandidateSetManifestV2(value: TeacherContextCandidateSetV2): String {
    let resealed = teacherSealContextCandidateSetV2(value.candidateSetId, value.baseCompositeHash,
        value.validationLevel, value.sourceEvidenceManifestHash, value.classificationManifestHash,
        value.sourceClosureHash, value.protectedClosureHash, value.rules, value.skills, value.knowledge,
        value.knowledgeTargetVersion, value.auditFiles)
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

private func teacherV2HashArray(object: JsonObject, name: String): Array<String> {
    let out = ArrayList<String>()
    match (object.get(name)) {
        case Some(value) => for (item in value.asArray().getItems()) { out.add(item.asString().getValue()) }
        case None => throw IllegalArgumentException("candidate_set_schema_invalid")
    }
    let values = out.toArray(); let sorted = values.clone(); sort(sorted)
    if (values.isEmpty() || values != sorted) { throw IllegalArgumentException("candidate_set_schema_invalid") }
    let seen = HashSet<String>()
    for (hash in values) {
        if (!teacherV2Hash(hash) || seen.contains(hash)) {
            throw IllegalArgumentException("candidate_set_schema_invalid")
        }
        seen.add(hash)
    }
    values
}

private func teacherV2HashArrayJson(values: Array<String>): String {
    teacherJoin(values.map({value: String => "\"${value}\""}), ",")
}

private func teacherV2SourceInventory(object: JsonObject): Array<String> {
    let out = ArrayList<String>()
    match (object.get("sourceInventory")) {
        case Some(value) => for (item in value.asArray().getItems()) {
            out.add(item.asString().getValue())
        }
        case None => throw IllegalArgumentException("candidate_set_schema_invalid")
    }
    let rows = out.toArray()
    if (rows.isEmpty()) { throw IllegalArgumentException("candidate_set_schema_invalid") }
    let paths = ArrayList<String>(); let seen = HashSet<String>()
    for (row in rows) {
        let parts = row.split("  ")
        if (parts.size != 2 || parts[0].toRuneArray().size != 64 ||
            !teacherV2Hash("sha256:${parts[0]}") || !teacherV2RelativePath(parts[1]) ||
            seen.contains(parts[1])) {
            throw IllegalArgumentException("candidate_set_schema_invalid")
        }
        seen.add(parts[1]); paths.add(parts[1])
    }
    let sortedPaths = paths.toArray().clone(); sort(sortedPaths)
    if (paths.toArray() != sortedPaths) { throw IllegalArgumentException("candidate_set_schema_invalid") }
    rows
}

private func teacherV2ValidateAudit(files: Array<TeacherArtifactFile>, sourceManifestHash: String,
    sourceClosureHash: String, protectedClosureHash: String): Unit {
    if (files.size != 2 || files[0].path != "protected-closure.json" ||
        files[1].path != "source-closure.json") {
        throw IllegalArgumentException("candidate_set_schema_invalid")
    }
    try {
        let sourceRaw = files[1].content.trimAscii(); let source = JsonValue.fromStr(sourceRaw).asObject()
        if (source.getFields().size != 4 || teacherV2String(source, "schemaVersion") !=
            "teacher-context-source-closure-v2") { throw IllegalArgumentException("candidate_set_schema_invalid") }
        let sourceInventory = teacherV2SourceInventory(source)
        let sourceEvidence = "{\"schemaVersion\":\"teacher-context-source-closure-v2\"," +
            "\"sourceEvidenceManifestHash\":\"${sourceManifestHash}\",\"sourceInventory\":[${teacherV2HashArrayJson(sourceInventory)}]"
        if (teacherV2String(source, "sourceEvidenceManifestHash") != sourceManifestHash ||
            teacherV2String(source, "sourceClosureHash") != sourceClosureHash ||
            sourceClosureHash != "sha256:${teacherStableHash(sourceEvidence + "}")}" ||
            sourceRaw != sourceEvidence + ",\"sourceClosureHash\":\"${sourceClosureHash}\"}") {
            throw IllegalArgumentException("candidate_set_hash_mismatch")
        }
        let protectedRaw = files[0].content.trimAscii()
        let protected = JsonValue.fromStr(protectedRaw).asObject()
        if (protected.getFields().size != 3 || teacherV2String(protected, "schemaVersion") !=
            "teacher-context-protected-closure-v1") { throw IllegalArgumentException("candidate_set_schema_invalid") }
        let protectedHashes = teacherV2HashArray(protected, "protectedHashes")
        let protectedEvidence = "{\"schemaVersion\":\"teacher-context-protected-closure-v1\"," +
            "\"protectedHashes\":[${teacherV2HashArrayJson(protectedHashes)}]}"
        if (teacherV2String(protected, "protectedClosureHash") != protectedClosureHash ||
            protectedClosureHash != "sha256:${teacherStableHash(protectedEvidence)}" ||
            protectedRaw != String(protectedEvidence.toRuneArray()[..protectedEvidence.toRuneArray().size - 1]) +
                ",\"protectedClosureHash\":\"${protectedClosureHash}\"}") {
            throw IllegalArgumentException("candidate_set_hash_mismatch")
        }
    } catch (e: IllegalArgumentException) { throw e }
    catch (_: Exception) { throw IllegalArgumentException("candidate_set_schema_invalid") }
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

private func teacherV2File(files: Array<TeacherArtifactFile>, path: String): String {
    for (file in files) { if (file.path == path) { return file.content } }
    throw IllegalArgumentException("candidate_lane_hash_mismatch")
}

private func teacherV2ValidateExecution(files: Array<TeacherArtifactFile>, prefix: String): (String, String, String) {
    let fixtureRaw = teacherV2File(files, "${prefix}/fixture.json").trimAscii()
    let expected = teacherV2File(files, "${prefix}/expected.txt").trimAscii()
    let actual = teacherV2File(files, "${prefix}/actual.txt").trimAscii()
    let transcript = teacherV2File(files, "${prefix}/transcript.txt").trimAscii()
    let executionRaw = teacherV2File(files, "${prefix}/execution.json").trimAscii()
    try {
        let fixture = JsonValue.fromStr(fixtureRaw).asObject()
        if (fixture.getFields().size != 7 || teacherV2String(fixture, "schemaVersion") !=
            "teacher-asset-fixture-v1") { throw IllegalArgumentException("candidate_test_evidence_invalid") }
        let value = TeacherAssetFixture(teacherV2String(fixture, "fixtureId"),
            teacherV2String(fixture, "kind"), teacherV2String(fixture, "sourceClass"),
            teacherV2String(fixture, "content"), teacherV2String(fixture, "expectedEvidence"))
        let fixtureHash = teacherAssetFixtureHash(value)
        if (fixtureRaw != renderTeacherAssetFixture(value) || expected != value.expectedEvidence ||
            teacherV2String(fixture, "fixtureHash") != fixtureHash) {
            throw IllegalArgumentException("candidate_test_evidence_invalid")
        }
        let execution = JsonValue.fromStr(executionRaw).asObject()
        if (execution.getFields().size != 13 || teacherV2String(execution, "schemaVersion") !=
            "teacher-candidate-fixture-execution-v1" ||
            teacherV2String(execution, "fixtureId") != value.fixtureId ||
            teacherV2String(execution, "kind") != value.kind ||
            teacherV2String(execution, "sourceClass") != value.sourceClass ||
            teacherV2String(execution, "fixtureHash") != fixtureHash ||
            teacherV2String(execution, "expectedEvidenceHash") !=
                "sha256:${teacherStableHash(expected)}" ||
            teacherV2String(execution, "actualEvidenceHash") !=
                "sha256:${teacherStableHash(actual)}" ||
            teacherV2String(execution, "transcriptHash") !=
                "sha256:${teacherStableHash(transcript)}" ||
            teacherV2Int(execution, "exitCode") != 0 || !teacherV2Bool(execution, "passed") ||
            expected != actual || !["fake_contract", "student_completion_non_humaneval"].contains(
                teacherV2String(execution, "executorKind")) ||
            !teacherV2Hash(teacherV2String(execution, "providerIdentityHash")) ||
            teacherV2String(execution, "modelVersion").isEmpty()) {
            throw IllegalArgumentException("candidate_test_evidence_invalid")
        }
        (value.kind, teacherV2String(execution, "transcriptHash"), value.sourceClass)
    } catch (e: IllegalArgumentException) { throw e }
    catch (_: Exception) { throw IllegalArgumentException("candidate_test_evidence_invalid") }
}

private func teacherV2DeriveLane(name: String, files: Array<TeacherArtifactFile>,
    manifest: JsonObject, baseCompositeHash: String, classificationHash: String,
    base: ?TeacherContextBaseStateV2): TeacherContextLaneV2 {
    let eligible = !files.isEmpty()
    if (eligible != teacherV2Bool(manifest, "${name}Eligible")) {
        throw IllegalArgumentException("candidate_lane_hash_mismatch")
    }
    if (!eligible) {
        if (baseCompositeHash == "none") { throw IllegalArgumentException("candidate_base_composite_mismatch") }
        let inherited = match (base) {
            case Some(value) => if (name == "rules") {
                TeacherContextLaneV2(false, value.rulesHash, teacherContextLaneTreeHashV2([]),
                    value.rulesCount, value.rulesLineage, value.rulesVisible, [])
            } else {
                TeacherContextLaneV2(false, value.skillsHash, teacherContextLaneTreeHashV2([]),
                    value.skillsCount, value.skillsLineage, value.skillsVisible, [])
            }
            case None => throw IllegalArgumentException("candidate_base_composite_mismatch")
        }
        let declared = teacherV2LaneFromManifest(manifest, name, files, inherited.visibleContent)
        if (declared.hash != inherited.hash || declared.count != inherited.count ||
            declared.lineage != inherited.lineage) {
            throw IllegalArgumentException("candidate_base_composite_mismatch")
        }
        return inherited
    }
    let lineage = if (baseCompositeHash == "none") { "independent" } else {
        if (classificationHash.isEmpty()) { throw IllegalArgumentException("candidate_lane_lineage_invalid") }
        "humaneval_164_derived"
    }
    let visibleName = if (name == "rules") { "/AGENTS.md" } else { "/SKILL.md" }
    let ids = HashSet<String>(); var visible = ""; let categories = HashMap<String, String>()
    var projectionAssets = match (base) {
        case Some(value) => if (name == "rules") { value.rulesAssets } else { value.skillsAssets }
        case None => Array<TeacherContextBaseAssetIdentity>()
    }
    var generalizationCount: Int64 = 0
    for (file in files) {
        let parts = file.path.split("/")
        if (parts.size < 2 || !teacherArtifactSafeComponent(parts[0])) {
            throw IllegalArgumentException("candidate_lane_hash_mismatch")
        }
        ids.add(parts[0])
        if (file.path.endsWith(visibleName)) { visible += file.content }
        if (file.path.endsWith("/execution.json")) {
            let suffix = "/execution.json"; let runes = file.path.toRuneArray()
            let prefix = String(runes[..runes.size - suffix.toRuneArray().size])
            let executed = teacherV2ValidateExecution(files, prefix)
            if (!categories.contains(executed[0])) { categories.add(executed[0], executed[1]) }
            if (executed[0] == "generalization" && executed[2] == "non_humaneval_experiment") {
                generalizationCount += 1
            }
        }
    }
    if (ids.isEmpty() || ids.size > 16 || visible.isEmpty() ||
        !categories.contains("positive") || !categories.contains("negative") ||
        !categories.contains("boundary") || !categories.contains("generalization") ||
        generalizationCount < 3 || (name == "rules" && !categories.contains("unit"))) {
        throw IllegalArgumentException("candidate_test_evidence_invalid")
    }
    for (id in ids) {
        let operation = JsonValue.fromStr(teacherV2File(files, "${id}/operation.json").trimAscii()).asObject()
        if (operation.getFields().size != 6 || teacherV2String(operation, "schemaVersion") !=
            "teacher-context-asset-operation-v1" || teacherV2String(operation, "assetRole") != name ||
            teacherV2String(operation, "assetId") != id ||
            !["add", "replace"].contains(teacherV2String(operation, "operation")) ||
            !teacherV2Hash(teacherV2String(operation, "newHash")) ||
            (baseCompositeHash == "none" && (teacherV2String(operation, "operation") != "add" ||
                !teacherV2String(operation, "expectedOldHash").isEmpty()))) {
            throw IllegalArgumentException("candidate_operation_invalid")
        }
        let baseAssets = match (base) {
            case Some(value) => if (name == "rules") { value.rulesAssets } else { value.skillsAssets }
            case None => Array<TeacherContextBaseAssetIdentity>()
        }
        _ = buildTeacherContextAssetOperation(name, id, teacherV2String(operation, "operation"),
            teacherV2String(operation, "expectedOldHash"), teacherV2String(operation, "newHash"),
            baseAssets)
        var assetContent = ""
        if (name == "rules") {
            let candidateRaw = teacherV2File(files, "${id}/candidate-manifest.json").trimAscii()
            let candidate = JsonValue.fromStr(candidateRaw).asObject()
            if (candidate.getFields().size != 17 || teacherV2String(candidate, "schemaVersion") !=
                "teacher-rule-candidate-v1" || teacherV2String(candidate, "ruleId") != id ||
                teacherV2String(candidate, "assetRole") != "rules" ||
                teacherV2String(candidate, "assetLineage") != lineage ||
                teacherV2String(candidate, "positiveEvidenceHash") != categories.get("positive").getOrThrow() ||
                teacherV2String(candidate, "negativeEvidenceHash") != categories.get("negative").getOrThrow() ||
                teacherV2String(candidate, "boundaryEvidenceHash") != categories.get("boundary").getOrThrow() ||
                teacherV2String(candidate, "generalizationEvidenceHash") != categories.get("generalization").getOrThrow()) {
                throw IllegalArgumentException("candidate_lane_hash_mismatch")
            }
            let fields = [teacherV2String(candidate, "ruleId"), teacherV2String(candidate, "conceptId"),
                teacherV2String(candidate, "title"), teacherV2String(candidate, "body"),
                teacherV2String(candidate, "trigger"), teacherV2String(candidate, "scope"),
                teacherV2Int(candidate, "priority").toString(), teacherV2String(candidate, "sourceEvidenceKind"),
                teacherV2String(candidate, "sourceEvidenceHash"), "rules",
                teacherV2String(candidate, "assetLineage"), teacherV2String(candidate, "positiveEvidenceHash"),
                teacherV2String(candidate, "negativeEvidenceHash"), teacherV2String(candidate, "boundaryEvidenceHash"),
                teacherV2String(candidate, "generalizationEvidenceHash")]
            let canonical = teacherJoin(fields.map({field: String => "${field.toArray().size}:${field}"}), "")
            let canonicalHash = "sha256:${teacherStableHash(canonical)}"
            if (teacherV2String(candidate, "canonicalHash") != canonicalHash ||
                teacherV2String(operation, "newHash") != canonicalHash) {
                throw IllegalArgumentException("candidate_lane_hash_mismatch")
            }
            let candidateProjection = "# Student Rules\n\n## ${teacherV2String(candidate, "title")}\n\n" +
                "${teacherV2String(candidate, "body")}\n\nTrigger: ${teacherV2String(candidate, "trigger")}\n" +
                "Scope: ${teacherV2String(candidate, "scope")}\n"
            if (teacherV2File(files, "${id}/AGENTS.md") != candidateProjection) {
                throw IllegalArgumentException("candidate_lane_hash_mismatch")
            }
            assetContent = String(candidateProjection.toRuneArray()["# Student Rules\n".toRuneArray().size..])
        } else {
            assetContent = teacherV2File(files, "${id}/SKILL.md")
            let candidateRaw = teacherV2File(files, "${id}/candidate-manifest.json").trimAscii()
            let candidate = JsonValue.fromStr(candidateRaw).asObject()
            let bundle = teacherV2File(files, "${id}/test-bundle.json").trimAscii()
            if (candidate.getFields().size != 15 || teacherV2String(candidate, "schemaVersion") !=
                "cangjie-teacher-skill-candidate-v1" || teacherV2String(candidate, "id") != id ||
                teacherV2String(candidate, "skillPath") != "SKILL.md" ||
                teacherV2String(candidate, "testBundlePath") != "test-bundle.json" ||
                teacherV2String(candidate, "lineage") != lineage ||
                teacherV2String(candidate, "skillContentHash") !=
                    "sha256:${teacherStableHash(teacherV2File(files, "${id}/SKILL.md"))}" ||
                teacherV2String(candidate, "testBundleHash") != "sha256:${teacherStableHash(bundle)}" ||
                !teacherV2Hash(teacherV2String(candidate, "testEvidenceHash")) ||
                teacherV2String(candidate, "candidateContentHash") !=
                    teacherV2String(operation, "newHash")) {
                throw IllegalArgumentException("candidate_lane_hash_mismatch")
            }
            let evidence = "{\"schemaVersion\":\"cangjie-teacher-skill-candidate-v1\"," +
                "\"id\":\"${teacherV2Escape(id)}\",\"version\":\"${teacherV2Escape(teacherV2String(candidate, "version"))}\"," +
                "\"title\":\"${teacherV2Escape(teacherV2String(candidate, "title"))}\"," +
                "\"procedure\":\"${teacherV2Escape(teacherV2String(candidate, "procedure"))}\"," +
                "\"sourceCategory\":\"${teacherV2String(candidate, "sourceCategory")}\"," +
                "\"applicability\":\"${teacherV2Escape(teacherV2String(candidate, "applicability"))}\"," +
                "\"lineage\":\"${teacherV2String(candidate, "lineage")}\",\"skillPath\":\"SKILL.md\"," +
                "\"skillContentHash\":\"${teacherV2String(candidate, "skillContentHash")}\"," +
                "\"testBundlePath\":\"test-bundle.json\",\"testBundleHash\":\"${teacherV2String(candidate, "testBundleHash")}\"," +
                "\"testEvidenceHash\":\"${teacherV2String(candidate, "testEvidenceHash")}\"," +
                "\"candidateContentHash\":\"${teacherV2String(candidate, "candidateContentHash")}\"}"
            let artifactHash = "sha256:${teacherStableHash(evidence)}"
            if (teacherV2String(candidate, "artifactHash") != artifactHash ||
                candidateRaw != String(evidence.toRuneArray()[..evidence.toRuneArray().size - 1]) +
                    ",\"artifactHash\":\"${artifactHash}\"}") {
                throw IllegalArgumentException("candidate_lane_hash_mismatch")
            }
        }
        projectionAssets = applyTeacherContextAssetOperation(projectionAssets,
            TeacherContextAssetOperation(name, id, teacherV2String(operation, "operation"),
                teacherV2String(operation, "expectedOldHash"), teacherV2String(operation, "newHash")),
            assetContent, priority: if (name == "rules") {
                let candidate = JsonValue.fromStr(teacherV2File(files, "${id}/candidate-manifest.json").trimAscii()).asObject()
                teacherV2Int(candidate, "priority")
            } else { 0 })
    }
    visible = teacherContextAssetProjection(name, projectionAssets)
    let hash = "sha256:${teacherStableHash(visible)}"
    if (teacherV2String(manifest, "${name}Hash") != hash ||
        teacherV2Int(manifest, "${name}Count") != projectionAssets.size ||
        teacherV2String(manifest, if (name == "skills") { "skillAssetLineage" } else {
            "rulesAssetLineage" }) != lineage) {
        throw IllegalArgumentException("candidate_lane_hash_mismatch")
    }
    TeacherContextLaneV2(true, hash, teacherContextLaneTreeHashV2(files), projectionAssets.size,
        lineage, visible, files)
}

private func teacherV2DeriveKnowledge(files: Array<TeacherArtifactFile>, manifest: JsonObject,
    baseCompositeHash: String, classificationHash: String,
    base: ?TeacherContextBaseStateV2): TeacherContextLaneV2 {
    let eligible = !files.isEmpty()
    if (eligible != teacherV2Bool(manifest, "knowledgeEligible")) {
        throw IllegalArgumentException("candidate_lane_hash_mismatch")
    }
    if (!eligible) {
        if (baseCompositeHash == "none") { throw IllegalArgumentException("candidate_base_composite_mismatch") }
        let inherited = match (base) {
            case Some(value) => TeacherContextLaneV2(false, value.knowledgeHash,
                teacherContextLaneTreeHashV2([]), 1, value.knowledgeLineage,
                value.knowledgeVisible, [])
            case None => throw IllegalArgumentException("candidate_base_composite_mismatch")
        }
        let declared = teacherV2LaneFromManifest(manifest, "knowledge", files,
            inherited.visibleContent)
        if (declared.hash != inherited.hash || declared.lineage != inherited.lineage ||
            teacherV2String(manifest, "knowledgeTargetVersion") != match (base) {
                case Some(value) => value.knowledgeVersion
                case None => ""
            }) {
            throw IllegalArgumentException("candidate_base_composite_mismatch")
        }
        return inherited
    }
    if (files.size != 1 || files[0].path != "knowledge-candidate-reference.json") {
        throw IllegalArgumentException("candidate_lane_hash_mismatch")
    }
    let reference = parseTeacherFrozenKnowledgeReference(files[0].content.trimAscii())
    let lineage = if (baseCompositeHash == "none") { "independent" } else {
        if (classificationHash.isEmpty()) { throw IllegalArgumentException("candidate_lane_lineage_invalid") }
        "humaneval_164_derived"
    }
    if (reference.assetLineage != lineage || teacherV2String(manifest, "knowledgeCandidateHash") !=
        reference.knowledgeCandidateHash || teacherV2String(manifest, "knowledgeTargetVersion") !=
        reference.knowledgeVersion || teacherV2String(manifest, "knowledgeAssetLineage") != lineage) {
        throw IllegalArgumentException("candidate_lane_hash_mismatch")
    }
    TeacherContextLaneV2(true, reference.knowledgeCandidateHash,
        teacherContextLaneTreeHashV2(files), 1, lineage, files[0].content, files)
}

public func parseTeacherContextCandidateSetDirectoryV2(allowedRoot: String,
    path: String, baseContextRoot!: String = "none"): TeacherContextCandidateSetV2 {
    let root = Path(teacherResolveArtifactInput(allowedRoot, path, directory: true))
    try {
        if (!exists(root) || FileInfo(root).isSymbolicLink() || !FileInfo(root).isDirectory()) {
            throw IllegalArgumentException("candidate_set_schema_invalid")
        }
        let expected = HashSet<String>(["candidate-set-manifest.json", "rules", "skills", "knowledge", "audit"])
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
        let auditFiles = teacherV2ReadLane(root, "audit")
        var rulesVisible = ""; for (file in rulesFiles) { if (file.path.endsWith("/AGENTS.md")) { rulesVisible += file.content } }
        var skillsVisible = ""; for (file in skillsFiles) { if (file.path.endsWith("/SKILL.md")) { skillsVisible += file.content } }
        var knowledgeVisible = ""; for (file in knowledgeFiles) {
            if (file.path == "knowledge-candidate-reference.json") { knowledgeVisible = file.content }
        }
        let baseHash = teacherV2String(object, "baseCompositeHash")
        let base: ?TeacherContextBaseStateV2 = if (baseHash == "none") {
            if (baseContextRoot != "none") { throw IllegalArgumentException("candidate_base_composite_mismatch") }
            None<TeacherContextBaseStateV2>
        } else {
            if (baseContextRoot == "none") { throw IllegalArgumentException("candidate_base_composite_mismatch") }
            let loaded = loadTeacherContextBaseStateV2(allowedRoot, baseContextRoot)
            if (loaded.compositeHash != baseHash) { throw IllegalArgumentException("candidate_base_composite_mismatch") }
            Some<TeacherContextBaseStateV2>(loaded)
        }
        let classificationHash = teacherV2String(object, "classificationManifestHash")
        let rules = teacherV2DeriveLane("rules", rulesFiles, object, baseHash, classificationHash, base)
        let skills = teacherV2DeriveLane("skills", skillsFiles, object, baseHash, classificationHash, base)
        let knowledge = teacherV2DeriveKnowledge(knowledgeFiles, object, baseHash, classificationHash, base)
        let sealed = teacherSealContextCandidateSetV2(teacherV2String(object, "candidateSetId"),
            teacherV2String(object, "baseCompositeHash"), teacherV2String(object, "validationLevel"),
            teacherV2String(object, "sourceEvidenceManifestHash"),
            teacherV2String(object, "classificationManifestHash"),
            teacherV2String(object, "sourceClosureHash"), teacherV2String(object, "protectedClosureHash"),
            rules, skills, knowledge, teacherV2String(object, "knowledgeTargetVersion"), auditFiles)
        teacherV2ValidateAudit(auditFiles, sealed.sourceEvidenceManifestHash,
            sealed.sourceClosureHash, sealed.protectedClosureHash)
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
    allowedRoot: String, outputRoot: String, baseContextRoot!: String = "none"): String {
    let canonicalAllowed = teacherCanonicalArtifactRoot(allowedRoot)
    let output = teacherResolveArtifactInput(allowedRoot, outputRoot, directory: true)
    // Revalidate the preserved caller path through the original lexical gate, then use
    // canonical path pairs for internal stage parsing.
    let canonicalBase = if (baseContextRoot == "none") { "none" } else {
        teacherResolveArtifactInput(allowedRoot, baseContextRoot, directory: true)
    }
    if (!teacherArtifactSafeComponent(value.candidateSetId)) {
        throw IllegalArgumentException("candidate_set_id_invalid")
    }
    let manifest = renderTeacherContextCandidateSetManifestV2(value)
    let target = "${output}/${value.candidateSetId}"
    if (exists(Path(target))) {
        let parsed = parseTeacherContextCandidateSetDirectoryV2(canonicalAllowed, target,
            baseContextRoot: canonicalBase)
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
        Directory.create(Path("${stage}/audit"), recursive: true)
        teacherV2WriteFiles(stage, "rules", value.rules.files)
        teacherV2WriteFiles(stage, "skills", value.skills.files)
        teacherV2WriteFiles(stage, "knowledge", value.knowledge.files)
        teacherV2WriteFiles(stage, "audit", value.auditFiles)
        _ = teacherAtomicWrite("${stage}/candidate-set-manifest.json", manifest + "\n")
        _ = parseTeacherContextCandidateSetDirectoryV2(canonicalAllowed, stage,
            baseContextRoot: canonicalBase)
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

private func teacherRenderContextApprovalV2(candidate: TeacherContextCandidateSetV2,
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

public func approveTeacherContextCandidateSetV2(allowedRoot: String, candidatePath: String,
    sourceRoot: String, protectedRoot: String, baseContextRoot: String,
    decision: String, reviewer: String,
    reason: String, approvedAtUtc: String): String {
    let candidate = parseTeacherContextCandidateSetDirectoryV2(allowedRoot, candidatePath,
        baseContextRoot: baseContextRoot)
    let loadedClosure = loadTeacherContextSourceClosure(allowedRoot, sourceRoot, protectedRoot)
    let closure = if (baseContextRoot == "none") { loadedClosure } else {
        bindTeacherContextSourceClosureToBase(loadedClosure,
            loadTeacherContextBaseStateV2(allowedRoot, baseContextRoot).closureBindings)
    }
    if (closure.manifest.sourceManifestHash != candidate.sourceEvidenceManifestHash ||
        closure.sourceClosureHash != candidate.sourceClosureHash ||
        closure.protectedClosureHash != candidate.protectedClosureHash) {
        throw IllegalArgumentException("candidate_approval_hash_mismatch")
    }
    teacherRenderContextApprovalV2(candidate, decision, reviewer, reason, approvedAtUtc)
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
        let expected = teacherRenderContextApprovalV2(candidate, decision,
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
