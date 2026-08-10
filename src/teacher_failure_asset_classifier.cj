package cangjie_teacher

import std.fs.*
import stdx.encoding.json.*

public class TeacherFailureAssetClassifierRequest {
    public let failureEvidenceHash: String
    public let observation: String
    public let publicSummary: String
    public let authority: String
    public init(failureEvidenceHash: String, observation: String, publicSummary: String, authority: String) {
        this.failureEvidenceHash = failureEvidenceHash; this.observation = observation
        this.publicSummary = publicSummary; this.authority = authority
    }
}

public interface TeacherFailureAssetClassifier {
    func classify(request: TeacherFailureAssetClassifierRequest): String
}

private func teacherFailureAdapterExecutable(value: String, expectedHash: String): Bool {
    let path = Path(value)
    if (!path.isAbsolute() || !exists(path) || !expectedHash.startsWith("sha256:")) { return false }
    try {
        !FileInfo(path).isSymbolicLink() && FileInfo(path).isRegular() &&
            canonicalize(path).toString() == value &&
            teacherValidationExecutableHash(value) == expectedHash
    } catch (_: Exception) { false }
}

// The process is a frozen classifier adapter. It receives only the canonical sanitized
// request file and must write one strict classifier response to the supplied output path.
public class StrictProcessTeacherFailureAssetClassifier <: TeacherFailureAssetClassifier {
    private let executable: String
    private let executableHash: String
    private let workspaceRoot: String
    private let executor: TeacherCommandExecutor
    private let timeoutMillis: Int64
    public init(executable: String, executableHash: String, allowedRoot: String,
        workspaceRoot: String, executor!: TeacherCommandExecutor = NativeTeacherCommandExecutor(),
        timeoutMillis!: Int64 = 600000) {
        if (!teacherFailureAdapterExecutable(executable, executableHash) || timeoutMillis < 1 ||
            timeoutMillis > 3600000) {
            throw IllegalArgumentException("classification_requires_review")
        }
        this.executable = executable; this.executableHash = executableHash
        this.workspaceRoot = teacherResolveArtifactInput(allowedRoot, workspaceRoot, directory: true)
        this.executor = executor; this.timeoutMillis = timeoutMillis
    }
    public func classify(request: TeacherFailureAssetClassifierRequest): String {
        let canonicalRequest = renderTeacherFailureAssetClassifierRequest(request)
        let requestHash = teacherStableHash(canonicalRequest)
        let runRoot = Path(workspaceRoot).join("classification-${requestHash}")
        if (exists(runRoot)) { throw IllegalArgumentException("classification_requires_review") }
        Directory.create(runRoot, recursive: true)
        let requestPath = runRoot.join("request.json").toString()
        let outputPath = runRoot.join("response.json").toString()
        _ = teacherAtomicWrite(requestPath, canonicalRequest + "\n")
        let result = executor.execute(TeacherCommandSpec(executable,
            ["--request", requestPath, "--output", outputPath], runRoot.toString(),
            env: [("CANGJIE_TEACHER_ADAPTER_EXECUTABLE_HASH", executableHash)],
            timeoutMillis: timeoutMillis))
        if (result.timedOut || result.exitCode != 0 || !exists(Path(outputPath))) {
            throw IllegalArgumentException("classification_requires_review")
        }
        let raw = teacherReadUtf8File(outputPath).trimAscii()
        if (raw.toArray().size > 32768) { throw IllegalArgumentException("classification_requires_review") }
        let parsed = parseTeacherFailureAssetClassifierResponse(raw)
        if (parsed.failureEvidenceHash != request.failureEvidenceHash ||
            raw != renderTeacherFailureAssetClassifierResponse(parsed)) {
            throw IllegalArgumentException("classification_requires_review")
        }
        raw
    }
}

private func teacherClassifierEscape(value: String): String {
    value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
        .replace("\r", "\\r").replace("\t", "\\t")
}

private func teacherClassifierSafe(value: String, limit: Int64): Bool {
    if (value.isEmpty() || value.toArray().size > limit) { return false }
    let lower = value.toAsciiLower()
    for (marker in ["cj-humaneval-", "/users/", "/home/", "/private/", "authorization",
        "token=", "password", "hidden_test", "reference solution", "expectedoutput"]) {
        if (lower.contains(marker)) { return false }
    }
    true
}

public func renderTeacherFailureAssetClassifierRequest(value: TeacherFailureAssetClassifierRequest): String {
    if (value.failureEvidenceHash.toRuneArray().size != 64 ||
        !teacherClassifierSafe(value.observation, 4096) ||
        !teacherClassifierSafe(value.publicSummary, 4096) ||
        !teacherClassifierSafe(value.authority, 8192)) {
        throw IllegalArgumentException("candidate_generation_invalid")
    }
    "{\"schemaVersion\":\"teacher-failure-asset-classifier-request-v1\"," +
        "\"failureEvidenceHash\":\"${value.failureEvidenceHash}\"," +
        "\"observation\":\"${teacherClassifierEscape(value.observation)}\"," +
        "\"publicSummary\":\"${teacherClassifierEscape(value.publicSummary)}\"," +
        "\"authority\":\"${teacherClassifierEscape(value.authority)}\"}"
}

private func teacherClassifierString(value: JsonObject, name: String): String {
    match (value.get(name)) { case Some(v) => v.asString().getValue(); case None => "" }
}

