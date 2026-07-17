package cangjie_teacher_test

import cangjie_teacher.*
import std.collection.*
import std.fs.*
import std.process.launch
import std.time.DateTime
import std.unittest.*
import std.unittest.testmacro.*

private class P5CodexFakeExecutor <: TeacherCommandExecutor {
    let mode: String
    public let specs = ArrayList<TeacherCommandSpec>()
    public init(mode!: String = "ok") { this.mode = mode }
    public func execute(spec: TeacherCommandSpec): TeacherProcessResult {
        specs.add(spec)
        if (mode == "throw") { throw IllegalStateException("/Users/private/token=secret 秘密🙂") }
        if (mode == "timeout") { return TeacherProcessResult(124, "secret must not surface", timedOut: true) }
        if (mode == "nonzero") { return TeacherProcessResult(7, "Authorization: secret") }
        var output = ""
        for (i in 0..spec.args.size - 1) { if (spec.args[i] == "--output-last-message") { output = spec.args[i + 1] } }
        if (mode == "invalid_utf8") { File.writeTo(Path(output), [UInt8(0xff), UInt8(0xfe)]); return TeacherProcessResult(0, "") }
        if (mode == "oversized") { File.writeTo(Path(output), Array<UInt8>(262145, repeat: UInt8(65))); return TeacherProcessResult(0, "") }
        let knowledge = match(mode){
            case "string_case_valid" => "Direct String iteration yields UInt8 bytes. String.toAsciiLower(): String performs ASCII-only conversion. Rune.toAsciiLowerCase(): Rune is ASCII-only. Unicode conversion requires import std.unicode.* and Rune.toLowerCase(): Rune. The failing String.toLower() receiver is unavailable. 中文🙂"
            case "string_case_returns_rune" => "Direct String iteration yields UInt8 bytes. String.toAsciiLower() returns a String and is ASCII-only. Rune.toAsciiLowerCase() returns a Rune and is ASCII-only. Unicode casing requires import std.unicode.* and Rune.toLowerCase() returns a Rune. String.toLower() is unavailable."
            case "string_case_produces_rune" => "Direct String iteration yields UInt8 bytes. String.toAsciiLower() returns a String and is ASCII-only. Rune.toAsciiLowerCase() returns a Rune and is ASCII-only. Unicode casing requires import std.unicode.* and Rune.toLowerCase() produces a Rune. String.toLower() is unavailable."
            case "string_case_result_is_rune" => "Direct String iteration yields UInt8 bytes. String.toAsciiLower() returns a String and is ASCII-only. Rune.toAsciiLowerCase() returns a Rune and is ASCII-only. Unicode casing requires import std.unicode.* and the result of Rune.toLowerCase() is a Rune. String.toLower() is unavailable."
            case "string_case_v2_a_missing_type" => "In Cangjie 1.0.0, direct String iteration yields UInt8 bytes. String.toAsciiLower() returns a String and performs ASCII-only lowercasing. Rune.toAsciiLowerCase() returns a Rune and is also ASCII-only. Unicode lowercasing requires import std.unicode.* and Rune.toLowerCase(). String.toLower() is unavailable, and toLowerAscii is not a Cangjie API."
            case "string_case_comment_disguise" => "Direct String iteration yields UInt8 bytes. String.toAsciiLower() returns a String and is ASCII-only. Rune.toAsciiLowerCase() returns a Rune and is ASCII-only. Unicode casing requires import std.unicode.*; // Rune.toLowerCase() returns a Rune. String.toLower() is unavailable."
            case "string_case_iteration_rune" => "Direct String iteration yields Rune values. String.toAsciiLower(): String. Rune.toAsciiLowerCase(): Rune. Unicode conversion requires import std.unicode.* and Rune.toLowerCase(): Rune. String.toLower() is unavailable."
            case "string_case_wrong_api" => "Direct String iteration yields UInt8 bytes. String.toAsciiLower(): String. Rune.toLowerAscii(): Rune. Unicode conversion requires import std.unicode.* and Rune.toLowerCase(): Rune. String.toLower() is unavailable."
            case "string_case_no_import" => "Direct String iteration yields UInt8 bytes. String.toAsciiLower(): String. Rune.toAsciiLowerCase(): Rune. Unicode conversion uses Rune.toLowerCase(): Rune. String.toLower() is unavailable."
            case "string_case_word_pile" => "UInt8 String iteration String.toAsciiLower Rune.toAsciiLowerCase std.unicode Rune.toLowerCase unavailable"
            case "reserved_match_valid" => "The reserved keyword `match` is invalid as a plain identifier. The backtick form `match` is a legal raw identifier. Alternatively, rename the variable to a non-keyword name. 中文🙂"
            case "reserved_match_valid_equivalent" => "Because `match` is a keyword, it is not valid as an ordinary identifier. As a raw identifier, `match` is valid, and using a different variable name is another option."
            case "reserved_match_v1_a" => "Cangjie reserves `match` for match expressions, so it cannot be used as a local variable identifier."
            case "reserved_match_v1_b" => "In Cangjie, `match` is a reserved keyword and cannot be used as a variable name or identifier; choose another name."
            case "reserved_match_no_raw" => "The reserved keyword `match` is invalid as a plain identifier; rename the variable to a non-keyword name."
            case "reserved_match_no_rename" => "The reserved keyword `match` is invalid as a plain identifier, while the backtick form `match` is a legal raw identifier."
            case "reserved_match_comment_disguise" => "The reserved keyword `match` is invalid as a plain identifier. // The backtick form `match` is a legal raw identifier; rename the variable."
            case "reserved_match_word_pile" => "match keyword plain identifier raw identifier legal rename"
            case _ => "Use Rune boundaries for 中文🙂 text."
        }
        let body = if (mode == "malformed") { "{" } else if (mode == "forbidden") { "/Users/private/秘密🙂 token=secret" } else if (mode == "retrieval") { "{\"category\":\"retrieval_failure\",\"knowledgeFamily\":\"\",\"reusable\":false,\"sourceClass\":\"\",\"citation\":\"\",\"purificationPassed\":false,\"canonicalKnowledgeId\":\"\",\"targetVersion\":\"\",\"evidenceId\":\"\",\"knowledgeText\":\"\"}" } else {
            "{\"category\":\"knowledge_gap\",\"knowledgeFamily\":\"standard_library\",\"reusable\":true,\"sourceClass\":\"official\",\"citation\":\"https://docs.cangjie-lang.cn/docs/1.0.0/\",\"purificationPassed\":true,\"canonicalKnowledgeId\":\"GENERAL-RUNE\",\"targetVersion\":\"1.0.0\",\"evidenceId\":\"official-rune\",\"knowledgeText\":\"${knowledge}\"}"
        }
        File.writeTo(Path(output), body.toArray()); TeacherProcessResult(0, "ignored stdout")
    }
}

