package cangjie_teacher

import std.collection.*
import stdx.encoding.json.*

public class TeacherCompletionFailureInput {
    public let runId: String
    public let caseId: String
    public let datasetVersion: String
    public let generationProtocol: String
    public let completionHash: String
    public let baseStatus: String
    public let plusStatus: String
    public let failureKind: String
    public let failureObservation: String
    public let assetLineage: String
    public let evidenceHash: String
    public init(runId: String, caseId: String, datasetVersion: String, generationProtocol: String,
        completionHash: String, baseStatus: String, plusStatus: String, failureKind: String,
        failureObservation: String, assetLineage: String, evidenceHash: String) {
        this.runId = runId; this.caseId = caseId; this.datasetVersion = datasetVersion
        this.generationProtocol = generationProtocol; this.completionHash = completionHash
        this.baseStatus = baseStatus; this.plusStatus = plusStatus; this.failureKind = failureKind
        this.failureObservation = failureObservation; this.assetLineage = assetLineage
        this.evidenceHash = evidenceHash
    }
}

public class TeacherFailureClassification {
    public let failureEvidenceHash: String
    public let gapKind: String
    public let knowledgeEligible: Bool
    public let skillEligible: Bool
    public let classificationEvidenceHash: String
    public init(failureEvidenceHash: String, gapKind: String, knowledgeEligible: Bool,
        skillEligible: Bool, classificationEvidenceHash: String) {
        this.failureEvidenceHash = failureEvidenceHash; this.gapKind = gapKind
        this.knowledgeEligible = knowledgeEligible; this.skillEligible = skillEligible
        this.classificationEvidenceHash = classificationEvidenceHash
    }
}

public class TeacherSkillFixture {
    public let fixtureId: String
    public let task: String
    public let expectedEvidence: String
    public let sourceClass: String
    public init(fixtureId: String, task: String, expectedEvidence: String,
        sourceClass!: String = "non_humaneval") {
        this.fixtureId = fixtureId; this.task = task; this.expectedEvidence = expectedEvidence
        this.sourceClass = sourceClass
    }
}

public class TeacherSkillTestBundle {
    public let fixtures: Array<TeacherSkillFixture>
    public let evidenceHash: String
    public init(fixtures: Array<TeacherSkillFixture>, evidenceHash: String) {
        this.fixtures = fixtures; this.evidenceHash = evidenceHash
    }
}

public class TeacherSkillCandidate {
    public let skillId: String
    public let version: String
    public let title: String
    public let procedure: String
    public let sourceCategory: String
    public let applicability: String
    public let lineage: String
    public let contentHash: String
    public let tests: TeacherSkillTestBundle
    public init(skillId: String, version: String, title: String, procedure: String,
        sourceCategory: String, applicability: String, lineage: String, contentHash: String,
        tests: TeacherSkillTestBundle) {
        this.skillId = skillId; this.version = version; this.title = title
        this.procedure = procedure; this.sourceCategory = sourceCategory
        this.applicability = applicability; this.lineage = lineage
        this.contentHash = contentHash; this.tests = tests
    }
}

private func teacherFailureEscape(value: String): String {
    value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
        .replace("\r", "\\r").replace("\t", "\\t")
}

private func teacherFailureHex(value: String): Bool {
    let runes = value.toRuneArray()
    if (runes.size != 64) { return false }
    for (rune in runes) {
        if (!((rune >= r'0' && rune <= r'9') || (rune >= r'a' && rune <= r'f'))) { return false }
    }
    true
}

private func teacherFailureString(value: JsonObject, key: String): String {
    match (value.get(key)) { case Some(field) => field.asString().getValue(); case None => "" }
}

private func teacherFailureBool(value: JsonObject, key: String): Bool {
    match (value.get(key)) { case Some(field) => field.asBool().getValue(); case None => false }
}

