package cangjie_teacher

import std.collection.*
import std.fs.*
import stdx.encoding.json.*

private let FAILURE_GENERATOR_MODEL = "gpt-5.6-sol"
private let FAILURE_GENERATOR_MAX_BYTES: Int64 = 262144

public class TeacherFailureAssetProviderGeneratorResult {
    public var ok = false
    public var diagnostic = "not_started"
    public init() {}
}

public func runTeacherFailureAssetProviderGenerator(args: Array<String>,
    executor!: TeacherCommandExecutor = NativeTeacherCommandExecutor(),
    codexExecutable!: String = "codex", timeoutMillis!: Int64 = 600000): Int64 {
    let result = executeTeacherFailureAssetProviderGenerator(args, executor: executor,
        codexExecutable: codexExecutable, timeoutMillis: timeoutMillis)
    if (result.ok) { println("failure asset generation complete"); return 0 }
    println("failure asset generation blocked diagnostic=${result.diagnostic}")
    1
}

public func executeTeacherFailureAssetProviderGenerator(args: Array<String>,
    executor!: TeacherCommandExecutor, codexExecutable!: String,
    timeoutMillis!: Int64): TeacherFailureAssetProviderGeneratorResult {
    let result = TeacherFailureAssetProviderGeneratorResult()
    try {
        let paths = parseFailureGeneratorPaths(args)
        if (codexExecutable.trimAscii() == "" || timeoutMillis < 1 || timeoutMillis > 3600000 ||
            !failureGeneratorPathsSafe(paths[0], paths[1])) {
            result.diagnostic = "adapter_contract_invalid"; return result
        }
        let requestRaw = failureGeneratorReadUtf8(paths[0], "request_missing")
        let request = failureGeneratorParseRequest(requestRaw)
        let parent = canonicalize(Path(paths[0]).parent).toString()
        let schemaPath = Path(parent).join("provider-response.schema.json").toString()
        let modelOutput = Path(parent).join("provider-response.model.json").toString()
        _ = teacherAtomicWrite(schemaPath, failureGeneratorOutputSchema())
        try { if (exists(Path(modelOutput))) { remove(Path(modelOutput)) } } catch (_: Exception) {}
        let command = TeacherCommandSpec(codexExecutable,
            ["exec", "-m", FAILURE_GENERATOR_MODEL, "--sandbox", "read-only",
             "--skip-git-repo-check", "--ephemeral", "--ignore-user-config", "--ignore-rules",
             "-C", parent, "--output-schema", schemaPath, "--output-last-message", modelOutput,
             failureGeneratorPrompt(requestRaw, request.lane)], parent, timeoutMillis: timeoutMillis)
        let process = executor.execute(command)
        if (process.timedOut) { result.diagnostic = "provider_timeout"; return result }
        if (process.exitCode != 0) { result.diagnostic = "provider_process_failed"; return result }
        let modelRaw = failureGeneratorReadUtf8(modelOutput, "provider_output_missing").trimAscii()
        let response = failureGeneratorSealResponse(modelRaw, request.lane)
        _ = teacherAtomicWrite(paths[1], response + "\n")
        result.ok = true; result.diagnostic = "ok"; result
    } catch (e: IllegalArgumentException) {
        result.diagnostic = failureGeneratorDiagnostic(e.message); result
    } catch (_: Exception) {
        result.diagnostic = "adapter_failed"; result
    }
}

private func parseFailureGeneratorPaths(args: Array<String>): Array<String> {
    if (args.size != 4) { throw IllegalArgumentException("invalid_arguments") }
    var request = ""; var output = ""
    for (i in 0..4: 2) {
        let value = args[i + 1].trimAscii()
        if (value == "") { throw IllegalArgumentException("invalid_arguments") }
        match (args[i]) {
            case "--request" => if (request == "") { request = value } else { throw IllegalArgumentException("invalid_arguments") }
            case "--output" => if (output == "") { output = value } else { throw IllegalArgumentException("invalid_arguments") }
            case _ => throw IllegalArgumentException("invalid_arguments")
        }
    }
    if (request == "" || output == "") { throw IllegalArgumentException("invalid_arguments") }
    [request, output]
}

private func failureGeneratorPathsSafe(request: String, output: String): Bool {
    try {
        if (!Path(request).isAbsolute() || !Path(output).isAbsolute() || request == output ||
            !exists(Path(request)) || exists(Path(output)) || output.contains("..")) { return false }
        let canonicalRequest = canonicalize(Path(request)).toString()
        let requestParent = canonicalize(Path(request).parent).toString()
        let outputParent = canonicalize(Path(output).parent).toString()
        canonicalRequest == request && requestParent == outputParent &&
            !FileInfo(Path(request)).isSymbolicLink() && FileInfo(Path(request)).isRegular()
    } catch (_: Exception) { false }
}

private func failureGeneratorReadUtf8(path: String, missing: String): String {
    if (!exists(Path(path))) { throw IllegalArgumentException(missing) }
    let bytes = File.readFrom(Path(path))
    if (bytes.size > FAILURE_GENERATOR_MAX_BYTES) { throw IllegalArgumentException("payload_too_large") }
    try { String.fromUtf8(bytes) } catch (_: Exception) { throw IllegalArgumentException("invalid_response_encoding") }
}

