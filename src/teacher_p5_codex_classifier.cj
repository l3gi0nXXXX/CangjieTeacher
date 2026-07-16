package cangjie_teacher

import std.collection.*
import std.convert.Parsable
import std.fs.*
import stdx.encoding.json.*

private let P5_CODEX_REQUEST_SCHEMA = "ckb-p5-classifier-request-v1"
private let P5_CODEX_RESPONSE_SCHEMA = "ckb-p5-classifier-response-v1"
private let P5_CODEX_PROVIDER = "codex"
private let P5_CODEX_MODEL = "GPT-5.6-Sol"
private let P5_CODEX_MODEL_ARG = "gpt-5.6-sol"
private let P5_CODEX_MAX_BYTES: Int64 = 262144

public class TeacherP5CodexAdapterOptions {
    public var request = ""
    public var output = ""
    public var workspace = ""
    public var runtimeHome = ""
    public var sessionId = ""
    public var expectedProvider = ""
    public var expectedModel = ""
    public var timeoutMillis: Int64 = 300000
    public init() {}
}

public class TeacherP5CodexAdapterResult {
    public var ok = false
    public var diagnostic = "not_started"
    public init() {}
}

public func runTeacherP5CodexClassifierAdapter(args: Array<String>,
    executor!: TeacherCommandExecutor = NativeTeacherCommandExecutor(), codexExecutable!: String = "codex",
    timeoutMillis!: Int64 = 300000): Int64 {
    let result = executeTeacherP5CodexClassifierAdapter(args, executor: executor,
        codexExecutable: codexExecutable, timeoutMillis: timeoutMillis)
    if (result.ok) { println("codex classifier complete"); return 0 }
    println("codex classifier blocked diagnostic=${result.diagnostic}")
    1
}

public func executeTeacherP5CodexClassifierAdapter(args: Array<String>, executor!: TeacherCommandExecutor,
    codexExecutable!: String, timeoutMillis!: Int64): TeacherP5CodexAdapterResult {
    let result = TeacherP5CodexAdapterResult()
    try {
        let options = parseTeacherP5CodexAdapterOptions(args)
        options.timeoutMillis = timeoutMillis
        if (options.expectedProvider != P5_CODEX_PROVIDER || options.expectedModel != P5_CODEX_MODEL ||
            timeoutMillis < 1 || timeoutMillis > 3600000 || codexExecutable.trimAscii() == "") {
            result.diagnostic = "adapter_identity_invalid"; return result
        }
        if (!p5CodexSafePaths(options)) { result.diagnostic = "adapter_path_invalid"; return result }
        let requestText = p5CodexReadBoundedUtf8(options.request)
        let request = p5CodexValidateRequest(requestText)
        if (request[0] != "ok") { result.diagnostic = request[0]; return result }
        if (!exists(Path(options.workspace))) { Directory.create(Path(options.workspace), recursive: true) }
        if (!exists(Path(options.runtimeHome))) { Directory.create(Path(options.runtimeHome), recursive: true) }
        let schemaPath = Path(options.workspace).join("classifier-response.schema.json").toString()
        let modelOutput = Path(options.workspace).join("classifier-response.model.json").toString()
        _ = teacherAtomicWrite(schemaPath, p5CodexOutputSchema())
        try { if (exists(Path(modelOutput))) { remove(Path(modelOutput)) } } catch (_: Exception) {}
        let prompt = p5CodexPrompt(requestText)
        // An empty controller runtime-home has no Codex login state. Keep it as
        // provenance isolation only; --ephemeral/--ignore-* prevent config and
        // session pollution while the process inherits the real authenticated home.
        let command = TeacherCommandSpec(codexExecutable,
            ["exec", "-m", P5_CODEX_MODEL_ARG, "--sandbox", "read-only", "--skip-git-repo-check",
             "--ephemeral", "--ignore-user-config", "--ignore-rules", "-C", options.workspace,
             "--output-schema", schemaPath, "--output-last-message", modelOutput, prompt],
            options.workspace, env: [("CANGJIE_TEACHER_SESSION", options.sessionId)],
            timeoutMillis: options.timeoutMillis)
        let process = executor.execute(command)
        if (process.timedOut) { result.diagnostic = "codex_timeout"; return result }
        if (process.exitCode != 0) { result.diagnostic = "codex_nonzero_exit"; return result }
        let raw = p5CodexReadBoundedUtf8(modelOutput)
        let response = p5CodexSealResponse(raw)
        if (response[0] != "ok") { result.diagnostic = response[0]; return result }
        _ = teacherAtomicWrite(options.output, response[1] + "\n")
        result.ok = true; result.diagnostic = "ok"; result
    } catch (e: IllegalArgumentException) {
        result.diagnostic = e.message; result
    } catch (_: Exception) {
        result.diagnostic = "adapter_failed"; result
    }
}

