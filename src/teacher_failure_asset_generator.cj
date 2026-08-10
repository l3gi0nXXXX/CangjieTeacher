package cangjie_teacher

import std.collection.*
import std.fs.*
import stdx.encoding.json.*

public class TeacherFailureAssetGenerationRequest {
    public let failureEvidenceHash: String
    public let classificationEvidenceHash: String
    public let lane: String
    public let gapDescription: String
    public init(failureEvidenceHash: String, classificationEvidenceHash: String, lane: String,
        gapDescription: String) {
        this.failureEvidenceHash = failureEvidenceHash
        this.classificationEvidenceHash = classificationEvidenceHash
        this.lane = lane; this.gapDescription = gapDescription
    }
}

public class TeacherFailureAssetGenerationResponse {
    public let lane: String
    public let title: String
    public let content: String
    public let trigger: String
    public let scope: String
    public let priority: Int64
    public let proposalHash: String
    public init(lane: String, title: String, content: String, trigger: String, scope: String,
        priority: Int64, proposalHash: String) {
        this.lane = lane; this.title = title; this.content = content
        this.trigger = trigger; this.scope = scope; this.priority = priority
        this.proposalHash = proposalHash
    }
}

public interface TeacherFailureAssetGenerator {
    func generate(request: TeacherFailureAssetGenerationRequest): String
}

private func teacherGeneratorExecutable(value: String, expectedHash: String): Bool {
    let path = Path(value)
    if (!path.isAbsolute() || !exists(path) || !expectedHash.startsWith("sha256:")) { return false }
    try {
        !FileInfo(path).isSymbolicLink() && FileInfo(path).isRegular() &&
            canonicalize(path).toString() == value &&
            teacherValidationExecutableHash(value) == expectedHash
    } catch (_: Exception) { false }
}

// The frozen generator adapter receives one canonical sanitized lane request and writes
// one strict proposal response. Provider console output is never treated as evidence.
public class StrictProcessTeacherFailureAssetGenerator <: TeacherFailureAssetGenerator {
    private let executable: String
    private let executableHash: String
    private let workspaceRoot: String
    private let executor: TeacherCommandExecutor
    private let timeoutMillis: Int64
    public init(executable: String, executableHash: String, allowedRoot: String,
        workspaceRoot: String, executor!: TeacherCommandExecutor = NativeTeacherCommandExecutor(),
        timeoutMillis!: Int64 = 600000) {
        if (!teacherGeneratorExecutable(executable, executableHash) || timeoutMillis < 1 ||
            timeoutMillis > 3600000) { throw IllegalArgumentException("candidate_generation_invalid") }
        this.executable = executable; this.executableHash = executableHash
        this.workspaceRoot = teacherResolveArtifactInput(allowedRoot, workspaceRoot, directory: true)
        this.executor = executor; this.timeoutMillis = timeoutMillis
    }
    public func generate(request: TeacherFailureAssetGenerationRequest): String {
        let canonicalRequest = renderTeacherFailureAssetGenerationRequest(request)
        let requestHash = teacherStableHash(canonicalRequest)
        let runRoot = Path(workspaceRoot).join("generation-${request.lane}-${requestHash}")
        if (exists(runRoot)) { throw IllegalArgumentException("candidate_generation_invalid") }
        Directory.create(runRoot, recursive: true)
        let requestPath = runRoot.join("request.json").toString()
        let outputPath = runRoot.join("response.json").toString()
        _ = teacherAtomicWrite(requestPath, canonicalRequest + "\n")
        let result = executor.execute(TeacherCommandSpec(executable,
            ["--request", requestPath, "--output", outputPath], runRoot.toString(),
            env: [("CANGJIE_TEACHER_ADAPTER_EXECUTABLE_HASH", executableHash)],
            timeoutMillis: timeoutMillis))
        if (result.timedOut || result.exitCode != 0 || !exists(Path(outputPath))) {
            throw IllegalArgumentException("candidate_generation_invalid")
        }
        let raw = teacherReadUtf8File(outputPath).trimAscii()
        if (raw.toArray().size > 32768) { throw IllegalArgumentException("candidate_generation_invalid") }
        let parsed = parseTeacherFailureAssetGenerationResponse(raw)
        if (parsed.lane != request.lane || raw != renderTeacherFailureAssetGenerationResponse(parsed)) {
            throw IllegalArgumentException("candidate_generation_invalid")
        }
        raw
    }
}

private func teacherGenerationEscape(value: String): String {
    value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
        .replace("\r", "\\r").replace("\t", "\\t")
}

private func teacherGenerationString(value: JsonObject, name: String): String {
    match (value.get(name)) { case Some(v) => v.asString().getValue(); case None => "" }
}

private func teacherGenerationSafe(value: String): Bool {
    if (value.isEmpty() || value.toArray().size > 8192) { return false }
    let lower = value.toAsciiLower()
    for (marker in ["cj-humaneval-", "caseid", "hidden_test", "expectedoutput", "solution_cj",
        "reference solution", "/users/", "/home/", "/private/", "authorization", "token=", "password="]) {
        if (lower.contains(marker)) { return false }
    }
    true
}