@Test
public class TeacherP5CodexClassifierTest {
    // P5-C-UT-01
    @TestCase public func p5CUT01StrictContractPinsCodexGpt56AndReadOnlyStructuredOutput(): Unit {
        let fixture = p5CodexFixture("ut"); let fake = P5CodexFakeExecutor()
        let result = executeTeacherP5CodexClassifierAdapter(fixture.args, executor: fake,
            codexExecutable: "/fake/codex", timeoutMillis: 4321)
        @Expect(result.ok, true); @Expect(fake.specs.size, 1)
        let spec = fake.specs[0]
        @Expect(spec.executable, "/fake/codex"); @Expect(spec.cwd, fixture.workspace); @Expect(spec.timeoutMillis, 4321)
        @Expect(spec.args[0], "exec"); @Expect(spec.args.contains("-m"), true); @Expect(spec.args.contains("gpt-5.6-sol"), true); @Expect(spec.args.contains("gpt-5.6"), false)
        @Expect(spec.args.contains("--sandbox"), true); @Expect(spec.args.contains("read-only"), true)
        @Expect(spec.args.contains("--ephemeral"), true); @Expect(spec.args.contains("--ignore-user-config"), true); @Expect(spec.args.contains("--ignore-rules"), true)
        @Expect(spec.args.contains("--output-schema"), true); @Expect(spec.args.contains("--output-last-message"), true)
        @Expect(spec.args[spec.args.size - 1].contains("root cause"), true)
        @Expect(spec.args[spec.args.size - 1].contains("even when the observed surface is compile_error or unit_failure"), true)
        @Expect(spec.args[spec.args.size - 1].contains("case-specific"), true)
        @Expect(spec.args[spec.args.size - 1].contains("knowledgeFamily must be exactly one of syntax, standard_library"), true)
        @Expect(spec.args[spec.args.size - 1].contains("sourceClass must be exactly official"), true)
        @Expect(spec.args[spec.args.size - 1].contains("https://docs.cangjie-lang.cn/docs/1.0.0/"), true)
        @Expect(spec.args[spec.args.size - 1].contains("targetVersion must be 1.0.0"), true)
        var homeOverridden=false;var sessionBound=false
        for(entry in spec.env){if(entry[0]=="CODEX_HOME"){homeOverridden=true};if(entry[0]=="CANGJIE_TEACHER_SESSION"&&entry[1]=="session-ut"){sessionBound=true}}
        @Expect(homeOverridden,false);@Expect(sessionBound,true)
        let output = teacherReadUtf8File(fixture.output)
        @Expect(output.contains("\"schemaVersion\":\"ckb-p5-classifier-response-v1\""), true)
        @Expect(output.contains("\"observedProvider\":\"codex\""), true); @Expect(output.contains("\"observedModel\":\"GPT-5.6-Sol\""), true)
        let schema=teacherReadUtf8File("${fixture.workspace}/classifier-response.schema.json")
        @Expect(schema.contains("\"required\":[\"category\",\"knowledgeFamily\",\"reusable\",\"sourceClass\",\"citation\",\"purificationPassed\",\"canonicalKnowledgeId\",\"targetVersion\",\"evidenceId\",\"knowledgeText\"]"),true)
    }

