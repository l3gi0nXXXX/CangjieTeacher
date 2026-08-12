package cangjie_teacher

import std.collection.*
import std.fs.*
import stdx.encoding.json.*

private let FAILURE_CODEX_MODEL = "gpt-5.6-sol"
private let FAILURE_CLASSIFIER_MAX_BYTES: Int64 = 262144

public class TeacherFailureCodexResult {
    public var ok = false
    public var diagnostic = "not_started"
    public init() {}
}

public func runTeacherFailureCodexClassifier(args: Array<String>,
    executor!: TeacherCommandExecutor = NativeTeacherCommandExecutor(),
    codexExecutable!: String = "codex", timeoutMillis!: Int64 = 300000): Int64 {
    let result = executeTeacherFailureCodexClassifier(args, executor: executor,
        codexExecutable: codexExecutable, timeoutMillis: timeoutMillis)
    if (result.ok) { 0 } else { 1 }
}

public func executeTeacherFailureCodexClassifier(args: Array<String>,
    executor!: TeacherCommandExecutor, codexExecutable!: String,
    timeoutMillis!: Int64): TeacherFailureCodexResult {
    let result = TeacherFailureCodexResult()
    let parsed = failureCodexOptions(args)
    if (parsed[2] != "ok") { result.diagnostic = parsed[2]; return result }
    if (timeoutMillis < 1 || timeoutMillis > 3600000 || codexExecutable.trimAscii() == "") {
        result.diagnostic = "adapter_identity_invalid"; return result
    }
    let requestPath = parsed[0]; let outputPath = parsed[1]
    if (!failureCodexPathsValid(requestPath, outputPath)) {
        result.diagnostic = "adapter_path_invalid"; return result
    }
    let requestRaw = try { failureCodexReadUtf8(requestPath) } catch (_: Exception) {
        result.diagnostic = "invalid_request_encoding"; return result
    }
    if (requestRaw.toArray().size > FAILURE_CLASSIFIER_MAX_BYTES) {
        result.diagnostic = "request_too_large"; return result
    }
    let request = try { failureCodexRequest(requestRaw.trimAscii()) } catch (e: IllegalArgumentException) {
        result.diagnostic = e.message; return result
    }
    let workspace = canonicalize(Path(requestPath).parent).toString()
    let schemaPath = Path(workspace).join("failure-classification.schema.json").toString()
    let modelPath = Path(workspace).join("failure-classification.model.json").toString()
    try {
        _ = teacherAtomicWrite(schemaPath, failureCodexSchema())
        if (exists(Path(modelPath))) { remove(Path(modelPath)) }
    } catch (_: Exception) { result.diagnostic = "workspace_write_failed"; return result }
    let prompt = failureClassifierPrompt(requestRaw.trimAscii())
    let process = executor.execute(TeacherCommandSpec(codexExecutable,
        ["exec", "-m", FAILURE_CODEX_MODEL, "--sandbox", "read-only", "--skip-git-repo-check",
         "--ephemeral", "--ignore-user-config", "--ignore-rules", "-C", workspace,
         "--output-schema", schemaPath, "--output-last-message", modelPath, prompt],
        workspace, timeoutMillis: timeoutMillis))
    if (process.timedOut) { result.diagnostic = "classifier_timeout"; return result }
    if (process.exitCode != 0) { result.diagnostic = "classifier_process_failed"; return result }
    let modelRaw = try { failureCodexReadUtf8(modelPath) } catch (_: Exception) {
        result.diagnostic = "invalid_response_encoding"; return result
    }
    if (modelRaw.toArray().size > FAILURE_CLASSIFIER_MAX_BYTES) {
        result.diagnostic = "classifier_output_too_large"; return result
    }
    let response = try { failureCodexSeal(request[0], modelRaw.trimAscii()) }
        catch (e: IllegalArgumentException) { result.diagnostic = e.message; return result }
    try { _ = teacherAtomicWrite(outputPath, response + "\n") }
    catch (_: Exception) { result.diagnostic = "response_write_failed"; return result }
    result.ok = true; result.diagnostic = "ok"; result
}

private func failureCodexOptions(args: Array<String>): (String, String, String) {
    var request = ""; var output = ""; let seen = HashSet<String>(); var i: Int64 = 0
    while (i < args.size) {
        if (i + 1 >= args.size || seen.contains(args[i]) || args[i + 1].trimAscii() == "") {
            return ("", "", "invalid_adapter_arguments")
        }
        seen.add(args[i])
        match (args[i]) {
            case "--request" => request = args[i + 1].trimAscii()
            case "--output" => output = args[i + 1].trimAscii()
            case _ => return ("", "", "invalid_adapter_arguments")
        }
        i += 2
    }
    if (seen.size != 2) { ("", "", "invalid_adapter_arguments") } else { (request, output, "ok") }
}

private func failureCodexPathsValid(request: String, output: String): Bool {
    try {
        if (!Path(request).isAbsolute() || !Path(output).isAbsolute() || !exists(Path(request)) ||
            request == output || exists(Path(output)) || FileInfo(Path(request)).isSymbolicLink()) { return false }
        let canonicalRequest = canonicalize(Path(request)).toString()
        let requestParent = canonicalize(Path(request).parent).toString()
        let outputParent = canonicalize(Path(output).parent).toString()
        canonicalRequest == request && requestParent == outputParent &&
            Path(request).parent.join(Path(request).fileName).toString() == request &&
            Path(output).parent.join(Path(output).fileName).toString() == output
    } catch (_: Exception) { false }
}