private func teacherFailureObservationSafe(value: String): Bool {
    if (value.isEmpty() || value.toRuneArray().size > 512) { return false }
    let lower = value.toAsciiLower()
    for (marker in ["/users/", "/home/", "/private/", "authorization", "token", "password",
        "secret", "hidden_test", "expectedoutput", "reference solution", "assertion line"]) {
        if (lower.contains(marker)) { return false }
    }
    true
}

private func renderTeacherCompletionFailureEvidence(value: TeacherCompletionFailureInput): String {
    "{\"schemaVersion\":\"ckb-completion-failure-v1\",\"runId\":\"${teacherFailureEscape(value.runId)}\"," +
        "\"caseId\":\"${teacherFailureEscape(value.caseId)}\",\"datasetVersion\":\"${teacherFailureEscape(value.datasetVersion)}\"," +
        "\"generationProtocol\":\"${teacherFailureEscape(value.generationProtocol)}\",\"completionHash\":\"${value.completionHash}\"," +
        "\"baseStatus\":\"${value.baseStatus}\",\"plusStatus\":\"${value.plusStatus}\",\"failureKind\":\"${value.failureKind}\"," +
        "\"failureObservation\":\"${teacherFailureEscape(value.failureObservation)}\",\"assetLineage\":\"${value.assetLineage}\"}"
}

public func renderTeacherCompletionFailureInput(value: TeacherCompletionFailureInput): String {
    let evidence = renderTeacherCompletionFailureEvidence(value)
    if (value.evidenceHash != teacherStableHash(evidence)) {
        throw IllegalArgumentException("completion_failure_evidence_hash_mismatch")
    }
    String(evidence.toRuneArray()[..evidence.toRuneArray().size - 1]) +
        ",\"evidenceHash\":\"${value.evidenceHash}\"}"
}

public func parseTeacherCompletionFailureInput(raw: String): TeacherCompletionFailureInput {
    try {
        let object = JsonValue.fromStr(raw).asObject()
        if (object.getFields().size != 12 || teacherFailureString(object, "schemaVersion") != "ckb-completion-failure-v1") {
            throw IllegalArgumentException("completion_failure_contract_invalid")
        }
        let value = TeacherCompletionFailureInput(teacherFailureString(object, "runId"),
            teacherFailureString(object, "caseId"), teacherFailureString(object, "datasetVersion"),
            teacherFailureString(object, "generationProtocol"), teacherFailureString(object, "completionHash"),
            teacherFailureString(object, "baseStatus"), teacherFailureString(object, "plusStatus"),
            teacherFailureString(object, "failureKind"), teacherFailureString(object, "failureObservation"),
            teacherFailureString(object, "assetLineage"), teacherFailureString(object, "evidenceHash"))
        let statuses = ["passed", "failed", "timeout", "infra_error"]
        let kinds = ["compile_error", "test_failure", "timeout", "infra_error", "protocol_violation"]
        if (value.runId.isEmpty() || !value.caseId.startsWith("CJ-HUMANEVAL-") ||
            value.datasetVersion.isEmpty() || value.generationProtocol != "completion-only-v1" ||
            !teacherFailureHex(value.completionHash) || !statuses.contains(value.baseStatus) ||
            !statuses.contains(value.plusStatus) || !kinds.contains(value.failureKind) ||
            !teacherFailureObservationSafe(value.failureObservation) ||
            !["independent", "humaneval_164_derived"].contains(value.assetLineage) ||
            !teacherFailureHex(value.evidenceHash) || value.evidenceHash != teacherStableHash(renderTeacherCompletionFailureEvidence(value)) ||
            raw != renderTeacherCompletionFailureInput(value)) {
            throw IllegalArgumentException("completion_failure_contract_invalid")
        }
        value
    } catch (e: IllegalArgumentException) {
        if (e.message == "completion_failure_contract_invalid" ||
            e.message == "completion_failure_evidence_hash_mismatch") { throw e }
        throw IllegalArgumentException("malformed_json")
    }
    catch (_: Exception) { throw IllegalArgumentException("malformed_json") }
}