private func failureGeneratorParseRequest(raw: String): TeacherFailureAssetGenerationRequest {
    if (failureGeneratorForbidden(raw)) { throw IllegalArgumentException("forbidden_data") }
    try {
        let object = JsonValue.fromStr(raw).asObject()
        if (object.getFields().size != 5 || failureGeneratorString(object, "schemaVersion") !=
            "teacher-failure-asset-generation-request-v1") {
            throw IllegalArgumentException("request_contract_invalid")
        }
        let request = TeacherFailureAssetGenerationRequest(
            failureGeneratorString(object, "failureEvidenceHash"),
            failureGeneratorString(object, "classificationEvidenceHash"),
            failureGeneratorString(object, "lane"), failureGeneratorString(object, "gapDescription"))
        if (!failureGeneratorBareHash(request.failureEvidenceHash) ||
            !failureGeneratorBareHash(request.classificationEvidenceHash) ||
            raw.trimAscii() != renderTeacherFailureAssetGenerationRequest(request)) {
            throw IllegalArgumentException("request_contract_invalid")
        }
        request
    } catch (e: IllegalArgumentException) { throw e }
    catch (_: Exception) { throw IllegalArgumentException("malformed_json") }
}

private func failureGeneratorSealResponse(raw: String, expectedLane: String): String {
    if (failureGeneratorForbidden(raw)) { throw IllegalArgumentException("forbidden_data") }
    try {
        let object = JsonValue.fromStr(raw).asObject()
        if (object.getFields().size != 7 ||
            failureGeneratorString(object, "schemaVersion") != "teacher-failure-asset-generation-response-v1") {
            throw IllegalArgumentException("response_contract_invalid")
        }
        let lane = failureGeneratorString(object, "lane")
        if (lane != expectedLane) { throw IllegalArgumentException("lane_mismatch") }
        let title = failureGeneratorString(object, "title")
        let content = failureGeneratorString(object, "content")
        let trigger = failureGeneratorString(object, "trigger")
        let scope = failureGeneratorString(object, "scope")
        let priority = object.get("priority").getOrThrow().asInt().getValue()
        let renderedRule = "\n## ${title}\n\n${content}\n\nTrigger: ${trigger}\nScope: ${scope}\n"
        if (lane == "rules" && renderedRule.toArray().size > 1000) {
            throw IllegalArgumentException("response_contract_invalid")
        }
        let evidence = "{\"schemaVersion\":\"teacher-failure-asset-generation-response-v1\",\"lane\":\"${lane}\"," +
            "\"title\":\"${failureGeneratorEscape(title)}\",\"content\":\"${failureGeneratorEscape(content)}\"," +
            "\"trigger\":\"${failureGeneratorEscape(trigger)}\",\"scope\":\"${failureGeneratorEscape(scope)}\"," +
            "\"priority\":${priority}}"
        if (raw != evidence) { throw IllegalArgumentException("response_contract_invalid") }
        let sealed = TeacherFailureAssetGenerationResponse(lane, title, content, trigger, scope,
            priority, "sha256:${teacherStableHash(evidence)}")
        let canonical = renderTeacherFailureAssetGenerationResponse(sealed)
        _ = parseTeacherFailureAssetGenerationResponse(canonical)
        canonical
    } catch (e: IllegalArgumentException) { throw e }
    catch (_: Exception) { throw IllegalArgumentException("malformed_json") }
}

private func failureGeneratorPrompt(request: String, lane: String): String {
    let rulesBudget = if (lane == "rules") {
        " Keep the complete rendered rule (heading, body, trigger, and scope) at most 1000 UTF-8 bytes."
    } else { "" }
    "Generate one reusable ${lane} guidance proposal from the sanitized failure-gap request below. " +
    "Return exactly one canonical JSON object matching the output schema. Keep lane exactly ${lane}. " +
    "Do not add proposalHash; the trusted adapter computes and seals it after validating the seven business fields. " +
    "Do not include case identifiers, task answers, solution code, hidden tests, filesystem paths, credentials, " +
    "tokens, authorization data, or private payloads. Generalize only from the supplied gap description." +
    "${rulesBudget} Request:\n${request}"
}

private func failureGeneratorOutputSchema(): String {
    "{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"schemaVersion\",\"lane\",\"title\",\"content\",\"trigger\",\"scope\",\"priority\"],\"properties\":{\"schemaVersion\":{\"type\":\"string\",\"const\":\"teacher-failure-asset-generation-response-v1\"},\"lane\":{\"type\":\"string\",\"enum\":[\"knowledge\",\"skill\",\"rules\"]},\"title\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"trigger\":{\"type\":\"string\"},\"scope\":{\"type\":\"string\"},\"priority\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":1000}}}"
}

private func failureGeneratorForbidden(value: String): Bool {
    let lower = value.toAsciiLower()
    for (marker in ["cj-humaneval-", "caseid", "case_id", "canonical_solution", "reference solution",
        "solution_cj", "hidden_test", "hidden-test", "expectedoutput", "/users/", "/home/", "/private/",
        "authorization", "api_key", "token=", "password", "secret="]) {
        if (lower.contains(marker)) { return true }
    }
    false
}

private func failureGeneratorBareHash(value: String): Bool {
    let runes = value.toRuneArray()
    if (runes.size != 64) { return false }
    for (rune in runes) {
        if (!((rune >= r'0' && rune <= r'9') || (rune >= r'a' && rune <= r'f'))) { return false }
    }
    true
}

private func failureGeneratorString(object: JsonObject, name: String): String {
    match (object.get(name)) { case Some(value) => value.asString().getValue(); case None => "" }
}

private func failureGeneratorEscape(value: String): String {
    value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
        .replace("\r", "\\r").replace("\t", "\\t")
}

private func failureGeneratorDiagnostic(value: String): String {
    if (["invalid_arguments", "adapter_contract_invalid", "request_missing", "payload_too_large",
        "invalid_response_encoding", "forbidden_data", "request_contract_invalid", "malformed_json",
        "provider_timeout", "provider_process_failed", "provider_output_missing", "response_contract_invalid",
        "lane_mismatch", "candidate_generation_invalid"].contains(value)) { value } else { "adapter_failed" }
}
