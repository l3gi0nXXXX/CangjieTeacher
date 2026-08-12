package cangjie_teacher

import std.fs.*
import stdx.encoding.json.*

private let FAILURE_CLAUDE_MODEL = "GLM-5.2"

public func runTeacherFailureClaudeClassifier(args: Array<String>,
    executor!: TeacherCommandExecutor = NativeTeacherCommandExecutor(),
    claudeExecutable!: String = "claude", timeoutMillis!: Int64 = 300000): Int64 {
    let result = executeTeacherFailureClaudeClassifier(args, executor: executor,
        claudeExecutable: claudeExecutable, timeoutMillis: timeoutMillis)
    if (result.ok) { 0 } else { 1 }
}

public func executeTeacherFailureClaudeClassifier(args: Array<String>,
    executor!: TeacherCommandExecutor, claudeExecutable!: String,
    timeoutMillis!: Int64): TeacherFailureCodexResult {
    let result = TeacherFailureCodexResult()
    // Claude shares the strict two-path parser, request validator, canonical sealer,
    // and diagnostics with Codex; only the provider transport differs.
    let parsed = failureClaudeOptions(args)
    if (parsed[2] != "ok") { result.diagnostic = parsed[2]; return result }
    if (timeoutMillis < 1 || timeoutMillis > 3600000 || claudeExecutable.trimAscii() == "") {
        result.diagnostic = "adapter_identity_invalid"; return result
    }
    let request = parsed[0]; let output = parsed[1]
    if (!failureClaudePathsValid(request, output)) { result.diagnostic = "adapter_path_invalid"; return result }
    let raw = try { String.fromUtf8(File.readFrom(Path(request))) } catch (_: Exception) {
        result.diagnostic = "invalid_request_encoding"; return result
    }
    if (raw.toArray().size > 262144) { result.diagnostic = "request_too_large"; return result }
    let hash = try { failureClaudeRequestHash(raw.trimAscii()) } catch (e: IllegalArgumentException) {
        result.diagnostic = e.message; return result
    }
    let workspace = canonicalize(Path(request).parent).toString()
    let schema = failureClaudeSchema()
    let prompt = "Classify this sanitized Cangjie Student failure. Return only the schema object. " +
        "Use infrastructure_failure/infrastructure_only for provider timeout, protocol, runner, or environment " +
        "failures. Never reveal case identifiers, hidden tests, reference solutions, credentials, or local paths.\n" + raw.trimAscii()
    let process = executor.execute(TeacherCommandSpec(claudeExecutable,
        ["-p", prompt, "--model", FAILURE_CLAUDE_MODEL, "--json-schema", schema,
         "--output-format", "json", "--effort", "low", "--no-session-persistence", "--bare",
         "--disable-slash-commands", "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}",
         "--tools", ""], workspace, timeoutMillis: timeoutMillis))
    if (process.timedOut) { result.diagnostic = "classifier_timeout"; return result }
    if (process.exitCode != 0) { result.diagnostic = "classifier_process_failed"; return result }
    if (process.output == "invalid_response_encoding") { result.diagnostic = "invalid_response_encoding"; return result }
    if (process.output.toArray().size > 262144) { result.diagnostic = "classifier_output_too_large"; return result }
    let model = try { failureClaudeTerminal(process.output) } catch (e: IllegalArgumentException) {
        result.diagnostic = e.message; return result
    }
    let response = try { failureClaudeSeal(hash, model) } catch (e: IllegalArgumentException) {
        result.diagnostic = e.message; return result
    }
    try { _ = teacherAtomicWrite(output, response + "\n") }
    catch (_: Exception) { result.diagnostic = "response_write_failed"; return result }
    result.ok = true; result.diagnostic = "ok"; result
}

private func failureClaudeOptions(args: Array<String>): (String, String, String) {
    if (args.size != 4) { return ("", "", "invalid_adapter_arguments") }
    if (args[0] == "--request" && args[2] == "--output" && args[1].trimAscii() != "" && args[3].trimAscii() != "") {
        return (args[1].trimAscii(), args[3].trimAscii(), "ok")
    }
    if (args[0] == "--output" && args[2] == "--request" && args[1].trimAscii() != "" && args[3].trimAscii() != "") {
        return (args[3].trimAscii(), args[1].trimAscii(), "ok")
    }
    ("", "", "invalid_adapter_arguments")
}

