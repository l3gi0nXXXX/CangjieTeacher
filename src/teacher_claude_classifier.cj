package cangjie_teacher

import std.collection.*
import std.env.getVariables
import std.fs.*
import std.io.StringReader
import std.process.*
import std.time.*
import stdx.encoding.json.*

private let CLAUDE_CLASSIFIER_PROVIDER = "claude-code"
private let CLAUDE_CLASSIFIER_MODEL = "GLM-5.2"
private let CLAUDE_CLASSIFIER_REQUEST_SCHEMA = "ckb-p5-classifier-request-v1"
private let CLAUDE_CLASSIFIER_RESPONSE_SCHEMA = "ckb-p5-classifier-response-v1"
private let CLAUDE_CLASSIFIER_MAX_BYTES: Int64 = 1048576
private let CLAUDE_CLASSIFIER_TIMEOUT_MILLIS: Int64 = 1800000

public class ClaudeClassifierRunResult {
    public var ok = false
    public var diagnostic = "not_started"
    public init() {}
}

// Claude's stderr is intentionally consumed but never mixed into the strict JSON
// protocol stream and never persisted, since it may contain provider diagnostics.
private class NativeClaudeClassifierExecutor <: TeacherCommandExecutor {
    public init() {}
    public func execute(spec:TeacherCommandSpec):TeacherProcessResult{
        let environment=HashMap<String,String>();for((key,value) in getVariables()){environment[key]=value};for(entry in spec.env){environment[entry[0]]=entry[1]}
        try{
            let process=launch(spec.executable,spec.args,stdOut:ProcessRedirect.Pipe,stdErr:ProcessRedirect.Pipe,
                workingDirectory:Some(Path(spec.cwd)),environment:Some(environment))
            let stdout=spawn{try{StringReader(process.stdOutPipe).readToEnd()}catch(_:Exception){"invalid_response_encoding"}}
            let stderr=spawn{try{StringReader(process.stdErrPipe).readToEnd()}catch(_:Exception){""}}
            try{let code=process.wait(timeout:Some(Duration.millisecond*spec.timeoutMillis));let output=stdout.get();_=stderr.get();TeacherProcessResult(code,output)}
            catch(_:TimeoutException){try{process.terminate(force:true)}catch(_:Exception){};try{_=stdout.get();_=stderr.get()}catch(_:Exception){};TeacherProcessResult(124,"",timedOut:true)}
        }catch(_:Exception){TeacherProcessResult(127,"")}
    }
}

private class ClaudeClassifierOptions {
    var request = ""; var output = ""; var workspace = ""; var runtimeHome = ""; var sessionId = ""
    var expectedProvider = ""; var expectedModel = ""
    init() {}
}

