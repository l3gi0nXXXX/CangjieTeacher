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
    let request = try { readClaudeClassifierUtf8(options.request) } catch (e: IllegalArgumentException) {
        result.diagnostic = e.message; return result
    }
    if (request.toArray().size > CLAUDE_CLASSIFIER_MAX_BYTES) { result.diagnostic = "request_too_large"; return result }
    if (!validClaudeClassifierRequest(request)) { result.diagnostic = "request_contract_invalid"; return result }
    let schema = claudeClassifierJsonSchema()
    let prompt = "Classify this Cangjie benchmark failure using only the supplied JSON. Return one schema-valid object. " +
        "Never infer or reveal hidden tests, reference answers, credentials, or local paths. Request:\n" + request
    let cli = executor.execute(TeacherCommandSpec("claude", ["-p", prompt, "--model", CLAUDE_CLASSIFIER_MODEL,
        "--json-schema", schema, "--output-format", "stream-json", "--verbose", "--no-session-persistence",
        "--bare", "--disable-slash-commands", "--strict-mcp-config", "--mcp-config", "{}", "--tools", ""],
        options.workspace, env: [("HOME", options.runtimeHome), ("CLAUDE_CONFIG_DIR", options.runtimeHome),
            ("CANGJIE_TEACHER_SESSION", options.sessionId)], timeoutMillis: 300000))
    if (cli.timedOut) { result.diagnostic = "classifier_timeout"; return result }
    if (cli.exitCode != 0) { result.diagnostic = "classifier_process_failed"; return result }
    if (cli.output == "invalid_response_encoding") { result.diagnostic = "invalid_response_encoding"; return result }
    if (cli.output.toArray().size > CLAUDE_CLASSIFIER_MAX_BYTES) { result.diagnostic = "classifier_output_too_large"; return result }
    let decoded = decodeClaudeClassifierStream(cli.output)
    if (decoded[1] != "ok") { result.diagnostic = decoded[1]; return result }
    try {
        _ = teacherAtomicWrite(options.output, decoded[0] + "\n")
        if (readClaudeClassifierUtf8(options.output) != decoded[0] + "\n") { result.diagnostic = "response_write_failed"; return result }
    } catch (_: Exception) { result.diagnostic = "response_write_failed"; return result }
    result.ok = true; result.diagnostic = "ok"; result
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
private func claudeClassifierForbidden(v:String):Bool{let x=v.toAsciiLower();x.contains("teacher-solutions")||x.contains("canonical_solution")||x.contains("hidden_test")||x.contains("hidden-test")||x.contains("/reference/")||x.contains("authorization:")||x.contains("password")||x.contains("api_key")||x.contains("token=")}
private func classifierString(o:JsonObject,k:String):String{match(o.get(k)){case Some(v)=>v.asString().getValue().trimAscii();case None=>""}}
private func classifierInt(o:JsonObject,k:String):Int64{match(o.get(k)){case Some(v)=>v.asInt().getValue();case None=>0}}
private func classifierBool(o:JsonObject,k:String):Bool{match(o.get(k)){case Some(v)=>v.asBool().getValue();case None=>false}}
private func classifierEscape(v:String):String{v.replace("\\","\\\\").replace("\"","\\\"").replace("\n","\\n").replace("\r","\\r").replace("\t","\\t")}