private func renderTeacherFailureClassificationEvidence(value: TeacherFailureClassification): String {
    "{\"schemaVersion\":\"ckb-completion-failure-classification-v1\",\"failureEvidenceHash\":\"${value.failureEvidenceHash}\"," +
        "\"gapKind\":\"${value.gapKind}\",\"knowledgeEligible\":${value.knowledgeEligible},\"skillEligible\":${value.skillEligible}}"
}

public func renderTeacherFailureClassification(value: TeacherFailureClassification): String {
    let evidence = renderTeacherFailureClassificationEvidence(value)
    if (value.classificationEvidenceHash != teacherStableHash(evidence)) {
        throw IllegalArgumentException("failure_classification_evidence_hash_mismatch")
    }
    String(evidence.toRuneArray()[..evidence.toRuneArray().size - 1]) +
        ",\"classificationEvidenceHash\":\"${value.classificationEvidenceHash}\"}"
}

public func parseTeacherFailureClassification(raw: String): TeacherFailureClassification {
    try {
        let object = JsonValue.fromStr(raw).asObject()
        if (object.getFields().size != 6 || teacherFailureString(object, "schemaVersion") != "ckb-completion-failure-classification-v1") {
            throw IllegalArgumentException("failure_classification_contract_invalid")
        }
        let value = TeacherFailureClassification(teacherFailureString(object, "failureEvidenceHash"),
            teacherFailureString(object, "gapKind"), teacherFailureBool(object, "knowledgeEligible"),
            teacherFailureBool(object, "skillEligible"), teacherFailureString(object, "classificationEvidenceHash"))
        let kinds = ["knowledge_gap", "procedure_gap", "mixed_gap", "reasoning_error",
            "translation_defect", "infrastructure_failure"]
        let eligible = (value.gapKind == "knowledge_gap" && value.knowledgeEligible && !value.skillEligible) ||
            (value.gapKind == "procedure_gap" && !value.knowledgeEligible && value.skillEligible) ||
            (value.gapKind == "mixed_gap" && value.knowledgeEligible && value.skillEligible) ||
            (["reasoning_error", "translation_defect", "infrastructure_failure"].contains(value.gapKind) &&
                !value.knowledgeEligible && !value.skillEligible)
        if (!teacherFailureHex(value.failureEvidenceHash) || !kinds.contains(value.gapKind) || !eligible ||
            !teacherFailureHex(value.classificationEvidenceHash) ||
            value.classificationEvidenceHash != teacherStableHash(renderTeacherFailureClassificationEvidence(value)) ||
            raw != renderTeacherFailureClassification(value)) {
            throw IllegalArgumentException("failure_classification_contract_invalid")
        }
        value
    } catch (e: IllegalArgumentException) {
        if (e.message == "failure_classification_contract_invalid" ||
            e.message == "failure_classification_evidence_hash_mismatch") { throw e }
        throw IllegalArgumentException("malformed_json")
    }
    catch (_: Exception) { throw IllegalArgumentException("malformed_json") }
}

public func classifyTeacherOutputKind(input: TeacherCompletionFailureInput,
    classification: TeacherFailureClassification): String {
    if (classification.failureEvidenceHash != input.evidenceHash) {
        throw IllegalArgumentException("failure_classification_binding_mismatch")
    }
    if (classification.knowledgeEligible && classification.skillEligible) { "mixed" }
    else if (classification.knowledgeEligible) { "knowledge" }
    else if (classification.skillEligible) { "skill" }
    else { "none" }
}

private func teacherSkillFixtureCanonical(value: TeacherSkillFixture): String {
    teacherJoin([value.fixtureId, value.task, value.expectedEvidence, value.sourceClass], "\u{1f}")
}