public func runClaudeClassifierAdapter(args: Array<String>,
    executor!: TeacherCommandExecutor = NativeClaudeClassifierExecutor()): ClaudeClassifierRunResult {
    let result = ClaudeClassifierRunResult()
    let parsed = parseClaudeClassifierOptions(args)
    if (parsed[1] != "ok") { result.diagnostic = parsed[1]; return result }
    let options = parsed[0]
    if (options.expectedProvider != CLAUDE_CLASSIFIER_PROVIDER || options.expectedModel != CLAUDE_CLASSIFIER_MODEL) {
        result.diagnostic = "expected_identity_not_allowed"; return result
    }
    if (!claudeClassifierPathsValid(options)) { result.diagnostic = "classifier_path_boundary_invalid"; return result }
    if (!removeClaudeClassifierDiagnostic(options)) { return failClaudeClassifier(result, options, "diagnostic_reset_failed") }
    let request = try { readClaudeClassifierUtf8(options.request) } catch (e: IllegalArgumentException) {
        return failClaudeClassifier(result, options, e.message)
    }
    if (request.toArray().size > CLAUDE_CLASSIFIER_MAX_BYTES) { return failClaudeClassifier(result, options, "request_too_large") }
    if (!validClaudeClassifierRequest(request)) { return failClaudeClassifier(result, options, "request_contract_invalid") }
    let schema = claudeClassifierJsonSchema()
    let prompt = "Classify the root cause of this Cangjie benchmark failure using only the supplied JSON; do not merely repeat its surface compiler or test outcome. " +
        "When the supplied evidence itself proves missing or misapplied reusable Cangjie syntax, standard-library, stdx, toolchain, diagnostic, version-migration, or engineering knowledge, choose knowledge_gap even when failureObservation is compile_error or unit_failure. " +
        "Choose compile_error or unit_failure only when the evidence does not establish an allowed reusable knowledge gap and the cause is case-specific. " +
        "For knowledge_gap, knowledgeFamily must be exactly one of syntax, standard_library, stdx, toolchain, compiler_diagnostic, version_migration, engineering_practice; sourceClass must be exactly official; citation must be an HTTPS URL under https://docs.cangjie-lang.cn/ (use https://docs.cangjie-lang.cn/docs/1.0.0/ when no more specific official URL is supplied); targetVersion must be 1.0.0; evidenceId must bind resultEvidenceHash; canonicalKnowledgeId must be general and must not contain the case id. " +
        "Provide only general reusable knowledge; otherwise leave all knowledge fields empty and both booleans false. " +
        "Never assert an import or dependency prerequisite unless the request's visible failureObservation or compilerTestSummary explicitly proves the same package and prerequisite. " +
        claudeClassifierGroundingPrompt(request) +
        "Return one schema-valid object. Never infer or reveal hidden tests, reference answers, credentials, or local paths. Request:\n" + request
    let cli = executor.execute(TeacherCommandSpec("claude", ["-p", prompt, "--model", CLAUDE_CLASSIFIER_MODEL,
        "--json-schema", schema, "--output-format", "json", "--effort", "low", "--no-session-persistence",
        "--bare", "--disable-slash-commands", "--strict-mcp-config",
        "--mcp-config", "{\"mcpServers\":{}}", "--tools", ""],
        options.workspace, env: [("HOME", options.runtimeHome), ("CLAUDE_CONFIG_DIR", options.runtimeHome),
            ("CANGJIE_TEACHER_SESSION", options.sessionId)], timeoutMillis: CLAUDE_CLASSIFIER_TIMEOUT_MILLIS))
    if (cli.timedOut) { return failClaudeClassifier(result, options, "classifier_timeout") }
    if (cli.exitCode != 0) { return failClaudeClassifier(result, options, "classifier_process_failed") }
    if (cli.output == "invalid_response_encoding") { return failClaudeClassifier(result, options, "invalid_response_encoding") }
    if (cli.output.toArray().size > CLAUDE_CLASSIFIER_MAX_BYTES) { return failClaudeClassifier(result, options, "classifier_output_too_large") }
    let decoded = decodeClaudeClassifierTerminalJson(cli.output)
    if (decoded[1] != "ok") { return failClaudeClassifier(result, options, decoded[1]) }
    let factDiagnostic=claudeClassifierResponseFactsDiagnostic(request,decoded[0])
    if(factDiagnostic!="ok"){return failClaudeClassifier(result,options,factDiagnostic)}
    try {
        _ = teacherAtomicWrite(options.output, decoded[0] + "\n")
        if (readClaudeClassifierUtf8(options.output) != decoded[0] + "\n") { return failClaudeClassifier(result, options, "response_write_failed") }
    } catch (_: Exception) { return failClaudeClassifier(result, options, "response_write_failed") }
    if (!removeClaudeClassifierDiagnostic(options)) { return failClaudeClassifier(result, options, "diagnostic_reset_failed") }
    result.ok = true; result.diagnostic = "ok"; result
}

