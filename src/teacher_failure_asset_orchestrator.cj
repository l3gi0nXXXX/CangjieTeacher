package cangjie_teacher

import std.collection.*
import std.fs.*
import std.sort.*
import stdx.encoding.json.*

public class TeacherContextSourceManifest {
    public let sourceKind: String
    public let sourceHashes: Array<String>
    public let sourceManifestHash: String
    public init(sourceKind: String, sourceHashes: Array<String>, sourceManifestHash: String) {
        this.sourceKind = sourceKind; this.sourceHashes = sourceHashes
        this.sourceManifestHash = sourceManifestHash
    }
}

public class TeacherContextLane {
    public let eligible: Bool
    public let hash: String
    public let count: Int64
    public let lineage: String
    public let content: String
    public init(eligible: Bool, hash: String, count: Int64, lineage: String, content: String) {
        this.eligible = eligible; this.hash = hash; this.count = count
        this.lineage = lineage; this.content = content
    }
}

public class TeacherContextCandidateSet {
    public let candidateSetId: String
    public let baseCompositeHash: String
    public let validationLevel: String
    public let sourceEvidenceManifestHash: String
    public let classificationManifestHash: String
    public let rules: TeacherContextLane
    public let skills: TeacherContextLane
    public let knowledge: TeacherContextLane
    public let knowledgeTargetVersion: String
    public let combinationAuditHash: String
    public let candidateSetHash: String
    public init(candidateSetId: String, baseCompositeHash: String, validationLevel: String,
        sourceEvidenceManifestHash: String, classificationManifestHash: String,
        rules: TeacherContextLane, skills: TeacherContextLane, knowledge: TeacherContextLane,
        knowledgeTargetVersion: String, combinationAuditHash: String, candidateSetHash: String) {
        this.candidateSetId = candidateSetId; this.baseCompositeHash = baseCompositeHash
        this.validationLevel = validationLevel; this.sourceEvidenceManifestHash = sourceEvidenceManifestHash
        this.classificationManifestHash = classificationManifestHash; this.rules = rules
        this.skills = skills; this.knowledge = knowledge; this.knowledgeTargetVersion = knowledgeTargetVersion
        this.combinationAuditHash = combinationAuditHash; this.candidateSetHash = candidateSetHash
    }
}

public class TeacherFailureAssetsBuildResult {
    public let classification: TeacherFailureAssetClassification
    public let proposals: Array<TeacherFailureAssetGenerationResponse>
    public init(classification: TeacherFailureAssetClassification,
        proposals: Array<TeacherFailureAssetGenerationResponse>) {
        this.classification = classification; this.proposals = proposals
    }
}

private func teacherContextHashesCanonical(values: Array<String>): Array<String> {
    let copy = values.clone(); sort(copy); copy
}

public func buildTeacherContextSourceManifest(sourceKind: String,
    sourceHashes: Array<String>): TeacherContextSourceManifest {
    if (!["independent_sources", "completion_failures"].contains(sourceKind) || sourceHashes.isEmpty()) {
        throw IllegalArgumentException("candidate_lane_lineage_invalid")
    }
    let sorted = teacherContextHashesCanonical(sourceHashes)
    let seen = HashSet<String>()
    for (hash in sorted) {
        if (!hash.startsWith("sha256:") || hash.toRuneArray().size != 71 || seen.contains(hash)) {
            throw IllegalArgumentException("candidate_lane_lineage_invalid")
        }
        seen.add(hash)
    }
    let evidence = "{\"schemaVersion\":\"teacher-context-source-manifest-v1\"," +
        "\"sourceKind\":\"${sourceKind}\",\"sourceHashes\":[" +
        teacherJoin(sorted.map({v: String => "\"${v}\""}), ",") + "]}"
    TeacherContextSourceManifest(sourceKind, sorted, "sha256:${teacherStableHash(evidence)}")
}

public func renderTeacherContextSourceManifest(value: TeacherContextSourceManifest): String {
    let evidence = "{\"schemaVersion\":\"teacher-context-source-manifest-v1\"," +
        "\"sourceKind\":\"${value.sourceKind}\",\"sourceHashes\":[" +
        teacherJoin(value.sourceHashes.map({v: String => "\"${v}\""}), ",") + "]}"
    if (value.sourceManifestHash != "sha256:${teacherStableHash(evidence)}") {
        throw IllegalArgumentException("candidate_lane_lineage_invalid")
    }
    let runes = evidence.toRuneArray()
    String(runes[..runes.size - 1]) + ",\"sourceManifestHash\":\"${value.sourceManifestHash}\"}"
}