    // P5-C-BND-01
    @TestCase public func p5CBND01UnicodeEmojiInvalidUtf8OversizeAndStrictCliFailClosed(): Unit {
        let fixture = p5CodexFixture("边界🙂"); let fake = P5CodexFakeExecutor()
        @Expect(executeTeacherP5CodexClassifierAdapter(fixture.args, executor: fake, codexExecutable: "/fake/codex", timeoutMillis: 1000).ok, true)
        @Expect(teacherReadUtf8File(fixture.output).contains("中文🙂"), true)
        let invalid = p5CodexFixture("invalid-utf8"); File.writeTo(Path(invalid.request), [UInt8(0xff), UInt8(0xfe)])
        @Expect(executeTeacherP5CodexClassifierAdapter(invalid.args, executor: fake, codexExecutable: "/fake/codex", timeoutMillis: 1000).diagnostic, "invalid_response_encoding")
        let large = p5CodexFixture("large"); File.writeTo(Path(large.request), Array<UInt8>(262145, repeat: UInt8(65)))
        @Expect(executeTeacherP5CodexClassifierAdapter(large.args, executor: fake, codexExecutable: "/fake/codex", timeoutMillis: 1000).diagnostic, "request_too_large")
        let unknown=ArrayList<String>();for(value in fixture.args){unknown.add(value)};unknown.add("--unknown");unknown.add("x")
        var rejected=false;try{_=parseTeacherP5CodexAdapterOptions(unknown.toArray())}catch(e:Exception){rejected=e.message=="invalid_adapter_arguments"};@Expect(rejected,true)
    }

