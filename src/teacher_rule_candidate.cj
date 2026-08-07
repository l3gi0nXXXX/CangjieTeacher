package cangjie_teacher

import std.collection.*
import std.fs.*
import std.sort.*

public class TeacherRuleTestBundle {
    public let executions: Array<TeacherAssetFixtureExecution>
    public init(executions: Array<TeacherAssetFixtureExecution>) { this.executions = executions }
}

public class TeacherRuleCandidate {
    public let ruleId: String
    public let conceptId: String
    public let title: String
    public let body: String
    public let trigger: String
    public let scope: String
    public let priority: Int64
    public let sourceEvidenceKind: String
    public let sourceEvidenceHash: String
    public let assetLineage: String
    public let tests: TeacherRuleTestBundle
    public let canonicalHash: String
    public init(ruleId: String, conceptId: String, title: String, body: String, trigger: String,
        scope: String, priority: Int64, sourceEvidenceKind: String, sourceEvidenceHash: String,
        assetLineage: String, tests: TeacherRuleTestBundle, canonicalHash: String) {
        this.ruleId = ruleId; this.conceptId = conceptId; this.title = title; this.body = body
        this.trigger = trigger; this.scope = scope; this.priority = priority
        this.sourceEvidenceKind = sourceEvidenceKind; this.sourceEvidenceHash = sourceEvidenceHash
        this.assetLineage = assetLineage; this.tests = tests; this.canonicalHash = canonicalHash
    }
}

private func teacherRuleSafeId(value: String): Bool {
    if (value.isEmpty() || value.toRuneArray().size > 96) { return false }
    for (rune in value.toRuneArray()) {
        if (!((rune >= r'a' && rune <= r'z') || (rune >= r'0' && rune <= r'9') || rune == r'-')) { return false }
    }
    true
}

private func teacherRuleVisibleSafe(value: String): Bool {
    if (value.isEmpty() || value.toArray().size > 4096) { return false }
    let lower = value.toAsciiLower()
    for (marker in ["cj-humaneval-", "caseid", "题号", "本题", "hidden_test", "expectedoutput",
        "solution_cj", "reference solution", "/users/", "/home/", "/private/", "authorization",
        "token=", "password=", "ignore protocol", "override protocol", "run command", "read test"]) {
        if (lower.contains(marker)) { return false }
    }
    true
}

private func teacherRuleEvidenceHash(tests: TeacherRuleTestBundle, kind: String): String {
    for (execution in tests.executions) {
        if (execution.fixture.kind == kind && execution.passed) { return execution.transcriptHash }
    }
    ""
}

private func teacherRuleCanonical(value: TeacherRuleCandidate): String {
    teacherJoin([value.ruleId, value.conceptId, value.title, value.body, value.trigger, value.scope,
        value.priority.toString(), value.sourceEvidenceKind, value.sourceEvidenceHash, "rules",
        value.assetLineage, teacherRuleEvidenceHash(value.tests, "positive"),
        teacherRuleEvidenceHash(value.tests, "negative"), teacherRuleEvidenceHash(value.tests, "boundary"),
        teacherRuleEvidenceHash(value.tests, "generalization")].map({v: String => "${v.toArray().size}:${v}"}), "")
}

