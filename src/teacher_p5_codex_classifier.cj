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
        if (!exists(Path(options.workspace))) { Directory.create(Path(options.workspace), recursive: true) }
        if (!exists(Path(options.runtimeHome))) { Directory.create(Path(options.runtimeHome), recursive: true) }
        if (!removeP5CodexClassifierDiagnostic(options)) {
            return failP5CodexClassifier(result, options, "diagnostic_reset_failed")
        }
        try {
            let requestText = p5CodexReadBoundedUtf8(options.request,
                missingDiagnostic: "request_contract_invalid", tooLargeDiagnostic: "request_too_large")
            let request = p5CodexValidateRequest(requestText)
            if (request[0] != "ok") { return failP5CodexClassifier(result, options, request[0]) }
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
            if (process.timedOut) { return failP5CodexClassifier(result, options, "codex_timeout") }
            if (process.exitCode != 0) { return failP5CodexClassifier(result, options, "codex_nonzero_exit") }
            let raw = p5CodexReadBoundedUtf8(modelOutput,
                missingDiagnostic: "missing_or_duplicate_terminal_result",
                tooLargeDiagnostic: "classifier_output_too_large")
            let response = p5CodexSealResponse(raw)
            if (response[0] != "ok") { return failP5CodexClassifier(result, options, response[0]) }
            let factDiagnostic=p5CodexResponseFactsDiagnostic(requestText,response[1])
            if(factDiagnostic!="ok"){return failP5CodexClassifier(result,options,factDiagnostic)}
            try { _ = teacherAtomicWrite(options.output, response[1] + "\n") }
            catch (_: Exception) { return failP5CodexClassifier(result, options, "response_write_failed") }
            if (!removeP5CodexClassifierDiagnostic(options)) {
                return failP5CodexClassifier(result, options, "diagnostic_reset_failed")
            }
            result.ok = true; result.diagnostic = "ok"; result
        } catch (e: IllegalArgumentException) {
            failP5CodexClassifier(result, options, e.message)
        } catch (_: Exception) {
            failP5CodexClassifier(result, options, "classifier_failure_unknown")
        }
    } catch (e: IllegalArgumentException) {
        result.diagnostic = e.message; result
    } catch (_: Exception) {
        result.diagnostic = "adapter_failed"; result
    }
}

private func failP5CodexClassifier(result: TeacherP5CodexAdapterResult,
    options: TeacherP5CodexAdapterOptions, diagnostic: String): TeacherP5CodexAdapterResult {
    let mapped = p5CodexClassifierSharedDiagnostic(diagnostic)
    let safe = if (p5CodexClassifierDiagnosticAllowed(mapped)) { mapped } else { "classifier_failure_unknown" }
    let payload = "{\"schemaVersion\":\"cangjie-teacher-classifier-diagnostic-v1\",\"diagnostic\":\"${safe}\"}\n"
    try {
        _ = teacherAtomicWrite(Path(options.workspace).join("classifier-diagnostic.json").toString(), payload)
        result.diagnostic = safe
    } catch (_: Exception) { result.diagnostic = "diagnostic_write_failed" }
    result
}

private func removeP5CodexClassifierDiagnostic(options: TeacherP5CodexAdapterOptions): Bool {
    let path = Path(options.workspace).join("classifier-diagnostic.json")
    try { if (exists(path)) { remove(path) }; !exists(path) } catch (_: Exception) { false }
}

private func p5CodexClassifierDiagnosticAllowed(value: String): Bool {
    ["invalid_response_encoding", "request_too_large", "request_contract_invalid", "classifier_timeout",
        "classifier_process_failed", "classifier_output_too_large", "missing_or_duplicate_terminal_result",
        "response_contract_invalid", "response_contains_forbidden_data", "malformed_structured_output",
        "classifier_response_source_fact_unsupported", "response_write_failed", "diagnostic_reset_failed",
        "classifier_reserved_match_plain_missing", "classifier_reserved_match_raw_missing",
        "classifier_reserved_match_rename_missing", "classifier_reserved_match_contradictory",
        "classifier_reserved_match_comment_disguised", "classifier_string_case_iteration_uint8_missing",
        "classifier_string_case_string_ascii_api_missing", "classifier_string_case_rune_ascii_api_missing",
        "classifier_string_case_unicode_import_missing", "classifier_string_case_unicode_rune_api_missing",
        "classifier_string_case_unicode_return_type_missing", "classifier_string_case_invalid_api_negative_missing",
        "classifier_string_case_contradictory", "classifier_string_case_comment_disguised",
        "classifier_failure_unknown"].contains(value)
}

