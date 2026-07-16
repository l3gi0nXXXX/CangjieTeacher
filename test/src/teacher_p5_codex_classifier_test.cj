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
        if (mode == "timeout") { return TeacherProcessResult(124, "secret must not surface", timedOut: true) }
        if (mode == "nonzero") { return TeacherProcessResult(7, "Authorization: secret") }
        var output = ""
        for (i in 0..spec.args.size - 1) { if (spec.args[i] == "--output-last-message") { output = spec.args[i + 1] } }
        if (mode == "invalid_utf8") { File.writeTo(Path(output), [UInt8(0xff), UInt8(0xfe)]); return TeacherProcessResult(0, "") }
        let body = if (mode == "malformed") { "{" } else if (mode == "retrieval") { "{\"category\":\"retrieval_failure\",\"knowledgeFamily\":\"\",\"reusable\":false,\"sourceClass\":\"\",\"citation\":\"\",\"purificationPassed\":false,\"canonicalKnowledgeId\":\"\",\"targetVersion\":\"\",\"evidenceId\":\"\",\"knowledgeText\":\"\"}" } else {
            "{\"category\":\"knowledge_gap\",\"knowledgeFamily\":\"standard_library\",\"reusable\":true,\"sourceClass\":\"official\",\"citation\":\"https://docs.cangjie-lang.cn/docs/1.0.0/\",\"purificationPassed\":true,\"canonicalKnowledgeId\":\"GENERAL-RUNE\",\"targetVersion\":\"1.0.0\",\"evidenceId\":\"official-rune\",\"knowledgeText\":\"Use Rune boundaries for 中文🙂 text.\"}"
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
        @Expect(executeTeacherP5CodexClassifierAdapter(large.args, executor: fake, codexExecutable: "/fake/codex", timeoutMillis: 1000).diagnostic, "input_too_large")
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
        @Expect(executeTeacherP5CodexClassifierAdapter(malformed.args,executor:P5CodexFakeExecutor(),codexExecutable:"/fake/codex",timeoutMillis:1000).diagnostic,"malformed_request_json")
    }
}

private class P5CodexFixture {
    public let root:String;public let workspace:String;public let runtimeHome:String;public let request:String;public let output:String;public let args:Array<String>
    public init(root:String,workspace:String,runtimeHome:String,request:String,output:String,args:Array<String>){this.root=root;this.workspace=workspace;this.runtimeHome=runtimeHome;this.request=request;this.output=output;this.args=args}
}

private func p5CodexFixture(label:String,model!:String="GPT-5.6-Sol"):P5CodexFixture{
    let root="/tmp/teacher-p5-codex-${label}-${DateTime.now().toUnixTimeStamp().toNanoseconds()}";let workspace="${root}/workspace";let runtime="${root}/runtime-home"
    Directory.create(Path(workspace),recursive:true);let request="${workspace}/request.json";let output="${workspace}/response.json"
    let body="{\"schemaVersion\":\"ckb-p5-classifier-request-v1\",\"caseId\":\"CJ-HUMANEVAL-016\",\"runId\":\"run-中文🙂\",\"datasetVersion\":\"dataset-v1\",\"attempt\":1,\"runMode\":\"development\",\"failureObservation\":\"缺少可复用 Rune 知识🙂\",\"resultEvidenceHash\":\"sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\"}"
    File.writeTo(Path(request),body.toArray())
    let args=["--request",request,"--output",output,"--workspace",workspace,"--runtime-home",runtime,"--session-id","session-${label}","--expected-provider","codex","--expected-model",model]
    P5CodexFixture(root,workspace,runtime,request,output,args)
}