    // P5-C-POS-01
    @TestCase public func p5CPOS01FakeCodexProducesAtomicKnowledgeAndNonKnowledgeResponses(): Unit {
        let knowledge = p5CodexFixture("positive-knowledge")
        @Expect(runTeacherP5CodexClassifierAdapter(knowledge.args, executor: P5CodexFakeExecutor(), codexExecutable: "/fake/codex", timeoutMillis: 1000), 0)
        @Expect(teacherReadUtf8File(knowledge.output).contains("\"category\":\"knowledge_gap\""), true)
        let retrieval = p5CodexFixture("positive-retrieval")
        @Expect(runTeacherP5CodexClassifierAdapter(retrieval.args, executor: P5CodexFakeExecutor(mode:"retrieval"), codexExecutable: "/fake/codex", timeoutMillis: 1000), 0)
        let body=teacherReadUtf8File(retrieval.output);@Expect(body.contains("\"category\":\"retrieval_failure\""),true);@Expect(body.contains("\"knowledgeFamily\":\"\""),true);@Expect(body.contains("\"reusable\":false"),true)
        @Expect(exists(Path(retrieval.output+".tmp")),false)
    }

    // P5-C-NEG-01
    @TestCase public func p5CNEG01MalformedNonzeroTimeoutAndIdentityMismatchWriteNothing(): Unit {
        for (mode in ["malformed", "invalid_utf8", "nonzero", "timeout"]) {
            let fixture=p5CodexFixture("negative-${mode}")
            let result=executeTeacherP5CodexClassifierAdapter(fixture.args,executor:P5CodexFakeExecutor(mode:mode),codexExecutable:"/fake/codex",timeoutMillis:1000)
            @Expect(result.ok,false);@Expect(exists(Path(fixture.output)),false)
        }
        let identity=p5CodexFixture("negative-identity",model:"gpt-5.6")
        let mismatch=executeTeacherP5CodexClassifierAdapter(identity.args,executor:P5CodexFakeExecutor(),codexExecutable:"/fake/codex",timeoutMillis:1000)
        @Expect(mismatch.diagnostic,"adapter_identity_invalid");@Expect(exists(Path(identity.output)),false)
        let malformed=p5CodexFixture("negative-request");File.writeTo(Path(malformed.request),"{".toArray())
        @Expect(executeTeacherP5CodexClassifierAdapter(malformed.args,executor:P5CodexFakeExecutor(),codexExecutable:"/fake/codex",timeoutMillis:1000).diagnostic,"request_contract_invalid")
    }

    // P5-C-UT/POS/NEG/BND-07: Codex receives and enforces the same exact case-016 source facts as Claude.
    @TestCase public func p5CStringCaseRuneFactsAreRequestAwareAndFailClosed(): Unit {
        let accepted=p5CodexFixture("string-case-valid",requestBody:p5StringCaseRequest())
        let validFake=P5CodexFakeExecutor(mode:"string_case_valid")
        @Expect(executeTeacherP5CodexClassifierAdapter(accepted.args,executor:validFake,codexExecutable:"/fake/codex",timeoutMillis:1000).diagnostic,"ok")
        let prompt=validFake.specs[0].args[validFake.specs[0].args.size-1]
        @Expect(prompt.contains("direct String iteration yields UInt8"),true)
        @Expect(prompt.contains("String.toAsciiLower()"),true);@Expect(prompt.contains("Rune.toAsciiLowerCase()"),true)
        @Expect(prompt.contains("import std.unicode.* and Rune.toLowerCase()"),true)
        @Expect(prompt.contains("Rune.toLowerCase() returns a Rune"),true)

        for(mode in ["string_case_returns_rune","string_case_produces_rune","string_case_result_is_rune"]){
            let equivalent=p5CodexFixture("accept-${mode}",requestBody:p5StringCaseRequest())
            @Expect(executeTeacherP5CodexClassifierAdapter(equivalent.args,executor:P5CodexFakeExecutor(mode:mode),codexExecutable:"/fake/codex",timeoutMillis:1000).diagnostic,"ok")
        }

        for(mode in ["string_case_iteration_rune","string_case_wrong_api","string_case_no_import","string_case_word_pile",
            "string_case_v2_a_missing_type","string_case_comment_disguise"]){
            let fixture=p5CodexFixture("reject-${mode}",requestBody:p5StringCaseRequest())
            let rejected=executeTeacherP5CodexClassifierAdapter(fixture.args,executor:P5CodexFakeExecutor(mode:mode),codexExecutable:"/fake/codex",timeoutMillis:1000)
            @Expect(rejected.diagnostic,"classifier_response_source_fact_unsupported")
            @Expect(exists(Path(fixture.output)),false)
            @Expect(teacherReadUtf8File("${fixture.workspace}/classifier-diagnostic.json").contains("classifier_response_source_fact_unsupported"),true)
        }

        let unrelated=p5CodexFixture("string-case-unrelated")
        @Expect(executeTeacherP5CodexClassifierAdapter(unrelated.args,executor:P5CodexFakeExecutor(),codexExecutable:"/fake/codex",timeoutMillis:1000).diagnostic,"ok")
    }