public func buildTeacherRuleCandidate(classification: TeacherFailureAssetClassification, ruleId: String,
    conceptId: String, title: String, body: String, trigger: String, scope: String, priority: Int64,
    sourceEvidenceKind: String, sourceEvidenceHash: String, tests: TeacherRuleTestBundle): TeacherRuleCandidate {
    let sourceBinding = sourceEvidenceHash == classification.failureEvidenceHash ||
        sourceEvidenceHash == "sha256:${classification.failureEvidenceHash}"
    if (!classification.rulesEligible || !sourceBinding ||
        !teacherRuleSafeId(ruleId) || !teacherRuleSafeId(conceptId) ||
        !teacherRuleVisibleSafe(title) || !teacherRuleVisibleSafe(body) ||
        !teacherRuleVisibleSafe(trigger) || !teacherRuleVisibleSafe(scope) || priority < 0 || priority > 1000 ||
        !["independent_manifest", "completion_failure"].contains(sourceEvidenceKind) ||
        tests.executions.size < 4 || teacherRuleEvidenceHash(tests, "positive").isEmpty() ||
        teacherRuleEvidenceHash(tests, "negative").isEmpty() ||
        teacherRuleEvidenceHash(tests, "boundary").isEmpty() ||
        teacherRuleEvidenceHash(tests, "generalization").isEmpty()) {
        throw IllegalArgumentException("candidate_test_evidence_invalid")
    }
    let lineage = if (sourceEvidenceKind == "completion_failure") { "humaneval_164_derived" } else { "independent" }
    let provisional = TeacherRuleCandidate(ruleId, conceptId, title, body, trigger, scope, priority,
        sourceEvidenceKind, sourceEvidenceHash, lineage, tests, "")
    TeacherRuleCandidate(ruleId, conceptId, title, body, trigger, scope, priority,
        sourceEvidenceKind, sourceEvidenceHash, lineage, tests,
        "sha256:${teacherStableHash(teacherRuleCanonical(provisional))}")
}

public func buildTeacherIndependentRuleCandidate(ruleId: String, conceptId: String, title: String,
    body: String, trigger: String, scope: String, priority: Int64, sourceManifestHash: String,
    tests: TeacherRuleTestBundle): TeacherRuleCandidate {
    let hash = if (sourceManifestHash.startsWith("sha256:")) {
        String(sourceManifestHash.toRuneArray()[7..])
    } else { sourceManifestHash }
    let classification = sealTeacherFailureAssetClassification(TeacherFailureAssetClassification(
        "ckb-completion-failure-classification-v2", hash, "rules_gap", false, false, true,
        "missing_global_invariant", ""))
    let derived = buildTeacherRuleCandidate(classification, ruleId, conceptId, title, body, trigger,
        scope, priority, "independent_manifest", sourceManifestHash, tests)
    TeacherRuleCandidate(derived.ruleId, derived.conceptId, derived.title, derived.body, derived.trigger,
        derived.scope, derived.priority, derived.sourceEvidenceKind, derived.sourceEvidenceHash,
        "independent", derived.tests, derived.canonicalHash)
}

private func teacherRuleSorted(values: Array<TeacherRuleCandidate>): Array<TeacherRuleCandidate> {
    let out = ArrayList<TeacherRuleCandidate>()
    var priority: Int64 = 1000
    while (priority >= 0) {
        let ids = ArrayList<String>()
        for (value in values) { if (value.priority == priority) { ids.add(value.ruleId) } }
        let sortedIds = ids.toArray(); sort(sortedIds)
        for (id in sortedIds) { for (value in values) {
            if (value.ruleId == id) { out.add(value); break }
        } }
        priority -= 1
    }
    out.toArray()
}

public func renderTeacherAgentsMarkdown(values: Array<TeacherRuleCandidate>): String {
    if (values.isEmpty() || values.size > 16) { throw IllegalArgumentException("candidate_generation_invalid") }
    let identities = HashMap<String, String>(); let bodies = HashSet<String>(); var out = "# Student Rules\n"
    for (value in teacherRuleSorted(values)) {
        let identity = "${value.conceptId}|${value.sourceEvidenceKind}|${value.sourceEvidenceHash}"
        match (identities.get(identity)) {
            case Some(hash) => if (hash != value.canonicalHash) {
                throw IllegalArgumentException("rule_conflict_requires_review")
            }
            case None =>
                if (bodies.contains(value.body)) { throw IllegalArgumentException("candidate_generation_invalid") }
                identities.add(identity, value.canonicalHash); bodies.add(value.body)
                out += "\n## ${value.title}\n\n${value.body}\n\nTrigger: ${value.trigger}\nScope: ${value.scope}\n"
        }
    }
    if (out.toArray().size > 8192) { throw IllegalArgumentException("candidate_generation_invalid") }
    out
}

private func teacherRuleJsonEscape(value: String): String {
    value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
}

