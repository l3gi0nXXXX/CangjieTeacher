package cangjie_teacher_test

import std.collection.*
import std.env.{getVariable,setVariable}
import std.fs.*
import std.process.launch
import std.time.*
import std.unittest.testmacro.*
import cangjie_teacher.*

private class ClassifierExecutor <: TeacherCommandExecutor {
    public let specs=ArrayList<TeacherCommandSpec>()
    private let result:TeacherProcessResult
    public init(result:TeacherProcessResult){this.result=result}
    public func execute(spec:TeacherCommandSpec):TeacherProcessResult{specs.add(spec);result}
}

@Test
public class TeacherClaudeClassifierTest {
    private func root(name:String):String{"/tmp/teacher-claude-classifier-${name}-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"}
    private func request():String{"{\"schemaVersion\":\"ckb-p5-classifier-request-v1\",\"caseId\":\"CJ-HUMANEVAL-007\",\"runId\":\"run-中文😀\",\"datasetVersion\":\"dataset-v1\",\"attempt\":1,\"runMode\":\"development\",\"resultEvidenceHash\":\"sha256:evidence\",\"failureObservation\":\"缺少 Rune 知识😀\"}"}
    private func absRequest():String{"{\"schemaVersion\":\"ckb-p5-classifier-request-v1\",\"caseId\":\"CASE-GENERIC-ABS\",\"runId\":\"run-中文😀\",\"datasetVersion\":\"dataset-v1\",\"attempt\":1,\"runMode\":\"development\",\"resultEvidenceHash\":\"sha256:evidence\",\"failureObservation\":\"compile_error 中文😀\",\"studentSourceExcerpt\":\"main(): Unit { let value: Float64 = -3.5; println(value.abs()) }\",\"compilerTestSummary\":\"error: undeclared identifier 'abs' 中文😀\"}"}
    private func prerequisiteRequest(summary:String):String{"{\"schemaVersion\":\"ckb-p5-classifier-request-v1\",\"caseId\":\"CASE-GENERIC-IMPORT\",\"runId\":\"run-中文😀\",\"datasetVersion\":\"dataset-v1\",\"attempt\":1,\"runMode\":\"development\",\"resultEvidenceHash\":\"sha256:evidence\",\"failureObservation\":\"compile_error 中文😀\",\"studentSourceExcerpt\":\"main(): Unit { println(1) }\",\"compilerTestSummary\":\"${summary}\"}"}
    private func structured(category!:String="reasoning_failure",model!:String="GLM-5.2"):String{
        let body="{\"category\":\"${category}\",\"knowledgeFamily\":\"\",\"reusable\":false,\"sourceClass\":\"\",\"citation\":\"\",\"purificationPassed\":false,\"canonicalKnowledgeId\":\"\",\"targetVersion\":\"\",\"evidenceId\":\"\",\"knowledgeText\":\"\"}"
        "{\"type\":\"system\",\"subtype\":\"init\",\"model\":\"${model}\"}\n{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"structured_output\":${body}}\n"
    }
    private func args(root:String):Array<String>{["--request","${root}/workspace/request.json","--output","${root}/workspace/response.json","--workspace","${root}/workspace","--runtime-home","${root}/runtime-home","--session-id","session-中文😀","--expected-provider","claude-code","--expected-model","GLM-5.2"]}
    private func prepare(name:String):(String,Array<String>){let r=root(name);Directory.create(Path("${r}/workspace"),recursive:true);Directory.create(Path("${r}/runtime-home"),recursive:true);File.writeTo(Path("${r}/workspace/request.json"),request().toArray());(r,args(r))}
    private func oversizedLine():String{var value="x";for(_ in 0..21){value+=value};value}
    private func knowledgeStructured(text:String):String{
        let body="{\"category\":\"knowledge_gap\",\"knowledgeFamily\":\"standard_library\",\"reusable\":true,\"sourceClass\":\"official\",\"citation\":\"https://docs.cangjie-lang.cn/docs/1.0.0/\",\"purificationPassed\":true,\"canonicalKnowledgeId\":\"GENERAL-ABS-API\",\"targetVersion\":\"1.0.0\",\"evidenceId\":\"sha256:evidence\",\"knowledgeText\":\"${text}\"}"
        "{\"type\":\"system\",\"subtype\":\"init\",\"model\":\"GLM-5.2\"}\n{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"structured_output\":${body}}\n"
    }

