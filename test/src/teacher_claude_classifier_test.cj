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
    private func structured(category!:String="reasoning_failure",model!:String="GLM-5.2"):String{
        let body="{\"category\":\"${category}\",\"knowledgeFamily\":\"\",\"reusable\":false,\"sourceClass\":\"\",\"citation\":\"\",\"purificationPassed\":false,\"canonicalKnowledgeId\":\"\",\"targetVersion\":\"\",\"evidenceId\":\"\",\"knowledgeText\":\"\"}"
        "{\"type\":\"system\",\"subtype\":\"init\",\"model\":\"${model}\"}\n{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"structured_output\":${body}}\n"
    }
    private func args(root:String):Array<String>{["--request","${root}/workspace/request.json","--output","${root}/workspace/response.json","--workspace","${root}/workspace","--runtime-home","${root}/runtime-home","--session-id","session-中文😀","--expected-provider","claude-code","--expected-model","GLM-5.2"]}
    private func prepare(name:String):(String,Array<String>){let r=root(name);Directory.create(Path("${r}/workspace"),recursive:true);Directory.create(Path("${r}/runtime-home"),recursive:true);File.writeTo(Path("${r}/workspace/request.json"),request().toArray());(r,args(r))}
    private func oversizedLine():String{var value="x";for(_ in 0..21){value+=value};value}

    // P5-C-UT-02 + P5-C-POS-02: exact isolated Claude argv and a native init/result identity produce response v1.
    @TestCase public func exactClaudeContractAndUtf8Positive():Unit{
        let setup=prepare("positive");let r=setup[0]
        try{
            let executor=ClassifierExecutor(TeacherProcessResult(0,structured()));let result=runClaudeClassifierAdapter(setup[1],executor:executor)
            @Expect(result.ok,true);@Expect(result.diagnostic,"ok");@Expect(executor.specs.size,1)
            let spec=executor.specs[0];@Expect(spec.executable,"claude");@Expect(spec.args.contains("-p"),true);@Expect(spec.args.contains("--json-schema"),true)
            @Expect(spec.args.contains("stream-json"),true);@Expect(spec.args.contains("--no-session-persistence"),true);@Expect(spec.args.contains("--bare"),true)
            @Expect(spec.args.contains("--strict-mcp-config"),true);@Expect(spec.args.contains("--tools"),true);@Expect(spec.args.contains("GLM-5.2"),true)
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
}