public func buildTeacherSkillTestBundle(fixtures: Array<TeacherSkillFixture>): TeacherSkillTestBundle {
    if (fixtures.size < 3) { throw IllegalArgumentException("skill_generalization_evidence_insufficient") }
    let ids = HashSet<String>()
    for (fixture in fixtures) {
        if (fixture.fixtureId.isEmpty() || fixture.task.isEmpty() || fixture.expectedEvidence.isEmpty() ||
            fixture.sourceClass != "non_humaneval" || ids.contains(fixture.fixtureId)) {
            throw IllegalArgumentException("invalid_skill_generalization_fixture")
        }
        ids.add(fixture.fixtureId)
    }
    let canonical = teacherJoin(fixtures.map({fixture: TeacherSkillFixture =>
        teacherSkillFixtureCanonical(fixture)}), "\n")
    TeacherSkillTestBundle(fixtures, "sha256:${teacherStableHash(canonical)}")
}

public func buildTeacherSkillCandidate(input: TeacherCompletionFailureInput,
    classification: TeacherFailureClassification, skillId: String, version: String, title: String,
    procedure: String, sourceCategory: String, applicability: String,
    tests: TeacherSkillTestBundle, candidateOrigin!: String = "p6_failure_derived"): TeacherSkillCandidate {
    let kind = classifyTeacherOutputKind(input, classification)
    if (kind != "skill" && kind != "mixed") { throw IllegalArgumentException("failure_has_no_skill_output") }
    if (skillId.isEmpty() || version.isEmpty() || title.isEmpty() || procedure.isEmpty() ||
        applicability.isEmpty() || !["official", "community", "general_engineering", "teacher_derived"].contains(sourceCategory) ||
        !["independent_seed", "p6_failure_derived"].contains(candidateOrigin) ||
        tests.fixtures.size < 3 || !tests.evidenceHash.startsWith("sha256:")) {
        throw IllegalArgumentException("invalid_teacher_skill_candidate")
    }
    if (candidateOrigin == "independent_seed" && input.assetLineage != "independent") {
        throw IllegalArgumentException("independent_skill_lineage_invalid")
    }
    let candidateLineage = if (candidateOrigin == "p6_failure_derived") {
        "humaneval_164_derived"
    } else { "independent" }
    let canonical = teacherJoin([skillId, version, title, procedure, sourceCategory, applicability,
        candidateLineage, tests.evidenceHash], "\u{1f}")
    TeacherSkillCandidate(skillId, version, title, procedure, sourceCategory, applicability,
        candidateLineage, "sha256:${teacherStableHash(canonical)}", tests)
}

public func renderCandidateSkillExport(value: TeacherSkillCandidate): String {
    if (!value.contentHash.startsWith("sha256:") || value.tests.fixtures.size < 3) {
        throw IllegalArgumentException("invalid_teacher_skill_candidate")
    }
    let expected = teacherStableHash(teacherJoin([value.skillId, value.version, value.title,
        value.procedure, value.sourceCategory, value.applicability, value.lineage,
        value.tests.evidenceHash], "\u{1f}"))
    if (value.contentHash != "sha256:${expected}") { throw IllegalArgumentException("skill_content_hash_mismatch") }
    "---\nname: ${value.skillId}\nversion: ${value.version}\nsource: ${value.sourceCategory}\n" +
        "lineage: ${value.lineage}\ncontent-hash: ${value.contentHash}\n---\n\n" +
        "# ${value.title}\n\nApplicability: ${value.applicability}\n\n${value.procedure}\n"
}

public func renderTeacherFailureObservationForModel(input: TeacherCompletionFailureInput,
    classification: TeacherFailureClassification): String {
    let kind = classifyTeacherOutputKind(input, classification)
    "generation_protocol=${input.generationProtocol}; failure_type=${kind}; " +
        "base_status=${input.baseStatus}; plus_status=${input.plusStatus}; " +
        "failure_observation=${input.failureObservation}"
}