public func renderTeacherFailureAssetGenerationRequest(value: TeacherFailureAssetGenerationRequest): String {
    if (!["knowledge", "skill", "rules"].contains(value.lane) ||
        value.failureEvidenceHash.toRuneArray().size != 64 ||
        value.classificationEvidenceHash.toRuneArray().size != 64 ||
        !teacherGenerationSafe(value.gapDescription)) {
        throw IllegalArgumentException("candidate_generation_invalid")
    }
    "{\"schemaVersion\":\"teacher-failure-asset-generation-request-v1\"," +
        "\"failureEvidenceHash\":\"${value.failureEvidenceHash}\"," +
        "\"classificationEvidenceHash\":\"${value.classificationEvidenceHash}\"," +
        "\"lane\":\"${value.lane}\",\"gapDescription\":\"${teacherGenerationEscape(value.gapDescription)}\"}"
}

private func teacherGenerationEvidence(value: TeacherFailureAssetGenerationResponse): String {
    "{\"schemaVersion\":\"teacher-failure-asset-generation-response-v1\",\"lane\":\"${value.lane}\"," +
        "\"title\":\"${teacherGenerationEscape(value.title)}\",\"content\":\"${teacherGenerationEscape(value.content)}\"," +
        "\"trigger\":\"${teacherGenerationEscape(value.trigger)}\",\"scope\":\"${teacherGenerationEscape(value.scope)}\"," +
        "\"priority\":${value.priority}}"
}

public func renderTeacherFailureAssetGenerationResponse(value: TeacherFailureAssetGenerationResponse): String {
    let evidence = teacherGenerationEvidence(value)
    if (value.proposalHash != "sha256:${teacherStableHash(evidence)}") {
        throw IllegalArgumentException("candidate_generation_invalid")
    }
    let runes = evidence.toRuneArray()
    String(runes[..runes.size - 1]) + ",\"proposalHash\":\"${value.proposalHash}\"}"
}

public func parseTeacherFailureAssetGenerationResponse(raw: String): TeacherFailureAssetGenerationResponse {
    try {
        let object = JsonValue.fromStr(raw).asObject()
        if (object.getFields().size != 8 ||
            teacherGenerationString(object, "schemaVersion") != "teacher-failure-asset-generation-response-v1") {
            throw IllegalArgumentException("candidate_generation_invalid")
        }
        let priority = match (object.get("priority")) {
            case Some(v) => v.asInt().getValue(); case None => Int64(-1)
        }
        let value = TeacherFailureAssetGenerationResponse(teacherGenerationString(object, "lane"),
            teacherGenerationString(object, "title"), teacherGenerationString(object, "content"),
            teacherGenerationString(object, "trigger"), teacherGenerationString(object, "scope"),
            priority, teacherGenerationString(object, "proposalHash"))
        if (!["knowledge", "skill", "rules"].contains(value.lane) || !teacherGenerationSafe(value.title) ||
            !teacherGenerationSafe(value.content) || !teacherGenerationSafe(value.trigger) ||
            !teacherGenerationSafe(value.scope) || value.priority < 0 || value.priority > 1000 ||
            raw != renderTeacherFailureAssetGenerationResponse(value)) {
            throw IllegalArgumentException("candidate_generation_invalid")
        }
        value
    } catch (e: IllegalArgumentException) {
        if (e.message == "candidate_generation_invalid") { throw e }
        throw IllegalArgumentException("malformed_json")
    } catch (_: Exception) { throw IllegalArgumentException("malformed_json") }
}

public func generateTeacherFailureAssetProposals(classification: TeacherFailureAssetClassification,
    gapDescription: String, generator: TeacherFailureAssetGenerator): Array<TeacherFailureAssetGenerationResponse> {
    if (classification.schemaVersion != "ckb-completion-failure-classification-v2") {
        throw IllegalArgumentException("candidate_generation_invalid")
    }
    let lanes = ArrayList<String>()
    if (classification.knowledgeEligible) { lanes.add("knowledge") }
    if (classification.skillEligible) { lanes.add("skill") }
    if (classification.rulesEligible) { lanes.add("rules") }
    let results = ArrayList<TeacherFailureAssetGenerationResponse>()
    let contents = HashSet<String>()
    for (lane in lanes) {
        let request = TeacherFailureAssetGenerationRequest(classification.failureEvidenceHash,
            classification.classificationEvidenceHash, lane, gapDescription)
        _ = renderTeacherFailureAssetGenerationRequest(request)
        let proposal = parseTeacherFailureAssetGenerationResponse(generator.generate(request))
        if (proposal.lane != lane || contents.contains(proposal.content)) {
            throw IllegalArgumentException("candidate_generation_invalid")
        }
        contents.add(proposal.content); results.add(proposal)
    }
    results.toArray()
}