private func failClaudeClassifier(result:ClaudeClassifierRunResult,options:ClaudeClassifierOptions,diagnostic:String):ClaudeClassifierRunResult{
    let safe=if(claudeClassifierDiagnosticAllowed(diagnostic)){diagnostic}else{"classifier_failure_unknown"}
    let payload="{\"schemaVersion\":\"cangjie-teacher-classifier-diagnostic-v1\",\"diagnostic\":\"${safe}\"}\n"
    try{_=teacherAtomicWrite(Path(options.workspace).join("classifier-diagnostic.json").toString(),payload);result.diagnostic=safe}
    catch(_:Exception){result.diagnostic="diagnostic_write_failed"};result
}
private func removeClaudeClassifierDiagnostic(options:ClaudeClassifierOptions):Bool{
    let path=Path(options.workspace).join("classifier-diagnostic.json")
    try{if(exists(path)){remove(path)};!exists(path)}catch(_:Exception){false}
}
private func claudeClassifierDiagnosticAllowed(value:String):Bool{
    ["invalid_response_encoding","request_too_large","request_contract_invalid","classifier_timeout","classifier_process_failed",
        "classifier_output_too_large","malformed_stream_json","malformed_terminal_json","duplicate_init",
        "classifier_unsuccessful_result","missing_init",
        "observed_model_mismatch","missing_or_duplicate_terminal_result","response_contract_invalid","response_contains_forbidden_data",
        "malformed_structured_output","classifier_response_source_fact_unsupported","response_write_failed","diagnostic_reset_failed",
        "classifier_reserved_match_plain_missing","classifier_reserved_match_raw_missing",
        "classifier_reserved_match_rename_missing","classifier_reserved_match_contradictory",
        "classifier_reserved_match_comment_disguised","classifier_string_case_iteration_uint8_missing",
        "classifier_string_case_string_ascii_api_missing","classifier_string_case_rune_ascii_api_missing",
        "classifier_string_case_unicode_import_missing","classifier_string_case_unicode_rune_api_missing",
        "classifier_string_case_unicode_return_type_missing","classifier_string_case_invalid_api_negative_missing",
        "classifier_string_case_contradictory","classifier_string_case_comment_disguised",
        "classifier_string_case_solution_leakage",
        "classifier_failure_unknown"].contains(value)
}

private func parseClaudeClassifierOptions(args: Array<String>): (ClaudeClassifierOptions, String) {
    let names = ["--request", "--output", "--workspace", "--runtime-home", "--session-id", "--expected-provider", "--expected-model"]
    let values = ArrayList<String>(); for (_ in names) { values.add("") }
    var i: Int64 = 0
    while (i < args.size) {
        var found: Int64 = -1; for (j in 0..names.size) { if (args[i] == names[j]) { found = j; break } }
        if (found < 0 || i + 1 >= args.size || args[i + 1].trimAscii() == "") { return (ClaudeClassifierOptions(), "unknown_or_missing_argument") }
        if (values[found] != "") { return (ClaudeClassifierOptions(), "duplicate_argument") }
        values[found] = args[i + 1].trimAscii(); i += 2
    }
    for (value in values) { if (value == "") { return (ClaudeClassifierOptions(), "arguments_incomplete") } }
    let o = ClaudeClassifierOptions(); o.request=values[0];o.output=values[1];o.workspace=values[2];o.runtimeHome=values[3]
    o.sessionId=values[4];o.expectedProvider=values[5];o.expectedModel=values[6];(o,"ok")
}

private func claudeClassifierPathsValid(o: ClaudeClassifierOptions): Bool {
    try {
        let workspace = canonicalize(Path(o.workspace)).toString(); let home = canonicalize(Path(o.runtimeHome)).toString()
        let request = canonicalize(Path(o.request)).toString(); let outputParent = canonicalize(Path(o.output).parent).toString()
        workspace.startsWith("/") && home.startsWith("/") && workspace != home && request.startsWith(workspace + "/") &&
            outputParent == workspace && o.request != o.output && !o.output.contains("..") && o.sessionId.toRuneArray().size <= 256
    } catch (_: Exception) { false }
}