private func teacherClassifierBool(value: JsonObject, name: String): Bool {
    match (value.get(name)) { case Some(v) => v.asBool().getValue(); case None => false }
}

private func teacherInternalClassificationEvidence(value: TeacherFailureAssetClassification): String {
    "{\"schemaVersion\":\"teacher-failure-asset-classification-v2\"," +
        "\"failureEvidenceHash\":\"${value.failureEvidenceHash}\",\"gapKind\":\"${value.gapKind}\"," +
        "\"knowledgeEligible\":${value.knowledgeEligible},\"skillEligible\":${value.skillEligible}," +
        "\"rulesEligible\":${value.rulesEligible},\"classificationReasonCode\":\"${value.classificationReasonCode}\"}"
}

public func renderTeacherFailureAssetClassifierResponse(value: TeacherFailureAssetClassification): String {
    if (value.schemaVersion != "teacher-failure-asset-classification-v2") {
        throw IllegalArgumentException("classification_identity_invalid")
    }
    let evidence = teacherInternalClassificationEvidence(value)
    if (value.classificationEvidenceHash != teacherStableHash(evidence)) {
        throw IllegalArgumentException("classification_evidence_hash_mismatch")
    }
    let runes = evidence.toRuneArray()
    String(runes[..runes.size - 1]) +
        ",\"classificationEvidenceHash\":\"${value.classificationEvidenceHash}\"}"
}

public func parseTeacherFailureAssetClassifierResponse(raw: String): TeacherFailureAssetClassification {
    try {
        let object = JsonValue.fromStr(raw).asObject()
        if (object.getFields().size != 8 ||
            teacherClassifierString(object, "schemaVersion") != "teacher-failure-asset-classification-v2") {
            throw IllegalArgumentException("classification_schema_fields_invalid")
        }
        let value = TeacherFailureAssetClassification("teacher-failure-asset-classification-v2",
            teacherClassifierString(object, "failureEvidenceHash"), teacherClassifierString(object, "gapKind"),
            teacherClassifierBool(object, "knowledgeEligible"), teacherClassifierBool(object, "skillEligible"),
            teacherClassifierBool(object, "rulesEligible"), teacherClassifierString(object, "classificationReasonCode"),
            teacherClassifierString(object, "classificationEvidenceHash"))
        let evidence = teacherInternalClassificationEvidence(value)
        if (value.classificationEvidenceHash != teacherStableHash(evidence)) {
            throw IllegalArgumentException("classification_evidence_hash_mismatch")
        }
        let sharedEvidence = evidence.replace("teacher-failure-asset-classification-v2",
            "ckb-completion-failure-classification-v2")
        let sharedRunes = sharedEvidence.toRuneArray()
        let sharedRaw = String(sharedRunes[..sharedRunes.size - 1]) +
            ",\"classificationEvidenceHash\":\"${teacherStableHash(sharedEvidence)}\"}"
        _ = parseTeacherFailureAssetClassification(sharedRaw)
        if (raw != renderTeacherFailureAssetClassifierResponse(value)) {
            throw IllegalArgumentException("classification_schema_fields_invalid")
        }
        value
    } catch (e: IllegalArgumentException) {
        if (["classification_schema_fields_invalid", "classification_identity_invalid",
            "classification_eligibility_invalid", "classification_evidence_hash_mismatch"].contains(e.message)) { throw e }
        throw IllegalArgumentException("malformed_json")
    } catch (_: Exception) { throw IllegalArgumentException("malformed_json") }
}

public func reconcileTeacherFailureAssetClassifications(a: TeacherFailureAssetClassification,
    b: TeacherFailureAssetClassification): TeacherFailureAssetClassification {
    if (a.schemaVersion != "teacher-failure-asset-classification-v2" ||
        b.schemaVersion != "teacher-failure-asset-classification-v2" ||
        a.failureEvidenceHash != b.failureEvidenceHash || a.gapKind != b.gapKind ||
        a.knowledgeEligible != b.knowledgeEligible || a.skillEligible != b.skillEligible ||
        a.rulesEligible != b.rulesEligible || a.classificationReasonCode != b.classificationReasonCode) {
        throw IllegalArgumentException("classification_requires_review")
    }
    let provisional = TeacherFailureAssetClassification("ckb-completion-failure-classification-v2",
        a.failureEvidenceHash, a.gapKind, a.knowledgeEligible, a.skillEligible, a.rulesEligible,
        a.classificationReasonCode, "")
    let evidence = "{\"schemaVersion\":\"ckb-completion-failure-classification-v2\"," +
        "\"failureEvidenceHash\":\"${provisional.failureEvidenceHash}\",\"gapKind\":\"${provisional.gapKind}\"," +
        "\"knowledgeEligible\":${provisional.knowledgeEligible},\"skillEligible\":${provisional.skillEligible}," +
        "\"rulesEligible\":${provisional.rulesEligible},\"classificationReasonCode\":\"${provisional.classificationReasonCode}\"}"
    let sealed = TeacherFailureAssetClassification(provisional.schemaVersion, provisional.failureEvidenceHash,
        provisional.gapKind, provisional.knowledgeEligible, provisional.skillEligible, provisional.rulesEligible,
        provisional.classificationReasonCode, teacherStableHash(evidence))
    _ = parseTeacherFailureAssetClassification(renderTeacherFailureAssetClassification(sealed))
    sealed
}