    // P5-C-UT-02 + P5-C-POS-02: exact isolated Claude argv and a native init/result identity produce response v1.
    @TestCase public func exactClaudeContractAndUtf8Positive():Unit{
        let setup=prepare("positive");let r=setup[0]
        try{
            let executor=ClassifierExecutor(TeacherProcessResult(0,structured()));let result=runClaudeClassifierAdapter(setup[1],executor:executor)
            @Expect(result.ok,true);@Expect(result.diagnostic,"ok");@Expect(executor.specs.size,1)
            let spec=executor.specs[0];@Expect(spec.executable,"claude");@Expect(spec.args.contains("-p"),true);@Expect(spec.args.contains("--json-schema"),true)
            @Expect(spec.args[1].contains("root cause"),true);@Expect(spec.args[1].contains("even when failureObservation is compile_error or unit_failure"),true)
            @Expect(spec.args[1].contains("case-specific"),true)
            @Expect(spec.args[1].contains("knowledgeFamily must be exactly one of syntax, standard_library"),true)
            @Expect(spec.args[1].contains("sourceClass must be exactly official"),true);@Expect(spec.args[1].contains("targetVersion must be 1.0.0"),true)
            @Expect(spec.args.contains("stream-json"),true);@Expect(spec.args.contains("--no-session-persistence"),true);@Expect(spec.args.contains("--bare"),true)
            @Expect(spec.args.contains("--strict-mcp-config"),true);@Expect(spec.args.contains("--tools"),true);@Expect(spec.args.contains("GLM-5.2"),true)
            @Expect(spec.args.contains("{\"mcpServers\":{}}"),true);@Expect(spec.args.contains("{}"),false)
            let output=teacherReadUtf8File("${r}/workspace/response.json");@Expect(output.contains("\"schemaVersion\":\"ckb-p5-classifier-response-v1\""),true)
            @Expect(output.contains("\"observedProvider\":\"claude-code\""),true);@Expect(output.contains("\"observedModel\":\"GLM-5.2\""),true)
        }finally{try{remove(Path(r),recursive:true)}catch(_:Exception){}}
    }

    // P5-C-POS-02: the native process path works with an isolated temporary fake CLI, never a real model/config.
    @TestCase public func isolatedFakeClaudeCliEndToEnd():Unit{
        let setup=prepare("fake-cli");let r=setup[0];let oldPath=getVariable("PATH")
        try{
            let fake="${r}/bin/claude";Directory.create(Path("${r}/bin"),recursive:true)
            let script="#!/bin/zsh\n[[ \" $* \" == *\" --model GLM-5.2 \"* ]] || exit 21\n[[ \" $* \" == *\" --json-schema \"* ]] || exit 22\n[[ \" $* \" == *\" --no-session-persistence \"* ]] || exit 23\n[[ \" $* \" == *\" --tools  \"* ]] || exit 24\nprint -r -- '{\"type\":\"system\",\"subtype\":\"init\",\"model\":\"GLM-5.2\"}'\nprint -r -- '{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"structured_output\":{\"category\":\"reasoning_failure\",\"knowledgeFamily\":\"\",\"reusable\":false,\"sourceClass\":\"\",\"citation\":\"\",\"purificationPassed\":false,\"canonicalKnowledgeId\":\"\",\"targetVersion\":\"\",\"evidenceId\":\"\",\"knowledgeText\":\"\"}}'\n"
            File.writeTo(Path(fake),script.toArray());@Expect(launch("/bin/chmod",["700",fake]).wait(),0)
            let previous=match(oldPath){case Some(v)=>v;case None=>"/usr/bin:/bin"};setVariable("PATH","${r}/bin:${previous}")
            let result=runClaudeClassifierAdapter(setup[1]);@Expect(result.ok,true);@Expect(teacherReadUtf8File("${r}/workspace/response.json").contains("reasoning_failure"),true)
        }finally{match(oldPath){case Some(v)=>setVariable("PATH",v);case None=>setVariable("PATH","")};try{remove(Path(r),recursive:true)}catch(_:Exception){}}
    }

    // P5-C-BND-02: malformed UTF-8, malformed JSON, oversized output, and UTF-8 values fail safely.
    @TestCase public func utf8JsonAndSizeBoundariesFailClosed():Unit{
        let setup=prepare("boundaries");let r=setup[0]
        try{
            File.writeTo(Path("${r}/workspace/request.json"),[UInt8(0xff),UInt8(0xfe)])
            @Expect(runClaudeClassifierAdapter(setup[1],executor:ClassifierExecutor(TeacherProcessResult(0,structured()))).diagnostic,"invalid_response_encoding")
            @Expect(decodeClaudeClassifierStream("{bad")[1],"malformed_stream_json")
            @Expect(decodeClaudeClassifierStream(oversizedLine())[1],"classifier_output_too_large")
            @Expect(decodeClaudeClassifierStream(structured())[0].contains("reasoning_failure"),true)
        }finally{try{remove(Path(r),recursive:true)}catch(_:Exception){}}
    }