private func readClaudeClassifierUtf8(path: String): String {
    try { String.fromUtf8(File.readFrom(Path(path))) } catch (_: Exception) { throw IllegalArgumentException("invalid_response_encoding") }
}

private func validClaudeClassifierRequest(raw: String): Bool {
    try {
        let o=JsonValue.fromStr(raw).asObject()
        classifierString(o,"schemaVersion")==CLAUDE_CLASSIFIER_REQUEST_SCHEMA && classifierString(o,"caseId")!="" &&
            classifierString(o,"runId")!="" && classifierString(o,"datasetVersion")!="" && classifierInt(o,"attempt")==1 &&
            classifierString(o,"runMode")=="development" && classifierString(o,"resultEvidenceHash")!="" &&
            !claudeClassifierForbidden(raw)
    } catch (_: Exception) { false }
}

private func claudeClassifierGroundingPrompt(request:String):String{
    try{
        let o=JsonValue.fromStr(request).asObject();let source=classifierString(o,"studentSourceExcerpt").toAsciiLower()
        let compiler=classifierString(o,"compilerTestSummary").toAsciiLower()
        if(claudeClassifierStringCaseFailure(source,compiler)){
            "For this visible String casing failure, use these exact Cangjie 1.0 facts: direct String iteration yields UInt8 bytes; String.toAsciiLower() returns a String and is ASCII-only; Rune.toAsciiLowerCase() returns a Rune and is ASCII-only; Unicode casing requires import std.unicode.* and Rune.toLowerCase() returns a Rune. String.toLower() is unavailable and toLowerAscii is not a Cangjie API. The knowledgeText must contain the exact clause: Unicode casing requires import std.unicode.*. The knowledgeText must contain the exact invalid API clause: String.toLower() is unavailable and toLowerAscii is not a Cangjie API. Do not replace these relationships with generic casing advice. Do not include the task-specific counting algorithm or implementation strategy in knowledgeText. "
        }else if(claudeClassifierReservedMatchFailure(source,compiler)){
            "For this visible reserved-keyword failure, use all of these exact Cangjie 1.0 facts: `match` is invalid as a plain identifier; the backtick form `match` is a legal raw identifier; alternatively, rename it to a non-keyword name. The knowledgeText must contain the exact clause: The backtick form `match` is a legal raw identifier. The knowledgeText must also contain the exact clause: `match` is invalid as a plain identifier. It must also state that renaming to a non-keyword name is valid. Never claim that `match` is forbidden as every kind of identifier. "
        }else if(source.contains(".abs(")&&compiler.contains("undeclared identifier 'abs'")){
            "For this visible receiver-style absolute-value failure, do not infer any package or import; if classifying a knowledge gap, state that receiver .abs() is unavailable and use the global documented abs(value) form. "
        }else{""}
    }catch(_:Exception){""}
}

private func claudeClassifierResponseFactsDiagnostic(requestText:String,responseText:String):String{
    try{
        let request=JsonValue.fromStr(requestText).asObject();let response=JsonValue.fromStr(responseText).asObject()
        if(classifierString(response,"category").toAsciiLower()!="knowledge_gap"){return "ok"}
        let knowledge=classifierString(response,"knowledgeText").toAsciiLower()
        let source=classifierString(request,"studentSourceExcerpt").toAsciiLower()
        let compiler=classifierString(request,"compilerTestSummary").toAsciiLower()
        let task=classifierString(request,"taskText").toAsciiLower()
        if(claudeClassifierStringCaseFailure(source,compiler)){
            if(!claudeClassifierContainsComment(knowledge)&&claudeClassifierDistinctCaseCountGoal(task)&&
                claudeClassifierDistinctCaseCountSolution(knowledge)){
                return "classifier_string_case_solution_leakage"
            }
            return claudeClassifierStringCaseFactsDiagnostic(knowledge)
        }
        if(claudeClassifierReservedMatchFailure(source,compiler)){
            return claudeClassifierReservedMatchFactsDiagnostic(knowledge)
        }
        if(source.contains(".abs(")&&compiler.contains("undeclared identifier 'abs'")){
            let receiverUnavailable=knowledge.contains("receiver")&&knowledge.contains(".abs(")&&
                (knowledge.contains("unavailable")||knowledge.contains("does not provide")||knowledge.contains("no member"))
            let globalForm=knowledge.contains("global")&&knowledge.contains("abs(value)")
            if(!receiverUnavailable||!globalForm||!claudeClassifierPackageTokens(knowledge).isEmpty()||claudeClassifierAssertsPrerequisite(knowledge)){return "classifier_response_source_fact_unsupported"}
        }
        if(!claudeClassifierAssertsPrerequisite(knowledge)){return "ok"}
        let evidence=(classifierString(request,"failureObservation")+" "+compiler).toAsciiLower()
        if(!claudeClassifierMissingPrerequisiteEvidence(evidence)){return "classifier_response_source_fact_unsupported"}
        for(packageName in claudeClassifierPackageTokens(knowledge)){if(!evidence.contains(packageName)){return "classifier_response_source_fact_unsupported"}}
        "ok"
    }catch(_:Exception){"classifier_response_source_fact_unsupported"}
}