public func parseTeacherContextSourceManifest(raw: String): TeacherContextSourceManifest {
    try {
        let object = JsonValue.fromStr(raw).asObject()
        if (object.getFields().size != 4) { throw IllegalArgumentException("candidate_lane_lineage_invalid") }
        let schema = match (object.get("schemaVersion")) { case Some(v) => v.asString().getValue(); case None => "" }
        let kind = match (object.get("sourceKind")) { case Some(v) => v.asString().getValue(); case None => "" }
        let hash = match (object.get("sourceManifestHash")) { case Some(v) => v.asString().getValue(); case None => "" }
        let hashes = ArrayList<String>()
        match (object.get("sourceHashes")) {
            case Some(v) => for (item in v.asArray().getItems()) { hashes.add(item.asString().getValue()) }
            case None => ()
        }
        if (schema != "teacher-context-source-manifest-v1") {
            throw IllegalArgumentException("candidate_lane_lineage_invalid")
        }
        let built = buildTeacherContextSourceManifest(kind, hashes.toArray())
        if (built.sourceManifestHash != hash || raw != renderTeacherContextSourceManifest(built)) {
            throw IllegalArgumentException("candidate_lane_lineage_invalid")
        }
        built
    } catch (e: IllegalArgumentException) {
        if (e.message == "candidate_lane_lineage_invalid") { throw e }
        throw IllegalArgumentException("malformed_json")
    } catch (_: Exception) { throw IllegalArgumentException("malformed_json") }
}

private func teacherCandidateSetEvidence(value: TeacherContextCandidateSet): String {
    "{\"schemaVersion\":\"teacher-student-context-candidate-set-v1\"," +
        "\"candidateSetId\":\"${value.candidateSetId}\",\"baseCompositeHash\":\"${value.baseCompositeHash}\"," +
        "\"validationLevel\":\"${value.validationLevel}\",\"sourceEvidenceManifestHash\":\"${value.sourceEvidenceManifestHash}\"," +
        "\"classificationManifestHash\":\"${value.classificationManifestHash}\"," +
        "\"rulesEligible\":${value.rules.eligible},\"rulesHash\":\"${value.rules.hash}\",\"rulesCount\":${value.rules.count}," +
        "\"rulesAssetLineage\":\"${value.rules.lineage}\",\"skillsEligible\":${value.skills.eligible}," +
        "\"skillsHash\":\"${value.skills.hash}\",\"skillsCount\":${value.skills.count}," +
        "\"skillAssetLineage\":\"${value.skills.lineage}\",\"knowledgeEligible\":${value.knowledge.eligible}," +
        "\"knowledgeCandidateHash\":\"${value.knowledge.hash}\",\"knowledgeTargetVersion\":\"${value.knowledgeTargetVersion}\"," +
        "\"knowledgeAssetLineage\":\"${value.knowledge.lineage}\",\"combinationAuditHash\":\"${value.combinationAuditHash}\"}"
}

public func renderTeacherContextCandidateSetManifest(value: TeacherContextCandidateSet): String {
    let evidence = teacherCandidateSetEvidence(value)
    if (value.candidateSetHash != "sha256:${teacherStableHash(evidence)}") {
        throw IllegalArgumentException("candidate_set_hash_mismatch")
    }
    let runes = evidence.toRuneArray()
    String(runes[..runes.size - 1]) + ",\"candidateSetHash\":\"${value.candidateSetHash}\"}"
}

public func auditTeacherAssetCombinationLeakage(rules: String, skills: String, knowledge: String,
    protectedArtifacts: Array<String>): LeakageAuditResult {
    let combined = "${rules}\n${skills}\n${knowledge}"
    let lower = combined.toAsciiLower(); let violations = ArrayList<String>()
    for (marker in ["cj-humaneval-", "hidden_test", "expectedoutput", "reference solution",
        "solution_cj", "ignore protocol", "override protocol", "read test", "run command"]) {
        if (lower.contains(marker)) { violations.add("combined_protected_directive") }
    }
    let protected = auditTextAgainstProtectedArtifacts(combined, protectedArtifacts)
    for (violation in protected.violations) { violations.add("combined_${violation}") }
    LeakageAuditResult(violations.isEmpty(), violations.toArray())
}

private func teacherBuildContextSet(candidateSetId: String, baseCompositeHash: String,
    sourceManifestHash: String, classificationManifestHash: String, rules: TeacherContextLane,
    skills: TeacherContextLane, knowledge: TeacherContextLane, knowledgeTargetVersion: String,
    protectedArtifacts: Array<String>): TeacherContextCandidateSet {
    let audit = auditTeacherAssetCombinationLeakage(rules.content, skills.content, knowledge.content,
        protectedArtifacts)
    if (!audit.passed) { throw IllegalArgumentException("protected_asset_combination") }
    let combinationHash = "sha256:${teacherStableHash(rules.content + "\n" + skills.content + "\n" + knowledge.content)}"
    let provisional = TeacherContextCandidateSet(candidateSetId, baseCompositeHash, "scaffold_contract",
        sourceManifestHash, classificationManifestHash, rules, skills, knowledge,
        knowledgeTargetVersion, combinationHash, "")
    TeacherContextCandidateSet(candidateSetId, baseCompositeHash, "scaffold_contract", sourceManifestHash,
        classificationManifestHash, rules, skills, knowledge, knowledgeTargetVersion, combinationHash,
        "sha256:${teacherStableHash(teacherCandidateSetEvidence(provisional))}")
}