    // P5-C-018-UT/POS/NEG/BND: ordinary `match`, raw identifier, and rename are one inseparable fact contract.
    @TestCase public func p5CReservedMatchRawIdentifierFactsAreRequestAwareAndFailClosed(): Unit {
        let accepted=p5CodexFixture("reserved-match-valid",requestBody:p5ReservedMatchRequest())
        let validFake=P5CodexFakeExecutor(mode:"reserved_match_valid")
        @Expect(executeTeacherP5CodexClassifierAdapter(accepted.args,executor:validFake,codexExecutable:"/fake/codex",timeoutMillis:1000).diagnostic,"ok")
        let prompt=validFake.specs[0].args[validFake.specs[0].args.size-1]
        @Expect(prompt.contains("plain identifier"),true);@Expect(prompt.contains("raw identifier"),true)
        @Expect(prompt.contains("`match`"),true);@Expect(prompt.contains("rename"),true)
        let equivalent=p5CodexFixture("reserved-match-valid-equivalent",requestBody:p5ReservedMatchRequest())
        @Expect(executeTeacherP5CodexClassifierAdapter(equivalent.args,executor:P5CodexFakeExecutor(mode:"reserved_match_valid_equivalent"),codexExecutable:"/fake/codex",timeoutMillis:1000).diagnostic,"ok")

        for(mode in ["reserved_match_v1_a","reserved_match_v1_b","reserved_match_no_raw","reserved_match_no_rename",
            "reserved_match_comment_disguise","reserved_match_word_pile"]){
            let fixture=p5CodexFixture("reject-${mode}",requestBody:p5ReservedMatchRequest())
            let rejected=executeTeacherP5CodexClassifierAdapter(fixture.args,executor:P5CodexFakeExecutor(mode:mode),codexExecutable:"/fake/codex",timeoutMillis:1000)
            @Expect(rejected.diagnostic,"classifier_response_source_fact_unsupported")
            @Expect(exists(Path(fixture.output)),false)
        }

        let unrelated=p5CodexFixture("reserved-match-unrelated")
        @Expect(executeTeacherP5CodexClassifierAdapter(unrelated.args,executor:P5CodexFakeExecutor(mode:"reserved_match_v1_a"),codexExecutable:"/fake/codex",timeoutMillis:1000).diagnostic,"ok")
    }