private func failureCodexReadUtf8(path: String): String {
    try { String.fromUtf8(File.readFrom(Path(path))) }
    catch (_: Exception) { throw IllegalArgumentException("invalid_response_encoding") }
}

// Returns the failure evidence hash after exact canonical-contract validation.
private func failureCodexRequest(raw: String): Array<String> {
    try {
        let object = JsonValue.fromStr(raw).asObject()
        let hash = failureCodexString(object, "failureEvidenceHash")
        let observation = failureCodexString(object, "observation")
        let summary = failureCodexString(object, "publicSummary")
        let authority = failureCodexString(object, "authority")
        if (object.getFields().size != 5 || hash.toRuneArray().size != 64 ||
            raw != renderTeacherFailureAssetClassifierRequest(
                TeacherFailureAssetClassifierRequest(hash, observation, summary, authority))) {
            throw IllegalArgumentException("request_contract_invalid")
        }
        [hash]
    } catch (e: IllegalArgumentException) {
        if (e.message == "request_contract_invalid") { throw e }
        throw IllegalArgumentException("request_contract_invalid")
    } catch (_: Exception) { throw IllegalArgumentException("request_contract_invalid") }
}

private func failureCodexSeal(hash: String, raw: String): String {
    try {
        if (failureCodexForbidden(raw)) { throw IllegalArgumentException("response_contains_forbidden_data") }
        let object = JsonValue.fromStr(raw).asObject()
        if (object.getFields().size != 5) { throw IllegalArgumentException("response_contract_invalid") }
        let gap = failureCodexString(object, "gapKind")
        let knowledge = failureCodexBool(object, "knowledgeEligible")
        let skill = failureCodexBool(object, "skillEligible")
        let rules = failureCodexBool(object, "rulesEligible")
        let reason = failureCodexString(object, "classificationReasonCode")
        let evidence = "{\"schemaVersion\":\"teacher-failure-asset-classification-v2\"," +
            "\"failureEvidenceHash\":\"${hash}\",\"gapKind\":\"${gap}\"," +
            "\"knowledgeEligible\":${knowledge},\"skillEligible\":${skill}," +
            "\"rulesEligible\":${rules},\"classificationReasonCode\":\"${reason}\"}"
        let value = TeacherFailureAssetClassification("teacher-failure-asset-classification-v2",
            hash, gap, knowledge, skill, rules, reason, teacherStableHash(evidence))
        let canonical = renderTeacherFailureAssetClassifierResponse(value)
        _ = parseTeacherFailureAssetClassifierResponse(canonical)
        canonical
    } catch (e: IllegalArgumentException) {
        if (["response_contains_forbidden_data", "classification_eligibility_invalid",
            "classification_identity_invalid"].contains(e.message)) { throw e }
        throw IllegalArgumentException("response_contract_invalid")
    } catch (_: Exception) { throw IllegalArgumentException("malformed_json") }
}

private func failureClassifierPrompt(request: String): String {
    "Classify this sanitized Cangjie Student failure. Return only the requested JSON object. " +
    "Choose exactly one valid gapKind/eligibility/reason combination. Reusable missing facts use " +
    "knowledge_gap/missing_versioned_fact; reusable procedures use procedure_gap/missing_reusable_procedure; " +
    "global behavioral constraints use rules_gap/missing_global_invariant; combinations use the matching " +
    "combined gap and multiple_reusable_gaps. Use infrastructure_failure/infrastructure_only for provider, " +
    "timeout, protocol, runner, or environment failures. Never reveal case identifiers, hidden tests, reference " +
    "solutions, credentials, or local paths. Request:\n${request}"
}

private func failureCodexSchema(): String {
    "{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"gapKind\",\"knowledgeEligible\",\"skillEligible\",\"rulesEligible\",\"classificationReasonCode\"],\"properties\":{\"gapKind\":{\"type\":\"string\",\"enum\":[\"knowledge_gap\",\"procedure_gap\",\"rules_gap\",\"knowledge_procedure_gap\",\"knowledge_rules_gap\",\"procedure_rules_gap\",\"all_assets_gap\",\"none\",\"reasoning_error\",\"translation_defect\",\"infrastructure_failure\"]},\"knowledgeEligible\":{\"type\":\"boolean\"},\"skillEligible\":{\"type\":\"boolean\"},\"rulesEligible\":{\"type\":\"boolean\"},\"classificationReasonCode\":{\"type\":\"string\"}}}"
}

private func failureCodexForbidden(value: String): Bool {
    let lower = value.toAsciiLower()
    for (marker in ["cj-humaneval-", "/users/", "/home/", "/private/", "authorization",
        "token=", "password", "api_key", "hidden_test", "hidden-test", "reference solution"]) {
        if (lower.contains(marker)) { return true }
    }
    false
}
private func failureCodexString(object: JsonObject, name: String): String {
    match (object.get(name)) { case Some(value) => value.asString().getValue(); case None => "" }
}
private func failureCodexBool(object: JsonObject, name: String): Bool {
    match (object.get(name)) { case Some(value) => value.asBool().getValue(); case None => false }
}