private func failureClaudePathsValid(request: String, output: String): Bool {
    try {
        Path(request).isAbsolute() && Path(output).isAbsolute() && exists(Path(request)) &&
            !exists(Path(output)) && request != output && !FileInfo(Path(request)).isSymbolicLink() &&
            canonicalize(Path(request)).toString() == request &&
            canonicalize(Path(request).parent).toString() == canonicalize(Path(output).parent).toString() &&
            Path(request).parent.join(Path(request).fileName).toString() == request &&
            Path(output).parent.join(Path(output).fileName).toString() == output
    } catch (_: Exception) { false }
}

private func failureClaudeRequestHash(raw: String): String {
    try {
        let object = JsonValue.fromStr(raw).asObject()
        let hash = failureClaudeString(object, "failureEvidenceHash")
        let canonical = renderTeacherFailureAssetClassifierRequest(TeacherFailureAssetClassifierRequest(hash,
            failureClaudeString(object, "observation"), failureClaudeString(object, "publicSummary"),
            failureClaudeString(object, "authority")))
        if (object.getFields().size != 5 || hash.toRuneArray().size != 64 || raw != canonical) {
            throw IllegalArgumentException("request_contract_invalid")
        }
        hash
    } catch (_: Exception) { throw IllegalArgumentException("request_contract_invalid") }
}

private func failureClaudeTerminal(raw: String): String {
    try {
        let object = JsonValue.fromStr(raw).asObject()
        if (failureClaudeString(object, "type") != "result" ||
            failureClaudeString(object, "subtype") != "success" || failureClaudeBool(object, "is_error")) {
            throw IllegalArgumentException("classifier_unsuccessful_result")
        }
        let usage = object.get("modelUsage").getOrThrow().asObject()
        if (usage.getFields().size != 1) { throw IllegalArgumentException("observed_model_mismatch") }
        match (usage.get(FAILURE_CLAUDE_MODEL)) { case Some(_) => (); case None => throw IllegalArgumentException("observed_model_mismatch") }
        match (object.get("structured_output")) {
            case Some(value) => value.toString()
            case None => throw IllegalArgumentException("malformed_structured_output")
        }
    } catch (e: IllegalArgumentException) { throw e }
    catch (_: Exception) { throw IllegalArgumentException("malformed_terminal_json") }
}

private func failureClaudeSeal(hash: String, raw: String): String {
    try {
        let object = JsonValue.fromStr(raw).asObject()
        if (object.getFields().size != 5) { throw IllegalArgumentException("response_contract_invalid") }
        let gap = failureClaudeString(object, "gapKind")
        let knowledge = failureClaudeBool(object, "knowledgeEligible")
        let skill = failureClaudeBool(object, "skillEligible")
        let rules = failureClaudeBool(object, "rulesEligible")
        let reason = failureClaudeString(object, "classificationReasonCode")
        let joined = gap + " " + reason
        let lower = joined.toAsciiLower()
        for (marker in ["cj-humaneval-", "/users/", "/home/", "/private/", "authorization",
            "token=", "password", "api_key", "hidden_test", "hidden-test", "reference solution"]) {
            if (lower.contains(marker)) { throw IllegalArgumentException("response_contains_forbidden_data") }
        }
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
        if (e.message == "response_contains_forbidden_data") { throw e }
        throw IllegalArgumentException("response_contract_invalid")
    } catch (_: Exception) { throw IllegalArgumentException("malformed_json") }
}

private func failureClaudeSchema(): String {
    "{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"gapKind\",\"knowledgeEligible\",\"skillEligible\",\"rulesEligible\",\"classificationReasonCode\"],\"properties\":{\"gapKind\":{\"type\":\"string\",\"enum\":[\"knowledge_gap\",\"procedure_gap\",\"rules_gap\",\"knowledge_procedure_gap\",\"knowledge_rules_gap\",\"procedure_rules_gap\",\"all_assets_gap\",\"none\",\"reasoning_error\",\"translation_defect\",\"infrastructure_failure\"]},\"knowledgeEligible\":{\"type\":\"boolean\"},\"skillEligible\":{\"type\":\"boolean\"},\"rulesEligible\":{\"type\":\"boolean\"},\"classificationReasonCode\":{\"type\":\"string\"}}}"
}
private func failureClaudeString(object: JsonObject, name: String): String {
    match (object.get(name)) { case Some(value) => value.asString().getValue(); case None => "" }
}
private func failureClaudeBool(object: JsonObject, name: String): Bool {
    match (object.get(name)) { case Some(value) => value.asBool().getValue(); case None => false }
}