    // P5-C-UT-05/POS-05/NEG-05/BND-05: failures expose only a workspace-local safe enum sidecar.
    @TestCase public func p5CSafeDiagnosticSidecarIsAtomicBoundedAndStaleSafe(): Unit {
        let sidecarName = "classifier-diagnostic.json"
        for ((mode, expected) in [("nonzero", "classifier_process_failed"), ("timeout", "classifier_timeout"),
            ("invalid_utf8", "invalid_response_encoding"), ("malformed", "malformed_structured_output"),
            ("oversized", "classifier_output_too_large"), ("forbidden", "response_contains_forbidden_data"),
            ("throw", "classifier_failure_unknown")]) {
            let fixture = p5CodexFixture("sidecar-${mode}")
            let sidecar = Path(fixture.workspace).join(sidecarName)
            File.writeTo(sidecar, "stale /private/token=secret".toArray())
            let result = executeTeacherP5CodexClassifierAdapter(fixture.args,
                executor: P5CodexFakeExecutor(mode: mode), codexExecutable: "/fake/codex", timeoutMillis: 1000)
            @Expect(result.ok, false); @Expect(result.diagnostic, expected); @Expect(exists(sidecar), true)
            let safe = if (exists(sidecar)) { teacherReadUtf8File(sidecar.toString()) } else { "" }
            @Expect(safe, "{\"schemaVersion\":\"cangjie-teacher-classifier-diagnostic-v1\",\"diagnostic\":\"${expected}\"}\n")
            @Expect(safe.toArray().size <= 160, true); @Expect(safe.contains("/Users"), false)
            @Expect(safe.contains("/private"), false); @Expect(safe.toAsciiLower().contains("token"), false)
            @Expect(exists(Path(sidecar.toString() + ".tmp")), false)
        }

        let success = p5CodexFixture("sidecar-success")
        let successSidecar = Path(success.workspace).join(sidecarName)
        File.writeTo(successSidecar, "stale /private/token=secret".toArray())
        let accepted = executeTeacherP5CodexClassifierAdapter(success.args,
            executor: P5CodexFakeExecutor(), codexExecutable: "/fake/codex", timeoutMillis: 1000)
        @Expect(accepted.ok, true); @Expect(accepted.diagnostic, "ok"); @Expect(exists(successSidecar), false)
    }
}

private class P5CodexFixture {
    public let root:String;public let workspace:String;public let runtimeHome:String;public let request:String;public let output:String;public let args:Array<String>
    public init(root:String,workspace:String,runtimeHome:String,request:String,output:String,args:Array<String>){this.root=root;this.workspace=workspace;this.runtimeHome=runtimeHome;this.request=request;this.output=output;this.args=args}
}

private func p5StringCaseRequest():String{"{\"schemaVersion\":\"ckb-p5-classifier-request-v1\",\"caseId\":\"CJ-HUMANEVAL-016\",\"runId\":\"run-中文🙂\",\"datasetVersion\":\"dataset-v1\",\"attempt\":1,\"runMode\":\"development\",\"failureObservation\":\"compile_error 中文🙂\",\"studentSourceExcerpt\":\"for (c in text.toLower()) { println(c) }\",\"compilerTestSummary\":\"error: 'toLower' is not a member of struct 'String' 中文🙂\",\"resultEvidenceHash\":\"sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\"}"}

private func p5ReservedMatchRequest():String{"{\"schemaVersion\":\"ckb-p5-classifier-request-v1\",\"caseId\":\"CJ-HUMANEVAL-018\",\"runId\":\"run-中文🙂\",\"datasetVersion\":\"dataset-v1\",\"attempt\":1,\"runMode\":\"development\",\"failureObservation\":\"compile_error 中文🙂\",\"studentSourceExcerpt\":\"var match = true\",\"compilerTestSummary\":\"error: expected identifier or pattern after 'var', found keyword 'match' 中文🙂\",\"resultEvidenceHash\":\"sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\"}"}

private func p5CodexFixture(label:String,model!:String="GPT-5.6-Sol",requestBody!:String=""):P5CodexFixture{
    let root="/tmp/teacher-p5-codex-${label}-${DateTime.now().toUnixTimeStamp().toNanoseconds()}";let workspace="${root}/workspace";let runtime="${root}/runtime-home"
    Directory.create(Path(workspace),recursive:true);let request="${workspace}/request.json";let output="${workspace}/response.json"
    let body=if(requestBody==""){"{\"schemaVersion\":\"ckb-p5-classifier-request-v1\",\"caseId\":\"CJ-HUMANEVAL-016\",\"runId\":\"run-中文🙂\",\"datasetVersion\":\"dataset-v1\",\"attempt\":1,\"runMode\":\"development\",\"failureObservation\":\"缺少可复用 Rune 知识🙂\",\"resultEvidenceHash\":\"sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\"}"}else{requestBody}
    File.writeTo(Path(request),body.toArray())
    let args=["--request",request,"--output",output,"--workspace",workspace,"--runtime-home",runtime,"--session-id","session-${label}","--expected-provider","codex","--expected-model",model]
    P5CodexFixture(root,workspace,runtime,request,output,args)
}