public func parseTeacherP5CodexAdapterOptions(args: Array<String>): TeacherP5CodexAdapterOptions {
    let options = TeacherP5CodexAdapterOptions()
    let seen = HashSet<String>()
    var i: Int64 = 0
    while (i < args.size) {
        if (i + 1 >= args.size || !args[i].startsWith("--") || seen.contains(args[i])) {
            throw IllegalArgumentException("invalid_adapter_arguments")
        }
        seen.add(args[i]); let value = args[i + 1].trimAscii()
        if (value == "") { throw IllegalArgumentException("invalid_adapter_arguments") }
        match (args[i]) {
            case "--request" => options.request = value
            case "--output" => options.output = value
            case "--workspace" => options.workspace = value
            case "--runtime-home" => options.runtimeHome = value
            case "--session-id" => options.sessionId = value
            case "--expected-provider" => options.expectedProvider = value
            case "--expected-model" => options.expectedModel = value
            case _ => throw IllegalArgumentException("invalid_adapter_arguments")
        }
        i += 2
    }
    if (seen.size != 7) { throw IllegalArgumentException("invalid_adapter_arguments") }
    options
}

private func p5CodexSafePaths(options: TeacherP5CodexAdapterOptions): Bool {
    if (!options.request.startsWith("/") || !options.output.startsWith("/") || !options.workspace.startsWith("/") ||
        !options.runtimeHome.startsWith("/") || options.sessionId.toRuneArray().size > 256 || options.sessionId.contains("/") ||
        options.sessionId.contains("\\") || options.sessionId.contains("..")) { return false }
    let workspace = options.workspace.trimEnd('/')
    let runtime = options.runtimeHome.trimEnd('/')
    let output = options.output
    workspace != runtime && output.startsWith(workspace + "/") && options.request.startsWith(workspace + "/") &&
        !workspace.toAsciiLower().contains("teacher-solutions") && !runtime.toAsciiLower().contains("teacher-solutions") &&
        !output.toAsciiLower().contains("ckb-data")
}

private func p5CodexReadBoundedUtf8(path: String): String {
    if (!exists(Path(path))) { throw IllegalArgumentException("input_missing") }
    let bytes = File.readFrom(Path(path))
    if (bytes.size > P5_CODEX_MAX_BYTES) { throw IllegalArgumentException("input_too_large") }
    try { String.fromUtf8(bytes) } catch (_: Exception) { throw IllegalArgumentException("invalid_response_encoding") }
}

private func p5CodexValidateRequest(raw: String): (String, String) {
    if (p5CodexForbidden(raw)) { return ("request_forbidden", "") }
    try {
        let o = JsonValue.fromStr(raw).asObject()
        if (p5CodexString(o, "schemaVersion") != P5_CODEX_REQUEST_SCHEMA || p5CodexString(o, "caseId") == "" ||
            p5CodexString(o, "runId") == "" || p5CodexString(o, "datasetVersion") == "" ||
            p5CodexInt(o, "attempt") != 1 || p5CodexString(o, "runMode") != "development" ||
            p5CodexString(o, "failureObservation") == "" || !p5CodexHash(p5CodexString(o, "resultEvidenceHash"))) {
            return ("request_contract_invalid", "")
        }
        ("ok", raw)
    } catch (_: Exception) { ("malformed_request_json", "") }
}

