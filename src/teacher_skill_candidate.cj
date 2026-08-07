package cangjie_teacher

import std.collection.*
import std.fs.*
import std.sort.*
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

public class TeacherFailureAssetClassification {
    public let schemaVersion: String
    public let failureEvidenceHash: String
    public let gapKind: String
    public let knowledgeEligible: Bool
    public let skillEligible: Bool
    public let rulesEligible: Bool
    public let classificationReasonCode: String
    public let classificationEvidenceHash: String
    public init(schemaVersion: String, failureEvidenceHash: String, gapKind: String,
        knowledgeEligible: Bool, skillEligible: Bool, rulesEligible: Bool,
        classificationReasonCode: String, classificationEvidenceHash: String) {
        this.schemaVersion = schemaVersion; this.failureEvidenceHash = failureEvidenceHash
        this.gapKind = gapKind; this.knowledgeEligible = knowledgeEligible
        this.skillEligible = skillEligible; this.rulesEligible = rulesEligible
        this.classificationReasonCode = classificationReasonCode
        this.classificationEvidenceHash = classificationEvidenceHash
    }
}

public class TeacherSkillFixture {
    public let fixtureId: String
    public let task: String
    public let expectedEvidence: String
    public let sourceClass: String
    public let kind: String
    public let fixturePath: String
    public let targetVersion: String
    public let benchmarkDerived: Bool
    public let passed: Bool
    public init(fixtureId: String, task: String, expectedEvidence: String,
        sourceClass!: String = "non_humaneval_experiment", kind!: String = "generalization",
        fixturePath!: String = "", targetVersion!: String = "1.0.0",
        benchmarkDerived!: Bool = false, passed!: Bool = true) {
        this.fixtureId = fixtureId; this.task = task; this.expectedEvidence = expectedEvidence
        this.sourceClass = sourceClass
        this.kind = kind
        this.fixturePath = if (fixturePath.isEmpty()) { "tests/${fixtureId}.txt" } else { fixturePath }
        this.targetVersion = targetVersion; this.benchmarkDerived = benchmarkDerived; this.passed = passed
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

private func renderTeacherFailureAssetClassificationEvidence(
    value: TeacherFailureAssetClassification): String {
    "{\"schemaVersion\":\"${value.schemaVersion}\",\"failureEvidenceHash\":\"${value.failureEvidenceHash}\"," +
        "\"gapKind\":\"${value.gapKind}\",\"knowledgeEligible\":${value.knowledgeEligible}," +
        "\"skillEligible\":${value.skillEligible},\"rulesEligible\":${value.rulesEligible}," +
        "\"classificationReasonCode\":\"${value.classificationReasonCode}\"}"
}

public func renderTeacherFailureAssetClassification(value: TeacherFailureAssetClassification): String {
    let evidence = renderTeacherFailureAssetClassificationEvidence(value)
    if (value.classificationEvidenceHash != teacherStableHash(evidence)) {
        throw IllegalArgumentException("classification_evidence_hash_mismatch")
    }
    let runes = evidence.toRuneArray()
    String(runes[..runes.size - 1]) +
        ",\"classificationEvidenceHash\":\"${value.classificationEvidenceHash}\"}"
}

private func teacherFailureAssetEligibilityValid(value: TeacherFailureAssetClassification): Bool {
    match (value.gapKind) {
        case "knowledge_gap" => value.knowledgeEligible && !value.skillEligible && !value.rulesEligible
        case "procedure_gap" => !value.knowledgeEligible && value.skillEligible && !value.rulesEligible
        case "rules_gap" => !value.knowledgeEligible && !value.skillEligible && value.rulesEligible
        case "knowledge_procedure_gap" => value.knowledgeEligible && value.skillEligible && !value.rulesEligible
        case "knowledge_rules_gap" => value.knowledgeEligible && !value.skillEligible && value.rulesEligible
        case "procedure_rules_gap" => !value.knowledgeEligible && value.skillEligible && value.rulesEligible
        case "all_assets_gap" => value.knowledgeEligible && value.skillEligible && value.rulesEligible
        case "none" | "reasoning_error" | "translation_defect" | "infrastructure_failure" =>
            !value.knowledgeEligible && !value.skillEligible && !value.rulesEligible
        case _ => false
    }
}

private func teacherFailureAssetReasonValid(value: TeacherFailureAssetClassification): Bool {
    match (value.gapKind) {
        case "knowledge_gap" => value.classificationReasonCode == "missing_versioned_fact"
        case "procedure_gap" => value.classificationReasonCode == "missing_reusable_procedure"
        case "rules_gap" => value.classificationReasonCode == "missing_global_invariant"
        case "knowledge_procedure_gap" | "knowledge_rules_gap" | "procedure_rules_gap" | "all_assets_gap" =>
            value.classificationReasonCode == "multiple_reusable_gaps"
        case "reasoning_error" => value.classificationReasonCode == "reasoning_only"
        case "translation_defect" => value.classificationReasonCode == "translation_defect_only"
        case "infrastructure_failure" => value.classificationReasonCode == "infrastructure_only"
        case "none" => value.classificationReasonCode == "no_reusable_gap"
        case _ => false
    }
}

public func sealTeacherFailureAssetClassification(
    value: TeacherFailureAssetClassification): TeacherFailureAssetClassification {
    if (value.schemaVersion != "ckb-completion-failure-classification-v2" ||
        !teacherFailureHex(value.failureEvidenceHash)) {
        throw IllegalArgumentException("classification_identity_invalid")
    }
    if (!teacherFailureAssetEligibilityValid(value) || !teacherFailureAssetReasonValid(value)) {
        throw IllegalArgumentException("classification_eligibility_invalid")
    }
    let evidence = renderTeacherFailureAssetClassificationEvidence(value)
    let sealed = TeacherFailureAssetClassification(value.schemaVersion, value.failureEvidenceHash,
        value.gapKind, value.knowledgeEligible, value.skillEligible, value.rulesEligible,
        value.classificationReasonCode, teacherStableHash(evidence))
    _ = parseTeacherFailureAssetClassification(renderTeacherFailureAssetClassification(sealed))
    sealed
}

public func parseTeacherFailureAssetClassification(raw: String): TeacherFailureAssetClassification {
    try {
        let object = JsonValue.fromStr(raw).asObject()
        if (object.getFields().size != 8) {
            throw IllegalArgumentException("classification_schema_fields_invalid")
        }
        for (name in ["schemaVersion", "failureEvidenceHash", "gapKind", "classificationReasonCode",
            "classificationEvidenceHash"]) {
            match (object.get(name)) {
                case Some(field) => try { _ = field.asString().getValue() } catch (_: Exception) {
                    throw IllegalArgumentException("classification_schema_fields_invalid")
                }
                case None => throw IllegalArgumentException("classification_schema_fields_invalid")
            }
        }
        for (name in ["knowledgeEligible", "skillEligible", "rulesEligible"]) {
            match (object.get(name)) {
                case Some(field) => try { _ = field.asBool().getValue() } catch (_: Exception) {
                    throw IllegalArgumentException("classification_schema_fields_invalid")
                }
                case None => throw IllegalArgumentException("classification_schema_fields_invalid")
            }
        }
        let value = TeacherFailureAssetClassification(teacherFailureString(object, "schemaVersion"),
            teacherFailureString(object, "failureEvidenceHash"), teacherFailureString(object, "gapKind"),
            teacherFailureBool(object, "knowledgeEligible"), teacherFailureBool(object, "skillEligible"),
            teacherFailureBool(object, "rulesEligible"), teacherFailureString(object, "classificationReasonCode"),
            teacherFailureString(object, "classificationEvidenceHash"))
        if (value.schemaVersion != "ckb-completion-failure-classification-v2" ||
            !teacherFailureHex(value.failureEvidenceHash)) {
            throw IllegalArgumentException("classification_identity_invalid")
        }
        if (!teacherFailureAssetEligibilityValid(value) || !teacherFailureAssetReasonValid(value)) {
            throw IllegalArgumentException("classification_eligibility_invalid")
        }
        if (!teacherFailureHex(value.classificationEvidenceHash) ||
            value.classificationEvidenceHash != teacherStableHash(renderTeacherFailureAssetClassificationEvidence(value))) {
            throw IllegalArgumentException("classification_evidence_hash_mismatch")
        }
        if (raw != renderTeacherFailureAssetClassification(value)) {
            throw IllegalArgumentException("classification_schema_fields_invalid")
        }
        value
    } catch (e: IllegalArgumentException) {
        if (["classification_schema_fields_invalid", "classification_identity_invalid",
            "classification_eligibility_invalid", "classification_evidence_hash_mismatch"].contains(e.message)) { throw e }
        throw IllegalArgumentException("malformed_json")
    } catch (_: Exception) { throw IllegalArgumentException("malformed_json") }
}

public func parseTeacherFailureAssetClassificationBytes(
    bytes: Array<UInt8>): TeacherFailureAssetClassification {
    let raw = try { String.fromUtf8(bytes) } catch (_: Exception) {
        throw IllegalArgumentException("invalid_response_encoding")
    }
    parseTeacherFailureAssetClassification(raw)
}

public func classifyTeacherAssetOutputKind(value: TeacherFailureAssetClassification): String {
    if (value.knowledgeEligible && value.skillEligible && value.rulesEligible) { "all" }
    else if (value.knowledgeEligible && value.skillEligible) { "knowledge_skill" }
    else if (value.knowledgeEligible && value.rulesEligible) { "knowledge_rules" }
    else if (value.skillEligible && value.rulesEligible) { "skill_rules" }
    else if (value.knowledgeEligible) { "knowledge" }
    else if (value.skillEligible) { "skill" }
    else if (value.rulesEligible) { "rules" }
    else { "none" }
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
    teacherJoin([value.fixtureId, value.kind, value.fixturePath, value.task, value.expectedEvidence,
        value.targetVersion, value.sourceClass, value.benchmarkDerived.toString(), value.passed.toString()], "\u{1f}")
}

public func buildTeacherSkillTestBundle(fixtures: Array<TeacherSkillFixture>): TeacherSkillTestBundle {
    if (fixtures.size < 3) { throw IllegalArgumentException("skill_generalization_evidence_insufficient") }
    let ids = HashSet<String>()
    let paths = HashSet<String>()
    for (fixture in fixtures) {
        if (fixture.fixtureId.isEmpty() || fixture.task.isEmpty() || fixture.expectedEvidence.isEmpty() ||
            !["official", "community", "non_humaneval_experiment"].contains(fixture.sourceClass) ||
            !["positive", "negative", "boundary", "generalization"].contains(fixture.kind) ||
            !teacherSkillFixturePathSafe(fixture.fixturePath) || fixture.targetVersion.isEmpty() ||
            fixture.benchmarkDerived || !fixture.passed || ids.contains(fixture.fixtureId) ||
            paths.contains(fixture.fixturePath)) {
            throw IllegalArgumentException("invalid_skill_generalization_fixture")
        }
        ids.add(fixture.fixtureId)
        paths.add(fixture.fixturePath)
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
    let provisional = TeacherSkillCandidate(skillId, version, title, procedure, sourceCategory,
        applicability, candidateLineage, "", tests)
    let artifactEvidenceHash = "sha256:${teacherStableHash(renderTeacherSkillTestEvidence(provisional))}"
    let boundTests = TeacherSkillTestBundle(tests.fixtures, artifactEvidenceHash)
    let canonical = teacherJoin([skillId, version, title, procedure, sourceCategory, applicability,
        candidateLineage, artifactEvidenceHash].map({field: String => teacherSkillLengthPart(field)}), "")
    TeacherSkillCandidate(skillId, version, title, procedure, sourceCategory, applicability,
        candidateLineage, "sha256:${teacherStableHash(canonical)}", boundTests)
}

public func renderCandidateSkillExport(value: TeacherSkillCandidate): String {
    if (!value.contentHash.startsWith("sha256:") || value.tests.fixtures.size < 3) {
        throw IllegalArgumentException("invalid_teacher_skill_candidate")
    }
    let expected = teacherStableHash(teacherJoin([value.skillId, value.version, value.title,
        value.procedure, value.sourceCategory, value.applicability, value.lineage,
        value.tests.evidenceHash].map({field: String => teacherSkillLengthPart(field)}), ""))
    if (value.contentHash != "sha256:${expected}") { throw IllegalArgumentException("skill_content_hash_mismatch") }
    "---\nname: ${value.skillId}\nversion: ${value.version}\nsource: ${value.sourceCategory}\n" +
        "lineage: ${value.lineage}\ncontent-hash: ${value.contentHash}\n---\n\n" +
        "# ${value.title}\n\nApplicability: ${value.applicability}\n\n${value.procedure}\n"
}

private func teacherSkillLengthPart(value: String): String { "${value.toArray().size}:${value}" }

private func teacherSkillFixturePathSafe(value: String): Bool {
    if (!value.startsWith("tests/") || value.startsWith("/") || value.contains("\\") ||
        value.endsWith("/") || value.toRuneArray().size > 256) { return false }
    for (part in value.split("/")) { if (part.isEmpty() || part == "." || part == "..") { return false } }
    true
}

private func teacherSkillNormalizedText(value: String): String {
    value.replace("\r\n", "\n").replace("\r", "\n")
}

private func teacherSkillFixtureBytes(value: TeacherSkillFixture): String {
    "{\"schemaVersion\":\"cangjie-teacher-skill-fixture-v1\",\"task\":\"${teacherFailureEscape(teacherSkillNormalizedText(value.task))}\"," +
        "\"resultEvidence\":\"${teacherFailureEscape(value.expectedEvidence)}\"}\n"
}

private func teacherSkillFixtureResultSafe(value: String): Bool {
    if (value.isEmpty() || value.toRuneArray().size > 512) { return false }
    let lower = value.toAsciiLower()
    for (marker in ["/users/", "/home/", "/private/", "authorization", "token", "password", "secret",
        "hidden_test", "reference solution"]) { if (lower.contains(marker)) { return false } }
    true
}

private func teacherSkillSortedFixtures(value: TeacherSkillCandidate): Array<TeacherSkillFixture> {
    let paths = value.tests.fixtures.map({fixture: TeacherSkillFixture => fixture.fixturePath})
    sort(paths)
    let out = ArrayList<TeacherSkillFixture>()
    for (path in paths) {
        for (fixture in value.tests.fixtures) { if (fixture.fixturePath == path) { out.add(fixture); break } }
    }
    out.toArray()
}

private func teacherSkillTestRow(value: TeacherSkillFixture): String {
    if (!teacherSkillFixtureResultSafe(value.expectedEvidence)) {
        throw IllegalArgumentException("skill_test_result_not_exportable")
    }
    let fixtureHash = "sha256:${teacherStableHash(teacherSkillFixtureBytes(value))}"
    let resultHash = "sha256:${teacherStableHash(value.expectedEvidence)}"
    "{\"testId\":\"${teacherFailureEscape(value.fixtureId)}\",\"kind\":\"${value.kind}\"," +
        "\"fixturePath\":\"${teacherFailureEscape(value.fixturePath)}\",\"fixtureHash\":\"${fixtureHash}\"," +
        "\"targetVersion\":\"${teacherFailureEscape(value.targetVersion)}\",\"sourceClass\":\"${value.sourceClass}\"," +
        "\"benchmarkDerived\":false,\"passed\":true,\"resultHash\":\"${resultHash}\"}"
}

private func teacherSkillTestsTreeHash(value: TeacherSkillCandidate): String {
    let parts = ArrayList<String>()
    for (fixture in teacherSkillSortedFixtures(value)) {
        let fileHash = "sha256:${teacherStableHash(teacherSkillFixtureBytes(fixture))}"
        parts.add(teacherSkillLengthPart(fixture.fixturePath) + teacherSkillLengthPart(fileHash))
    }
    "sha256:${teacherStableHash(teacherJoin(parts.toArray(), ""))}"
}

public func renderTeacherSkillTestEvidence(value: TeacherSkillCandidate): String {
    let fixtures = teacherSkillSortedFixtures(value)
    var positive: Int64 = 0; var negative: Int64 = 0; var boundary: Int64 = 0; var generalization: Int64 = 0
    let rows = ArrayList<String>()
    let ids = HashSet<String>()
    for (fixture in fixtures) {
        if (ids.contains(fixture.fixtureId)) { throw IllegalArgumentException("duplicate_skill_test_id") }
        ids.add(fixture.fixtureId); rows.add(teacherSkillTestRow(fixture))
        if (fixture.kind == "positive") { positive += 1 } else if (fixture.kind == "negative") { negative += 1 }
        else if (fixture.kind == "boundary") { boundary += 1 } else if (fixture.kind == "generalization") { generalization += 1 }
    }
    if (positive < 1 || negative < 1 || boundary < 1 || generalization < 3) {
        throw IllegalArgumentException("skill_test_category_count_invalid")
    }
    let rowsText = teacherJoin(rows.toArray(), ",")
    "{\"schemaVersion\":\"cangjie-teacher-skill-test-bundle-v1\",\"candidateId\":\"${teacherFailureEscape(value.skillId)}\"," +
        "\"candidateVersion\":\"${teacherFailureEscape(value.version)}\",\"lineage\":\"${value.lineage}\",\"testsRoot\":\"tests\"," +
        "\"testsTreeHash\":\"${teacherSkillTestsTreeHash(value)}\",\"positiveCount\":${positive},\"negativeCount\":${negative}," +
        "\"boundaryCount\":${boundary},\"generalizationCount\":${generalization},\"tests\":[${rowsText}]}"
}

public func renderTeacherSkillTestBundle(value: TeacherSkillCandidate): String {
    let evidence = renderTeacherSkillTestEvidence(value)
    let hash = "sha256:${teacherStableHash(evidence)}"
    String(evidence.toRuneArray()[..evidence.toRuneArray().size - 1]) + ",\"evidenceHash\":\"${hash}\"}"
}

private func renderTeacherSkillCandidateEvidence(value: TeacherSkillCandidate): String {
    let skill = teacherSkillNormalizedText(renderCandidateSkillExport(value))
    let bundle = renderTeacherSkillTestBundle(value)
    let testEvidenceHash = "sha256:${teacherStableHash(renderTeacherSkillTestEvidence(value))}"
    "{\"schemaVersion\":\"cangjie-teacher-skill-candidate-v1\",\"id\":\"${teacherFailureEscape(value.skillId)}\"," +
        "\"version\":\"${teacherFailureEscape(value.version)}\",\"title\":\"${teacherFailureEscape(value.title)}\"," +
        "\"procedure\":\"${teacherFailureEscape(value.procedure)}\",\"sourceCategory\":\"${value.sourceCategory}\"," +
        "\"applicability\":\"${teacherFailureEscape(value.applicability)}\",\"lineage\":\"${value.lineage}\"," +
        "\"skillPath\":\"SKILL.md\",\"skillContentHash\":\"sha256:${teacherStableHash(skill)}\"," +
        "\"testBundlePath\":\"test-bundle.json\",\"testBundleHash\":\"sha256:${teacherStableHash(bundle)}\"," +
        "\"testEvidenceHash\":\"${testEvidenceHash}\",\"candidateContentHash\":\"${value.contentHash}\"}"
}

public func renderTeacherSkillCandidateManifest(value: TeacherSkillCandidate): String {
    if (!((value.sourceCategory == "general_engineering" && value.lineage == "independent") ||
        (value.sourceCategory == "teacher_derived" && value.lineage == "humaneval_164_derived"))) {
        throw IllegalArgumentException("skill_source_lineage_invalid")
    }
    if (!teacherSkillCandidateExportSafe(value)) { throw IllegalArgumentException("skill_candidate_not_exportable") }
    let evidence = renderTeacherSkillCandidateEvidence(value)
    let artifactHash = "sha256:${teacherStableHash(evidence)}"
    String(evidence.toRuneArray()[..evidence.toRuneArray().size - 1]) + ",\"artifactHash\":\"${artifactHash}\"}"
}

private func teacherSkillCandidateExportSafe(value: TeacherSkillCandidate): Bool {
    var body = teacherJoin([value.skillId, value.version, value.title, value.procedure,
        value.sourceCategory, value.applicability, value.lineage], "\n")
    for (fixture in value.tests.fixtures) {
        body += "\n${fixture.fixtureId}\n${fixture.fixturePath}\n${fixture.task}\n${fixture.expectedEvidence}"
    }
    let lower = body.toAsciiLower()
    for (marker in ["cj-humaneval-", "hidden_test", "expectedoutput", "reference solution",
        "/users/", "/home/", "/private/", "authorization", "token=", "password", "secret"] ) {
        if (lower.contains(marker)) { return false }
    }
    true
}

private func teacherSkillCandidateDirectoryValid(path: String, value: TeacherSkillCandidate): Bool {
    let root = Path(path)
    if (!exists(root) || FileInfo(root).isSymbolicLink() || !FileInfo(root).isDirectory()) { return false }
    let expected = HashSet<String>(["SKILL.md", "candidate-manifest.json", "test-bundle.json", "tests"])
    for (entry in Directory.readFrom(root)) {
        if (!expected.contains(entry.name) || entry.isSymbolicLink()) { return false }
        expected.remove(entry.name)
    }
    if (!expected.isEmpty()) { return false }
    let expectedFixtures = HashSet<String>()
    for (fixture in value.tests.fixtures) { expectedFixtures.add(fixture.fixturePath) }
    let actualFixtures = ArrayList<String>()
    if (!teacherSkillCollectRegularFiles(root.join("tests"), "tests", actualFixtures)) { return false }
    for (fixturePath in actualFixtures) {
        if (!expectedFixtures.contains(fixturePath)) { return false }
        expectedFixtures.remove(fixturePath)
    }
    expectedFixtures.isEmpty()
}

private func teacherSkillCollectRegularFiles(current: Path, relative: String,
    files: ArrayList<String>): Bool {
    if (!exists(current) || FileInfo(current).isSymbolicLink() || !FileInfo(current).isDirectory()) { return false }
    for (entry in Directory.readFrom(current)) {
        if (entry.isSymbolicLink()) { return false }
        let child = "${relative}/${entry.name}"
        if (entry.isDirectory()) {
            if (!teacherSkillCollectRegularFiles(entry.path, child, files)) { return false }
        } else if (entry.isRegular()) { files.add(child) } else { return false }
    }
    true
}

public func exportTeacherSkillCandidateDirectory(value: TeacherSkillCandidate, candidateRoot: String): String {
    if (!candidateRoot.startsWith("/") || value.skillId.isEmpty() || value.skillId.contains("/") ||
        value.skillId.contains("..") || value.skillId.contains("\\")) {
        throw IllegalArgumentException("skill_candidate_path_invalid")
    }
    let root = Path(candidateRoot)
    if (exists(root) && (FileInfo(root).isSymbolicLink() || !FileInfo(root).isDirectory())) {
        throw IllegalArgumentException("skill_candidate_root_invalid")
    }
    if (!exists(root)) { Directory.create(root, recursive: true) }
    let target = root.join(value.skillId).toString()
    let stage = root.join(".${value.skillId}.tmp-${value.contentHash.replace("sha256:", "")}").toString()
    try {
        if (exists(Path(stage))) { remove(Path(stage), recursive: true) }
        Directory.create(Path("${stage}/tests"), recursive: true)
        _ = teacherAtomicWrite("${stage}/SKILL.md", teacherSkillNormalizedText(renderCandidateSkillExport(value)))
        _ = teacherAtomicWrite("${stage}/test-bundle.json", renderTeacherSkillTestBundle(value) + "\n")
        _ = teacherAtomicWrite("${stage}/candidate-manifest.json", renderTeacherSkillCandidateManifest(value) + "\n")
        for (fixture in value.tests.fixtures) {
            _ = teacherAtomicWrite("${stage}/${fixture.fixturePath}", teacherSkillFixtureBytes(fixture))
        }
        if (!teacherSkillCandidateDirectoryValid(stage, value)) { throw IllegalArgumentException("skill_candidate_directory_invalid") }
        if (exists(Path(target))) {
            if (!teacherSkillCandidateDirectoryValid(target, value) || teacherDirectoryHash(target) != teacherDirectoryHash(stage)) {
                throw IllegalArgumentException("skill_candidate_immutable_conflict")
            }
            remove(Path(stage), recursive: true)
        } else { rename(Path(stage), to: Path(target), overwrite: false) }
        renderTeacherSkillCandidateManifest(value)
    } catch (e: Exception) {
        try { if (exists(Path(stage))) { remove(Path(stage), recursive: true) } } catch (_: Exception) {}
        throw e
    }
}

public func renderTeacherFailureObservationForModel(input: TeacherCompletionFailureInput,
    classification: TeacherFailureClassification): String {
    let kind = classifyTeacherOutputKind(input, classification)
    "generation_protocol=${input.generationProtocol}; failure_type=${kind}; " +
        "base_status=${input.baseStatus}; plus_status=${input.plusStatus}; " +
        "failure_observation=${input.failureObservation}"
}