private func p5CodexClassifierSharedDiagnostic(value: String): String {
    match (value) {
        case "codex_timeout" => "classifier_timeout"
        case "codex_nonzero_exit" => "classifier_process_failed"
        case "request_forbidden" => "request_contract_invalid"
        case "malformed_request_json" => "request_contract_invalid"
        case "response_forbidden" => "response_contains_forbidden_data"
        case "malformed_response_json" => "malformed_structured_output"
        case _ => value
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

private func p5CodexReadBoundedUtf8(path: String, missingDiagnostic!: String,
    tooLargeDiagnostic!: String): String {
    if (!exists(Path(path))) { throw IllegalArgumentException(missingDiagnostic) }
    let bytes = File.readFrom(Path(path))
    if (bytes.size > P5_CODEX_MAX_BYTES) { throw IllegalArgumentException(tooLargeDiagnostic) }
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
    "All ten fields are required. For knowledge_gap, knowledgeFamily must be exactly one of syntax, standard_library, stdx, toolchain, compiler_diagnostic, version_migration, engineering_practice; sourceClass must be exactly official; citation must be an HTTPS URL under https://docs.cangjie-lang.cn/ (use https://docs.cangjie-lang.cn/docs/1.0.0/ when the request has no more specific official URL); targetVersion must be 1.0.0 for this dataset; evidenceId must bind the supplied resultEvidenceHash; canonicalKnowledgeId must identify general knowledge and must not contain the case id. " +
    "Provide only reusable general knowledge, never the case answer or solution. " +
    p5CodexGroundingPrompt(request) +
    "For every other category, set every knowledge string to an empty string and both reusable and purificationPassed to false. Request:\n${request}"
}

private func p5CodexGroundingPrompt(request:String):String{
    try{
        let o=JsonValue.fromStr(request).asObject()
        let source=p5CodexString(o,"studentSourceExcerpt").toAsciiLower()
        let compiler=p5CodexString(o,"compilerTestSummary").toAsciiLower()
        if(p5CodexStringCaseFailure(source,compiler)){
            "For this visible String casing failure, use these exact Cangjie 1.0 facts: direct String iteration yields UInt8 bytes; String.toAsciiLower() returns a String and is ASCII-only; Rune.toAsciiLowerCase() returns a Rune and is ASCII-only; Unicode casing requires import std.unicode.* and Rune.toLowerCase() returns a Rune. String.toLower() is unavailable and toLowerAscii is not a Cangjie API. The knowledgeText must contain the exact clause: Unicode casing requires import std.unicode.*. The knowledgeText must contain the exact invalid API clause: String.toLower() is unavailable and toLowerAscii is not a Cangjie API. Do not replace these relationships with generic casing advice. "
        }else if(p5CodexReservedMatchFailure(source,compiler)){
            "For this visible reserved-keyword failure, use all of these exact Cangjie 1.0 facts: `match` is invalid as a plain identifier; the backtick form `match` is a legal raw identifier; alternatively, rename it to a non-keyword name. The knowledgeText must contain the exact clause: The backtick form `match` is a legal raw identifier. The knowledgeText must also contain the exact clause: `match` is invalid as a plain identifier. It must also state that renaming to a non-keyword name is valid. Never claim that `match` is forbidden as every kind of identifier. "
        }else{""}
    }catch(_:Exception){""}
}

private func p5CodexResponseFactsDiagnostic(requestText:String,responseText:String):String{
    try{
        let request=JsonValue.fromStr(requestText).asObject();let response=JsonValue.fromStr(responseText).asObject()
        if(p5CodexString(response,"category").toAsciiLower()!="knowledge_gap"){return "ok"}
        let source=p5CodexString(request,"studentSourceExcerpt").toAsciiLower()
        let compiler=p5CodexString(request,"compilerTestSummary").toAsciiLower()
        let knowledge=p5CodexString(response,"knowledgeText").toAsciiLower()
        if(p5CodexStringCaseFailure(source,compiler)){
            return p5CodexStringCaseFactsDiagnostic(knowledge)
        }
        if(p5CodexReservedMatchFailure(source,compiler)){return p5CodexReservedMatchFactsDiagnostic(knowledge)}
        "ok"
    }catch(_:Exception){"classifier_response_source_fact_unsupported"}
}

private func p5CodexReservedMatchFailure(source:String,compiler:String):Bool{
    source.contains("var match")&&compiler.contains("expected identifier")&&compiler.contains("found keyword 'match'")
}

private func p5CodexReservedMatchFactsDiagnostic(knowledge:String):String{
    if(knowledge.contains("//")||knowledge.contains("/*")||knowledge.contains("*/")){
        return "classifier_reserved_match_comment_disguised"
    }
    if(knowledge.contains("cannot be used as a local variable identifier")||
        knowledge.contains("cannot be used as a variable name or identifier")||
        knowledge.contains("cannot be used as an identifier")){
        return "classifier_reserved_match_contradictory"
    }
    let plainScope=knowledge.contains("plain identifier")||knowledge.contains("ordinary identifier")||knowledge.contains("regular identifier")
    let plainInvalid=knowledge.contains("`match`")&&knowledge.contains("keyword")&&plainScope&&
        (knowledge.contains("invalid")||knowledge.contains("not valid")||knowledge.contains("cannot be used"))
    if(!plainInvalid){return "classifier_reserved_match_plain_missing"}
    let rawLegal=(knowledge.contains("backtick form `match`")&&knowledge.contains("legal raw identifier"))||
        (knowledge.contains("raw identifier `match`")&&(knowledge.contains("is legal")||knowledge.contains("is valid")))||
        knowledge.contains("`match` is a legal raw identifier")||knowledge.contains("`match` is a valid raw identifier")||
        (knowledge.contains("as a raw identifier")&&knowledge.contains("`match` is valid"))
    if(!rawLegal){return "classifier_reserved_match_raw_missing"}
    let rename=knowledge.contains("rename")||knowledge.contains("renaming")||knowledge.contains("different variable name")||
        knowledge.contains("non-keyword name")
    if(!rename){return "classifier_reserved_match_rename_missing"}
    "ok"
}

private func p5CodexStringCaseFailure(source:String,compiler:String):Bool{
    source.contains(".tolower(")&&compiler.contains("'tolower' is not a member")&&compiler.contains("'string'")
}

private func p5CodexStringCaseFactsDiagnostic(knowledge:String):String{
    if(knowledge.contains("//")||knowledge.contains("/*")||knowledge.contains("*/")){
        return "classifier_string_case_comment_disguised"
    }
    let value=knowledge.replace("`", "")
    let iterationUInt8=value.contains("string iteration yields uint8")||
        value.contains("iterating a string yields uint8")||value.contains("string iteration produces uint8")
    let iterationRune=value.contains("string iteration yields rune")||
        value.contains("iterating a string yields rune")||value.contains("string iteration produces rune")
    let contradictory=iterationRune||value.contains("rune.tolowerascii")||value.contains("string.tolowerascii")||
        value.contains("string.toasciilowercase")||value.contains("rune.toasciilower(")||
        value.contains("use tolowerascii")||value.contains("call tolowerascii")||value.contains("tolowerascii returns")||
        value.contains("tolowerascii is available")||value.contains("use string.tolower")||value.contains("call string.tolower")||
        value.contains("string.tolower() is available")||value.contains("string supports string.tolower")||
        value.contains("string provides string.tolower")
    if(contradictory){return "classifier_string_case_contradictory"}
    if(!iterationUInt8){return "classifier_string_case_iteration_uint8_missing"}
    let stringAscii=value.contains("string.toasciilower()")&&value.contains("ascii-only")&&
        (value.contains("returns a string")||value.contains(": string"))
    if(!stringAscii){return "classifier_string_case_string_ascii_api_missing"}
    let runeAscii=value.contains("rune.toasciilowercase()")&&value.contains("ascii-only")&&
        (value.contains("returns a rune")||value.contains(": rune"))
    if(!runeAscii){return "classifier_string_case_rune_ascii_api_missing"}
    if(!value.contains("unicode")||!p5CodexUnicodeImportRequired(value)){
        return "classifier_string_case_unicode_import_missing"
    }
    if(!value.contains("rune.tolowercase()")){return "classifier_string_case_unicode_rune_api_missing"}
    if(!p5CodexRuneLowerResultValid(value)){return "classifier_string_case_unicode_return_type_missing"}
    let genericUnavailable=value.contains("string.tolower()")&&
        (value.contains("unavailable")||value.contains("does not provide")||value.contains("not a member")||value.contains("does not exist"))
    if(!genericUnavailable||!p5CodexToLowerAsciiClaimValid(value)){
        return "classifier_string_case_invalid_api_negative_missing"
    }
    "ok"
}

private func p5CodexToLowerAsciiClaimValid(knowledge:String):Bool{
    if(!knowledge.contains("tolowerascii")){return true}
    if(knowledge.contains("//")||knowledge.contains("/*")||knowledge.contains("*/")){return false}
    let denied=knowledge.contains("tolowerascii is not a cangjie api")||
        knowledge.contains("tolowerascii is unavailable")||knowledge.contains("tolowerascii does not exist")
    if(!denied){return false}
    !(knowledge.contains("use tolowerascii")||knowledge.contains("call tolowerascii")||
        knowledge.contains("tolowerascii returns")||knowledge.contains("tolowerascii is available")||
        knowledge.contains("rune.tolowerascii")||knowledge.contains("string.tolowerascii"))
}

private func p5CodexUnicodeImportRequired(knowledge:String):Bool{
    for(clause in knowledge.replace(";", ". ").split(". ")){
        let value=clause.trimAscii()
        if(!value.contains("std.unicode")){continue}
        if(value.contains("//")||value.contains("/*")||value.contains("*/")){return false}
        if(value.contains("requires import std.unicode")||value.contains("requires importing std.unicode")){return true}
    }
    false
}

private func p5CodexRuneLowerResultValid(knowledge:String):Bool{
    for(clause in knowledge.replace(";", ". ").split(". ")){
        let value=clause.trimAscii()
        if(!value.contains("rune.tolowercase()")){continue}
        if(value.contains("//")||value.contains("/*")||value.contains("*/")){return false}
        if(value.contains("rune.tolowercase() returns a rune")||
            value.contains("rune.tolowercase() produces a rune")||
            value.contains("rune.tolowercase() result is a rune")||
            value.contains("result of rune.tolowercase() is a rune")||
            value.contains("rune.tolowercase(): rune")){return true}
    }
    false
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