private func p5CodexSealResponse(raw: String): (String, String) {
    if (p5CodexForbidden(raw)) { return ("response_forbidden", "") }
    try {
        let o = JsonValue.fromStr(raw).asObject()
        let category = p5CodexString(o, "category").toAsciiLower()
        if (!p5CodexCategory(category) || !p5CodexResponseFieldsPresent(o)) { return ("response_contract_invalid", "") }
        if (category == "knowledge_gap") {
            let family = p5CodexString(o, "knowledgeFamily").toAsciiLower(); let source = p5CodexString(o, "sourceClass").toAsciiLower()
            let citation = p5CodexString(o, "citation"); let knowledge = p5CodexString(o, "knowledgeText")
            if (!p5CodexFamily(family) || (source != "official" && source != "approved_trusted") || citation == "" ||
                p5CodexString(o, "canonicalKnowledgeId") == "" || p5CodexString(o, "targetVersion") == "" ||
                p5CodexString(o, "evidenceId") == "" || knowledge == "" || !p5CodexBool(o, "reusable") ||
                !p5CodexBool(o, "purificationPassed")) { return ("response_contract_invalid", "") }
        } else if (p5CodexString(o,"knowledgeFamily")!="" || p5CodexBool(o,"reusable") || p5CodexString(o,"sourceClass")!="" ||
            p5CodexString(o,"citation")!="" || p5CodexBool(o,"purificationPassed") || p5CodexString(o,"canonicalKnowledgeId")!="" ||
            p5CodexString(o,"targetVersion")!="" || p5CodexString(o,"evidenceId")!="" || p5CodexString(o,"knowledgeText")!="") {
            return ("response_contract_invalid", "")
        }
        let knowledge=category=="knowledge_gap"
        let body="{\"schemaVersion\":\"${P5_CODEX_RESPONSE_SCHEMA}\",\"observedProvider\":\"${P5_CODEX_PROVIDER}\",\"observedModel\":\"${P5_CODEX_MODEL}\",\"category\":\"${p5CodexEscape(category)}\",\"knowledgeFamily\":\"${p5CodexEscape(if(knowledge){p5CodexString(o,"knowledgeFamily").toAsciiLower()}else{""})}\",\"reusable\":${knowledge&&p5CodexBool(o,"reusable")},\"sourceClass\":\"${p5CodexEscape(if(knowledge){p5CodexString(o,"sourceClass").toAsciiLower()}else{""})}\",\"citation\":\"${p5CodexEscape(if(knowledge){p5CodexString(o,"citation")}else{""})}\",\"purificationPassed\":${knowledge&&p5CodexBool(o,"purificationPassed")},\"canonicalKnowledgeId\":\"${p5CodexEscape(if(knowledge){p5CodexString(o,"canonicalKnowledgeId")}else{""})}\",\"targetVersion\":\"${p5CodexEscape(if(knowledge){p5CodexString(o,"targetVersion")}else{""})}\",\"evidenceId\":\"${p5CodexEscape(if(knowledge){p5CodexString(o,"evidenceId")}else{""})}\",\"knowledgeText\":\"${p5CodexEscape(if(knowledge){p5CodexString(o,"knowledgeText")}else{""})}\"}"
        ("ok",body)
    } catch (_: Exception) { ("malformed_response_json", "") }
}