    // P5-C-NEG-02: timeout/nonzero/no result/wrong identity and unsupported expected identity never write output.
    @TestCase public func executionAndIdentityFailuresDoNotPublish():Unit{
        let setup=prepare("negative");let r=setup[0]
        try{
            let timeout=runClaudeClassifierAdapter(setup[1],executor:ClassifierExecutor(TeacherProcessResult(124,"timeout",timedOut:true)));@Expect(timeout.diagnostic,"classifier_timeout")
            @Expect(runClaudeClassifierAdapter(setup[1],executor:ClassifierExecutor(TeacherProcessResult(9,"failed"))).diagnostic,"classifier_process_failed")
            @Expect(decodeClaudeClassifierStream("{\"type\":\"system\",\"subtype\":\"init\",\"model\":\"GLM-5.2\"}\n")[1],"missing_or_duplicate_terminal_result")
            @Expect(decodeClaudeClassifierStream(structured(model:"wrong-model"))[1],"observed_model_mismatch")
            let wrong=setup[1].clone();wrong[13]="GPT-5.6";@Expect(runClaudeClassifierAdapter(wrong,executor:ClassifierExecutor(TeacherProcessResult(0,structured()))).diagnostic,"expected_identity_not_allowed")
            @Expect(exists(Path("${r}/workspace/response.json")),false)
        }finally{try{remove(Path(r),recursive:true)}catch(_:Exception){}}
    }

    // P5-C-UT-03/POS-03/NEG-03/BND-03: request-visible facts bound every prerequisite and abs API claim.
    @TestCase public func groundedPrerequisitesAndAbsFactsFailClosed():Unit{
        let setup=prepare("grounded-facts");let r=setup[0]
        try{
            File.writeTo(Path("${r}/workspace/request.json"),absRequest().toArray())
            let correct=ClassifierExecutor(TeacherProcessResult(0,knowledgeStructured("Float64 receiver .abs() is unavailable; use the global documented abs(value) form.")))
            let accepted=runClaudeClassifierAdapter(setup[1],executor:correct)
            @Expect(accepted.ok,true);@Expect(accepted.diagnostic,"ok")
            @Expect(correct.specs[0].args[1].contains("Never assert an import or dependency prerequisite unless"),true)
            @Expect(correct.specs[0].args[1].contains("receiver .abs() is unavailable and use the global documented abs(value) form"),true)
            remove(Path("${r}/workspace/response.json"))

            let unsupported=ClassifierExecutor(TeacherProcessResult(0,knowledgeStructured("Float64 requires import std.math.* before global abs(value).")))
            let rejected=runClaudeClassifierAdapter(setup[1],executor:unsupported)
            @Expect(rejected.ok,false);@Expect(rejected.diagnostic,"classifier_response_source_fact_unsupported")
            @Expect(exists(Path("${r}/workspace/response.json")),false)

            let incomplete=ClassifierExecutor(TeacherProcessResult(0,knowledgeStructured("Use the documented Float64 API.")))
            @Expect(runClaudeClassifierAdapter(setup[1],executor:incomplete).diagnostic,"classifier_response_source_fact_unsupported")
            let privatePath=knowledgeStructured("Use global abs(value); see /Users/private/秘密😀.")
            @Expect(decodeClaudeClassifierStream(privatePath)[1],"response_contains_forbidden_data")

            File.writeTo(Path("${r}/workspace/request.json"),prerequisiteRequest("root imports package 'std.unicode' but it is not declared as a dependency").toArray())
            let supported=ClassifierExecutor(TeacherProcessResult(0,knowledgeStructured("The visible dependency diagnostic requires import std.unicode.*.")))
            @Expect(runClaudeClassifierAdapter(setup[1],executor:supported).diagnostic,"ok")
            remove(Path("${r}/workspace/response.json"))
            let wrongPackage=ClassifierExecutor(TeacherProcessResult(0,knowledgeStructured("The failure requires import std.math.*.")))
            @Expect(runClaudeClassifierAdapter(setup[1],executor:wrongPackage).diagnostic,"classifier_response_source_fact_unsupported")
            File.writeTo(Path("${r}/workspace/request.json"),prerequisiteRequest("error: undeclared identifier 'demo'").toArray())
            @Expect(runClaudeClassifierAdapter(setup[1],executor:supported).diagnostic,"classifier_response_source_fact_unsupported")
            File.writeTo(Path("${r}/workspace/request.json"),prerequisiteRequest("error after import std.unicode.* 中文😀").toArray())
            @Expect(runClaudeClassifierAdapter(setup[1],executor:supported).diagnostic,"classifier_response_source_fact_unsupported")
            File.writeTo(Path("${r}/workspace/request.json"),prerequisiteRequest("source contains import std.unicode.* but another API failed").toArray())
            @Expect(runClaudeClassifierAdapter(setup[1],executor:supported).diagnostic,"classifier_response_source_fact_unsupported")
            File.writeTo(Path("${r}/workspace/request.json"),prerequisiteRequest("cannot find package std.unicode 中文😀").toArray())
            @Expect(runClaudeClassifierAdapter(setup[1],executor:supported).diagnostic,"ok")
        }finally{try{remove(Path(r),recursive:true)}catch(_:Exception){}}
    }