private func claudeClassifierReservedMatchFailure(source:String,compiler:String):Bool{
    source.contains("var match")&&compiler.contains("expected identifier")&&compiler.contains("found keyword 'match'")
}

private func claudeClassifierReservedMatchFactsDiagnostic(knowledge:String):String{
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

private func claudeClassifierStringCaseFailure(source:String,compiler:String):Bool{
    source.contains(".tolower(")&&compiler.contains("'tolower' is not a member")&&compiler.contains("'string'")
}

private func claudeClassifierContainsComment(value:String):Bool{
    value.contains("//")||value.contains("/*")||value.contains("*/")
}

private func claudeClassifierDistinctCaseCountGoal(value:String):Bool{
    let count=value.contains("count")||value.contains("how many")||value.contains("number of")||
        value.contains("统计")||value.contains("计数")
    let distinct=value.contains("distinct")||value.contains("unique")||value.contains("不同")||
        value.contains("唯一")||value.contains("不重复")
    let character=value.contains("character")||value.contains("字符")
    let insensitive=value.contains("case-insensitive")||value.contains("case insensitive")||
        value.contains("case insensitively")||value.contains("regardless of case")||value.contains("ignore case")||
        value.contains("ignoring case")||value.contains("不区分大小写")||value.contains("忽略大小写")
    count&&distinct&&character&&insensitive
}

private func claudeClassifierDistinctCaseCountSolution(knowledge:String):Bool{
    if(!claudeClassifierDistinctCaseCountGoal(knowledge)){return false}
    knowledge.contains("hashset")||knowledge.contains("hash set")||knowledge.contains("collect ")||
        knowledge.contains("collect into")||knowledge.contains("collecting")||knowledge.contains("collected")||
        knowledge.contains("iterate over")||knowledge.contains("iterating over")||knowledge.contains("loop")||
        knowledge.contains("for (")||knowledge.contains("torunearray")||knowledge.contains("normalize case")||
        knowledge.contains("遍历")||knowledge.contains("循环")||knowledge.contains("收集")||
        (knowledge.contains("先")&&knowledge.contains("再"))||
        (knowledge.contains("first ")&&knowledge.contains(" then "))
}

private func claudeClassifierStringCaseFactsDiagnostic(knowledge:String):String{
    if(claudeClassifierContainsComment(knowledge)){
        return "classifier_string_case_comment_disguised"
    }
    let value=knowledge.replace("`", "")
    let iterationUInt8=(value.contains("string iteration yields uint8")||
        value.contains("iterating a string yields uint8")||value.contains("string iteration produces uint8"))
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
    if(!value.contains("unicode")||!claudeClassifierUnicodeImportRequired(value)){
        return "classifier_string_case_unicode_import_missing"
    }
    if(!value.contains("rune.tolowercase()")){return "classifier_string_case_unicode_rune_api_missing"}
    if(!claudeClassifierRuneLowerResultValid(value)){return "classifier_string_case_unicode_return_type_missing"}
    let genericUnavailable=value.contains("string.tolower()")&&
        (value.contains("unavailable")||value.contains("does not provide")||value.contains("not a member")||value.contains("does not exist"))
    if(!genericUnavailable||!claudeClassifierToLowerAsciiClaimValid(value)){
        return "classifier_string_case_invalid_api_negative_missing"
    }
    "ok"
}

private func claudeClassifierToLowerAsciiClaimValid(knowledge:String):Bool{
    if(!knowledge.contains("tolowerascii")){return true}
    if(knowledge.contains("//")||knowledge.contains("/*")||knowledge.contains("*/")){return false}
    let denied=knowledge.contains("tolowerascii is not a cangjie api")||
        knowledge.contains("tolowerascii is unavailable")||knowledge.contains("tolowerascii does not exist")
    if(!denied){return false}
    !(knowledge.contains("use tolowerascii")||knowledge.contains("call tolowerascii")||
        knowledge.contains("tolowerascii returns")||knowledge.contains("tolowerascii is available")||
        knowledge.contains("rune.tolowerascii")||knowledge.contains("string.tolowerascii"))
}

private func claudeClassifierUnicodeImportRequired(knowledge:String):Bool{
    for(clause in knowledge.replace(";", ". ").split(". ")){
        let value=clause.trimAscii()
        if(!value.contains("std.unicode")){continue}
        if(value.contains("//")||value.contains("/*")||value.contains("*/")){return false}
        if(value.contains("requires import std.unicode")||value.contains("requires importing std.unicode")){return true}
    }
    false
}

private func claudeClassifierRuneLowerResultValid(knowledge:String):Bool{
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

private func claudeClassifierMissingPrerequisiteEvidence(evidence:String):Bool{
    evidence.contains("missing dependency")||evidence.contains("missing package")||evidence.contains("missing import")||
        evidence.contains("not declared as a dependency")||evidence.contains("not added as a dependency")||
        evidence.contains("cannot find package")||evidence.contains("cannot find module")||
        evidence.contains("undeclared package")||evidence.contains("undeclared module")||
        ((evidence.contains("package")||evidence.contains("module")||evidence.contains("dependency"))&&evidence.contains("not found"))
}

private func claudeClassifierAssertsPrerequisite(knowledge:String):Bool{
    let denies=knowledge.contains("import is unnecessary")||knowledge.contains("import is not required")||
        knowledge.contains("does not require import")||knowledge.contains("without importing")||
        knowledge.contains("do not import")||knowledge.contains("must not import")||
        knowledge.contains("dependency is unnecessary")||knowledge.contains("dependency is not required")
    if(denies){return false}
    knowledge.contains("must import")||knowledge.contains("requires import")||knowledge.contains("required to import")||
        knowledge.contains("importing std.")||knowledge.contains("importing stdx.")||knowledge.contains("import std.")||
        knowledge.contains("import stdx.")||knowledge.contains("add a dependency")||knowledge.contains("add the dependency")||
        knowledge.contains("dependency prerequisite")||knowledge.contains("depends on std.")||knowledge.contains("depends on stdx.")
}

private func claudeClassifierPackageTokens(value:String):ArrayList<String>{
    let out=ArrayList<String>();var current=StringBuilder()
    for(c in value.toAsciiLower().toRuneArray()){
        if((c>=r'a'&&c<=r'z')||(c>=r'0'&&c<=r'9')||c==r'_'||c==r'.'||c==r'*'){current.append(c)}
        else{claudeClassifierAddPackageToken(out,current.toString());current=StringBuilder()}
    };claudeClassifierAddPackageToken(out,current.toString());out
}
private func claudeClassifierAddPackageToken(out:ArrayList<String>,raw:String):Unit{
    let runes=raw.toRuneArray();var end=runes.size
    while(end>0&&(runes[end-1]==r'.'||runes[end-1]==r'*')){end-=1}
    if(end==0){return};let token=String(runes[0..end])
    if((token.startsWith("std.")||token.startsWith("stdx."))&&!out.contains(token)){out.add(token)}
}

// A Claude stream is provider evidence only when it contains the native system/init event;
// model identity comes from that event, never from the requested model or model-authored payload.
public func decodeClaudeClassifierStream(raw: String): (String, String) {
    var initialized=false; var observedModel=""; var terminal=""; var terminalCount:Int64=0
    for (line in raw.split("\n")) {
        let clean=line.trimAscii();if(clean==""){continue}
        if(clean.toArray().size>CLAUDE_CLASSIFIER_MAX_BYTES){return("","classifier_output_too_large")}
        try {
            let o=JsonValue.fromStr(clean).asObject();let kind=classifierString(o,"type");let subtype=classifierString(o,"subtype")
            if(kind=="system"&&subtype=="init"){
                if(initialized){return("","duplicate_init")};initialized=true;observedModel=classifierString(o,"model")
            } else if(kind=="result") {
                terminalCount+=1
                if(subtype!="success"||classifierBool(o,"is_error")){return("","classifier_unsuccessful_result")}
                terminal=match(o.get("structured_output")){case Some(v)=>v.toString();case None=>""}
            }
        } catch (_: Exception) { return ("", "malformed_stream_json") }
    }
    if(!initialized){return("","missing_init")};if(observedModel!=CLAUDE_CLASSIFIER_MODEL){return("","observed_model_mismatch")}
    if(terminalCount!=1||terminal==""){return("","missing_or_duplicate_terminal_result")}
    try {
        let o=JsonValue.fromStr(terminal).asObject()
        if(!validClaudeClassifierResponse(o)){return("","response_contract_invalid")}
        let response=renderClaudeClassifierResponse(o)
        if(claudeClassifierForbidden(response)){return("","response_contains_forbidden_data")}
        (response,"ok")
    } catch (_: Exception) { ("","malformed_structured_output") }
}

// Non-streaming JSON keeps model reasoning outside the classifier protocol while
// still binding the successful terminal result to the single observed model.
public func decodeClaudeClassifierTerminalJson(raw:String):(String,String){
    if(raw.toArray().size>CLAUDE_CLASSIFIER_MAX_BYTES){return("","classifier_output_too_large")}
    try{
        let terminal=JsonValue.fromStr(raw).asObject()
        if(classifierString(terminal,"type")!="result"||classifierString(terminal,"subtype")!="success"||
            classifierBool(terminal,"is_error")){return("","classifier_unsuccessful_result")}
        let usage=terminal.get("modelUsage").getOrThrow().asObject()
        if(usage.getFields().size!=1){return("","observed_model_mismatch")}
        match(usage.get(CLAUDE_CLASSIFIER_MODEL)){
            case Some(_) => ()
            case None => return("","observed_model_mismatch")
        }
        let structured=match(terminal.get("structured_output")){case Some(v)=>v.asObject();case None=>return("","malformed_structured_output")}
        if(!validClaudeClassifierResponse(structured)){return("","response_contract_invalid")}
        let response=renderClaudeClassifierResponse(structured)
        if(claudeClassifierForbidden(response)){return("","response_contains_forbidden_data")}
        (response,"ok")
    }catch(_:Exception){("","malformed_terminal_json")}
}

private func validClaudeClassifierResponse(o:JsonObject):Bool{
    let category=classifierString(o,"category").toAsciiLower();let knowledge=category=="knowledge_gap"
    let categories=["knowledge_gap","retrieval_failure","reasoning_failure","compile_error","unit_failure","dataset_failure","runner_failure","environment_failure","tool_error","timeout","protocol_violation"]
    if(!categories.contains(category)){return false}
    if(knowledge){classifierString(o,"knowledgeFamily")!=""&&classifierBool(o,"reusable")&&classifierString(o,"sourceClass")=="official"&&
        classifierString(o,"citation").startsWith("https://docs.cangjie-lang.cn/")&&classifierBool(o,"purificationPassed")&&
        classifierString(o,"canonicalKnowledgeId")!=""&&classifierString(o,"targetVersion")!=""&&classifierString(o,"evidenceId")!=""&&classifierString(o,"knowledgeText")!=""}
    else{true}
}

private func renderClaudeClassifierResponse(o:JsonObject):String{
    let category=classifierString(o,"category").toAsciiLower();let knowledge=category=="knowledge_gap"
    "{\"schemaVersion\":\"${CLAUDE_CLASSIFIER_RESPONSE_SCHEMA}\",\"observedProvider\":\"${CLAUDE_CLASSIFIER_PROVIDER}\",\"observedModel\":\"${CLAUDE_CLASSIFIER_MODEL}\",\"category\":\"${classifierEscape(category)}\",\"knowledgeFamily\":\"${classifierEscape(if(knowledge){classifierString(o,"knowledgeFamily")}else{""})}\",\"reusable\":${knowledge&&classifierBool(o,"reusable")},\"sourceClass\":\"${classifierEscape(if(knowledge){classifierString(o,"sourceClass")}else{""})}\",\"citation\":\"${classifierEscape(if(knowledge){classifierString(o,"citation")}else{""})}\",\"purificationPassed\":${knowledge&&classifierBool(o,"purificationPassed")},\"canonicalKnowledgeId\":\"${classifierEscape(if(knowledge){classifierString(o,"canonicalKnowledgeId")}else{""})}\",\"targetVersion\":\"${classifierEscape(if(knowledge){classifierString(o,"targetVersion")}else{""})}\",\"evidenceId\":\"${classifierEscape(if(knowledge){classifierString(o,"evidenceId")}else{""})}\",\"knowledgeText\":\"${classifierEscape(if(knowledge){classifierString(o,"knowledgeText")}else{""})}\"}"
}

private func claudeClassifierJsonSchema():String{"{\"type\":\"object\",\"additionalProperties\":false,\"properties\":{\"category\":{\"type\":\"string\"},\"knowledgeFamily\":{\"type\":\"string\"},\"reusable\":{\"type\":\"boolean\"},\"sourceClass\":{\"type\":\"string\"},\"citation\":{\"type\":\"string\"},\"purificationPassed\":{\"type\":\"boolean\"},\"canonicalKnowledgeId\":{\"type\":\"string\"},\"targetVersion\":{\"type\":\"string\"},\"evidenceId\":{\"type\":\"string\"},\"knowledgeText\":{\"type\":\"string\"}},\"required\":[\"category\",\"knowledgeFamily\",\"reusable\",\"sourceClass\",\"citation\",\"purificationPassed\",\"canonicalKnowledgeId\",\"targetVersion\",\"evidenceId\",\"knowledgeText\"]}"}
private func claudeClassifierForbidden(v:String):Bool{let x=v.toAsciiLower();x.contains("teacher-solutions")||x.contains("canonical_solution")||x.contains("hidden_test")||x.contains("hidden-test")||x.contains("/reference/")||x.contains("/users/")||x.contains("/private/")||x.contains("authorization:")||x.contains("password")||x.contains("api_key")||x.contains("token=")}
private func classifierString(o:JsonObject,k:String):String{match(o.get(k)){case Some(v)=>v.asString().getValue().trimAscii();case None=>""}}
private func classifierInt(o:JsonObject,k:String):Int64{match(o.get(k)){case Some(v)=>v.asInt().getValue();case None=>0}}
private func classifierBool(o:JsonObject,k:String):Bool{match(o.get(k)){case Some(v)=>v.asBool().getValue();case None=>false}}
private func classifierEscape(v:String):String{v.replace("\\","\\\\").replace("\"","\\\"").replace("\n","\\n").replace("\r","\\r").replace("\t","\\t")}