private func p5CodexPrompt(request: String): String {
    "Classify the root cause of this first-attempt Cangjie evaluation failure, not merely its surface compiler or test outcome. " +
    "Use only the supplied request; do not access files, tools, hidden tests, reference solutions, Teacher solutions, or external data. " +
    "Return exactly one JSON object matching the output schema. Categories: knowledge_gap, retrieval_failure, reasoning_failure, compile_error, unit_failure, dataset_failure, runner_failure, environment_failure, tool_error, timeout, protocol_violation. " +
    "When the supplied evidence itself proves that the failure came from missing or misapplied reusable Cangjie syntax, standard-library, stdx, toolchain, diagnostic, version-migration, or engineering knowledge, choose knowledge_gap even when the observed surface is compile_error or unit_failure. " +
    "Choose compile_error or unit_failure only when the evidence does not establish an allowed reusable knowledge gap and the cause is case-specific. " +
    "All ten fields are required. For knowledge_gap, provide only reusable general knowledge with official or approved-trusted citation. " +
    "For every other category, set every knowledge string to an empty string and both reusable and purificationPassed to false. Request:\n${request}"
}

private func p5CodexOutputSchema(): String {
    "{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"category\",\"knowledgeFamily\",\"reusable\",\"sourceClass\",\"citation\",\"purificationPassed\",\"canonicalKnowledgeId\",\"targetVersion\",\"evidenceId\",\"knowledgeText\"],\"properties\":{\"category\":{\"type\":\"string\",\"enum\":[\"knowledge_gap\",\"retrieval_failure\",\"reasoning_failure\",\"compile_error\",\"unit_failure\",\"dataset_failure\",\"runner_failure\",\"environment_failure\",\"tool_error\",\"timeout\",\"protocol_violation\"]},\"knowledgeFamily\":{\"type\":\"string\"},\"reusable\":{\"type\":\"boolean\"},\"sourceClass\":{\"type\":\"string\"},\"citation\":{\"type\":\"string\"},\"purificationPassed\":{\"type\":\"boolean\"},\"canonicalKnowledgeId\":{\"type\":\"string\"},\"targetVersion\":{\"type\":\"string\"},\"evidenceId\":{\"type\":\"string\"},\"knowledgeText\":{\"type\":\"string\"}}}"
}

private func p5CodexResponseFieldsPresent(o:JsonObject):Bool{for(k in ["category","knowledgeFamily","reusable","sourceClass","citation","purificationPassed","canonicalKnowledgeId","targetVersion","evidenceId","knowledgeText"]){match(o.get(k)){case Some(_)=>();case None=>return false}};true}

private func p5CodexForbidden(value: String): Bool { let v=value.toAsciiLower(); v.contains("teacher-solutions")||v.contains("canonical_solution")||v.contains("hidden_test")||v.contains("hidden-test")||v.contains("/reference/")||v.contains("authorization:")||v.contains("api_key")||v.contains("token=")||v.contains("password") }
private func p5CodexCategory(v:String):Bool{v=="knowledge_gap"||v=="retrieval_failure"||v=="reasoning_failure"||v=="compile_error"||v=="unit_failure"||v=="dataset_failure"||v=="runner_failure"||v=="environment_failure"||v=="tool_error"||v=="timeout"||v=="protocol_violation"}
private func p5CodexFamily(v:String):Bool{v=="syntax"||v=="standard_library"||v=="stdx"||v=="toolchain"||v=="compiler_diagnostic"||v=="version_migration"||v=="engineering_practice"}
private func p5CodexHash(v:String):Bool{let r=v.toRuneArray();if(r.size!=71||!v.startsWith("sha256:")){return false};for(i in 7..71){let c=r[i];if(!((c>=r'0'&&c<=r'9')||(c>=r'a'&&c<=r'f'))){return false}};true}
private func p5CodexString(o:JsonObject,k:String):String{match(o.get(k)){case Some(v)=>v.asString().getValue().trimAscii();case None=>""}}
private func p5CodexInt(o:JsonObject,k:String):Int64{match(o.get(k)){case Some(v)=>v.asInt().getValue();case None=>0}}
private func p5CodexBool(o:JsonObject,k:String):Bool{match(o.get(k)){case Some(v)=>v.asBool().getValue();case None=>false}}
private func p5CodexEscape(v:String):String{v.replace("\\","\\\\").replace("\"","\\\"").replace("\n","\\n").replace("\r","\\r").replace("\t","\\t")}