    // P5-C-UT-04/POS-04/NEG-04/BND-04: failures expose only a workspace-local enum sidecar.
    @TestCase public func safeFailureDiagnosticSidecarIsAtomicBoundedAndStaleSafe():Unit{
        let setup=prepare("safe-sidecar");let r=setup[0];let sidecar=Path("${r}/workspace/classifier-diagnostic.json")
        try{
            File.writeTo(Path("${r}/workspace/request.json"),absRequest().toArray())
            let unsafeText="Float64 requires import std.math.* before global abs(value); /Users/private/秘密😀 token=secret."
            let blocked=runClaudeClassifierAdapter(setup[1],executor:ClassifierExecutor(TeacherProcessResult(0,knowledgeStructured(unsafeText))))
            @Expect(blocked.diagnostic,"response_contains_forbidden_data");@Expect(exists(sidecar),true)
            let safe=if(exists(sidecar)){teacherReadUtf8File(sidecar.toString())}else{""}
            @Expect(safe,"{\"schemaVersion\":\"cangjie-teacher-classifier-diagnostic-v1\",\"diagnostic\":\"response_contains_forbidden_data\"}\n")
            @Expect(safe.contains("/Users"),false);@Expect(safe.toAsciiLower().contains("token"),false);@Expect(safe.contains("秘密😀"),false)

            File.writeTo(sidecar,"stale /private/token=secret".toArray())
            let correct=ClassifierExecutor(TeacherProcessResult(0,knowledgeStructured("Float64 receiver .abs() is unavailable; use the global documented abs(value) form.")))
            @Expect(runClaudeClassifierAdapter(setup[1],executor:correct).diagnostic,"ok")
            @Expect(exists(sidecar),false)
            remove(Path("${r}/workspace/response.json"))

            File.writeTo(Path("${r}/workspace/request.json"),[UInt8(0xff),UInt8(0xfe)])
            @Expect(runClaudeClassifierAdapter(setup[1],executor:ClassifierExecutor(TeacherProcessResult(0,structured()))).diagnostic,"invalid_response_encoding")
            let encodingSafe=if(exists(sidecar)){teacherReadUtf8File(sidecar.toString())}else{""}
            @Expect(encodingSafe.contains("invalid_response_encoding"),true)
            @Expect(encodingSafe!=""&&encodingSafe.toArray().size<=160,true)

            File.writeTo(Path("${r}/workspace/request.json"),absRequest().toArray())
            @Expect(runClaudeClassifierAdapter(setup[1],executor:ClassifierExecutor(TeacherProcessResult(124,"private timeout payload",timedOut:true))).diagnostic,"classifier_timeout")
            @Expect(teacherReadUtf8File(sidecar.toString()).contains("classifier_timeout"),true)
            @Expect(teacherReadUtf8File(sidecar.toString()).contains("private timeout payload"),false)
            @Expect(runClaudeClassifierAdapter(setup[1],executor:ClassifierExecutor(TeacherProcessResult(0,"{bad"))).diagnostic,"malformed_stream_json")
            @Expect(teacherReadUtf8File(sidecar.toString()).contains("malformed_stream_json"),true)
        }finally{try{remove(Path(r),recursive:true)}catch(_:Exception){}}
    }
}