public func buildTeacherIndependentContextSeed(sourceManifest: TeacherContextSourceManifest,
    candidateSetId: String, rulesContent: String, skillsContent: String, knowledgeContent: String,
    knowledgeTargetVersion: String, protectedArtifacts!: Array<String> = [],
    base!: String = "none"): TeacherContextCandidateSet {
    if (sourceManifest.sourceKind != "independent_sources" || base != "none" ||
        rulesContent.isEmpty() || skillsContent.isEmpty() || knowledgeContent.isEmpty()) {
        throw IllegalArgumentException("candidate_lane_lineage_invalid")
    }
    let rules = TeacherContextLane(true, "sha256:${teacherStableHash(rulesContent)}", 1, "independent", rulesContent)
    let skills = TeacherContextLane(true, "sha256:${teacherStableHash(skillsContent)}", 1, "independent", skillsContent)
    let knowledge = TeacherContextLane(true, "sha256:${teacherStableHash(knowledgeContent)}", 1, "independent", knowledgeContent)
    teacherBuildContextSet(candidateSetId, base, sourceManifest.sourceManifestHash, "", rules, skills,
        knowledge, knowledgeTargetVersion, protectedArtifacts)
}

public func buildTeacherFailureAssets(failure: TeacherCompletionFailureInput,
    first: TeacherFailureAssetClassification, second: TeacherFailureAssetClassification,
    gapDescription: String, generator: TeacherFailureAssetGenerator): TeacherFailureAssetsBuildResult {
    let classification = reconcileTeacherFailureAssetClassifications(first, second)
    if (classification.failureEvidenceHash != failure.evidenceHash) {
        throw IllegalArgumentException("failure_classification_binding_mismatch")
    }
    TeacherFailureAssetsBuildResult(classification,
        generateTeacherFailureAssetProposals(classification, gapDescription, generator))
}

public func buildTeacherKnowledgeCandidateFromFailureAsset(classification: TeacherFailureAssetClassification,
    atomBundle: String, workspaceRoot: String, executor!: TeacherCommandExecutor = NativeTeacherCommandExecutor(),
    timeoutMillis!: Int64 = 600000): TeacherAtomExecutionResult {
    if (!classification.knowledgeEligible || classification.schemaVersion != "ckb-completion-failure-classification-v2" ||
        atomBundle.contains("ckb-benchmark-gap-v1")) {
        let rejected = TeacherAtomExecutionResult(); rejected.diagnostic = "failure_knowledge_adapter_invalid"; return rejected
    }
    executeTeacherKnowledgeAtomCandidate(atomBundle, workspaceRoot, executor: executor,
        timeoutMillis: timeoutMillis)
}

public func exportTeacherContextCandidateSet(value: TeacherContextCandidateSet, outputRoot: String): String {
    let manifest = renderTeacherContextCandidateSetManifest(value)
    let target = Path(outputRoot).join(value.candidateSetId)
    if (exists(target)) {
        if (teacherReadUtf8File(target.join("candidate-set-manifest.json").toString()).trimAscii() == manifest) {
            return manifest
        }
        throw IllegalArgumentException("candidate_set_hash_mismatch")
    }
    let stage = Path(outputRoot).join(".${value.candidateSetId}.tmp-${teacherStableHash(manifest)}")
    try {
        if (exists(stage)) { remove(stage, recursive: true) }
        Directory.create(stage.join("rules"), recursive: true)
        Directory.create(stage.join("skills"), recursive: true)
        Directory.create(stage.join("knowledge"), recursive: true)
        _ = teacherAtomicWrite(stage.join("candidate-set-manifest.json").toString(), manifest + "\n")
        _ = teacherAtomicWrite(stage.join("rules/AGENTS.md").toString(), value.rules.content)
        _ = teacherAtomicWrite(stage.join("skills/student-skills.prompt.md").toString(), value.skills.content)
        _ = teacherAtomicWrite(stage.join("knowledge/knowledge-candidate-reference.json").toString(), value.knowledge.content)
        rename(stage, to: target, overwrite: false)
    } catch (e: Exception) {
        try { if (exists(stage)) { remove(stage, recursive: true) } } catch (_: Exception) {}
        throw e
    }
    manifest
}

public func renderTeacherContextApproval(candidate: TeacherContextCandidateSet, decision: String,
    reviewer: String, reason: String, approvedAtUtc: String): String {
    if (!["approve", "reject"].contains(decision) || reviewer.isEmpty() || reason.isEmpty() ||
        approvedAtUtc.isEmpty()) { throw IllegalArgumentException("candidate_approval_rejected") }
    "{\"schemaVersion\":\"teacher-student-context-approval-v1\",\"candidateSetHash\":\"${candidate.candidateSetHash}\"," +
        "\"rulesHash\":\"${candidate.rules.hash}\",\"skillsHash\":\"${candidate.skills.hash}\"," +
        "\"knowledgeCandidateHash\":\"${candidate.knowledge.hash}\",\"decision\":\"${decision}\"," +
        "\"reviewer\":\"${reviewer}\",\"reason\":\"${reason}\",\"approvedAtUtc\":\"${approvedAtUtc}\"}"
}