public func renderTeacherRuleCandidateManifest(value: TeacherRuleCandidate): String {
    if (value.canonicalHash != "sha256:${teacherStableHash(teacherRuleCanonical(value))}") {
        throw IllegalArgumentException("candidate_lane_hash_mismatch")
    }
    "{\"schemaVersion\":\"teacher-rule-candidate-v1\",\"ruleId\":\"${value.ruleId}\"," +
        "\"conceptId\":\"${value.conceptId}\",\"title\":\"${teacherRuleJsonEscape(value.title)}\"," +
        "\"body\":\"${teacherRuleJsonEscape(value.body)}\",\"trigger\":\"${teacherRuleJsonEscape(value.trigger)}\"," +
        "\"scope\":\"${teacherRuleJsonEscape(value.scope)}\",\"priority\":${value.priority}," +
        "\"sourceEvidenceKind\":\"${value.sourceEvidenceKind}\",\"sourceEvidenceHash\":\"${value.sourceEvidenceHash}\"," +
        "\"assetRole\":\"rules\",\"assetLineage\":\"${value.assetLineage}\"," +
        "\"positiveEvidenceHash\":\"${teacherRuleEvidenceHash(value.tests, "positive")}\"," +
        "\"negativeEvidenceHash\":\"${teacherRuleEvidenceHash(value.tests, "negative")}\"," +
        "\"boundaryEvidenceHash\":\"${teacherRuleEvidenceHash(value.tests, "boundary")}\"," +
        "\"generalizationEvidenceHash\":\"${teacherRuleEvidenceHash(value.tests, "generalization")}\"," +
        "\"canonicalHash\":\"${value.canonicalHash}\"}"
}

public func exportTeacherRuleCandidateDirectory(value: TeacherRuleCandidate, outputRoot: String): String {
    let target = Path(outputRoot).join(value.ruleId); let manifest = renderTeacherRuleCandidateManifest(value)
    if (exists(target)) {
        if (teacherReadUtf8File(target.join("candidate-manifest.json").toString()).trimAscii() == manifest) { return manifest }
        throw IllegalArgumentException("candidate_lane_hash_mismatch")
    }
    let stage = Path(outputRoot).join(".${value.ruleId}.tmp-${teacherStableHash(manifest)}")
    try {
        if (exists(stage)) { remove(stage, recursive: true) }
        Directory.create(stage.join("tests"), recursive: true)
        _ = teacherAtomicWrite(stage.join("AGENTS.md").toString(), renderTeacherAgentsMarkdown([value]))
        _ = teacherAtomicWrite(stage.join("candidate-manifest.json").toString(), manifest + "\n")
        for (execution in value.tests.executions) {
            _ = teacherAtomicWrite(stage.join("tests/${execution.fixture.fixtureId}.json").toString(),
                renderTeacherAssetFixtureExecution(execution) + "\n")
        }
        rename(stage, to: target, overwrite: false)
    } catch (e: Exception) {
        try { if (exists(stage)) { remove(stage, recursive: true) } } catch (_: Exception) {}
        throw e
    }
    manifest
}

public func teacherRuleCandidateArtifactFiles(value: TeacherRuleCandidate,
    operation: TeacherContextAssetOperation): Array<TeacherArtifactFile> {
    if (operation.assetRole != "rules" || operation.assetId != value.ruleId ||
        operation.newHash != value.canonicalHash) {
        throw IllegalArgumentException("candidate_operation_invalid")
    }
    let files = ArrayList<TeacherArtifactFile>()
    files.add(TeacherArtifactFile("${value.ruleId}/AGENTS.md", renderTeacherAgentsMarkdown([value])))
    files.add(TeacherArtifactFile("${value.ruleId}/candidate-manifest.json",
        renderTeacherRuleCandidateManifest(value) + "\n"))
    files.add(TeacherArtifactFile("${value.ruleId}/operation.json",
        renderTeacherContextAssetOperation(operation) + "\n"))
    for (execution in value.tests.executions) {
        for (file in teacherAssetFixtureExecutionFiles(execution,
            "${value.ruleId}/tests/${execution.fixture.fixtureId}")) { files.add(file) }
    }
    files.toArray()
}
