package cangjie_teacher_test

import std.collection.*
import std.fs.*
import std.time.*
import std.unittest.testmacro.*
import stdx.encoding.json.*
import cangjie_teacher.*

private func p3CkbString(object: JsonObject, key: String): String {
    object.get(key).getOrThrow().asString().getValue()
}

private func p3CkbPart(value: String): String { "${value.size}:${value}" }

private func p3CkbCandidateHashFor(object:JsonObject,bundle:String,evidence:String,evidenceHash:String):String{
    let benchmark = p3CkbString(object, "benchmark").trimAscii().toAsciiLower()
    let dataset = p3CkbString(object, "datasetVersion").trimAscii().toAsciiLower()
    let caseId = p3CkbString(object, "caseId").trimAscii().toAsciiLower()
    let gap = p3CkbString(object, "missingKnowledge").trimAscii().toAsciiUpper()
    let target = p3CkbString(object, "targetVersion").trimAscii().toAsciiLower()
    let identity = "${benchmark}:${dataset}:${caseId}:${gap}:${target}"
    let canonical = p3CkbPart(identity) + p3CkbPart(p3CkbString(object, "taskText")) +
        p3CkbPart(p3CkbString(object, "visibleTestExcerpt")) + p3CkbPart(p3CkbString(object, "compilerOutput")) +
        p3CkbPart(gap) + p3CkbPart(p3CkbString(object, "interfaceId").trimAscii()) +
        p3CkbPart(p3CkbString(object, "contentFamily").trimAscii()) +
        p3CkbPart(p3CkbString(object, "updateMechanism").trimAscii()) +
        p3CkbPart(p3CkbString(object, "targetVersion").trimAscii()) +
        p3CkbPart(p3CkbString(object, "officialCitation").trimAscii()) + p3CkbPart(bundle) +
        p3CkbPart("${object.get("knowledgeAtomCandidate").getOrThrow().asBool().getValue()}") +
        p3CkbPart(p3CkbString(object, "teacherRunId")) + p3CkbPart(evidenceHash) +
        p3CkbPart(evidence) + p3CkbPart(p3CkbString(object, "candidatePath")) +
        p3CkbPart(object.get("revision").getOrThrow().toString()) + p3CkbPart(object.get("attempt").getOrThrow().toString()) +
        p3CkbPart(p3CkbString(object, "failureTaxonomy")) + p3CkbPart(object.get("knowledgeGapConfirmations").getOrThrow().toString())
    "sha256:${teacherStableHash(canonical)}"
}

private func p3CkbCandidateHash(raw: String): String {
    let object=JsonValue.fromStr(raw.trimAscii()).asObject()
    p3CkbCandidateHashFor(object,object.get("knowledgeAtomTestBundle").getOrThrow().toString(),p3CkbString(object,"evidence"),p3CkbString(object,"evidenceHash"))
}

private func makeLegacyRawCkb(source:String):Unit{
    let path="${source}/candidate-knowledge/ckb-benchmark-gap.jsonl";let current=teacherReadUtf8File(path).trimAscii();let object=JsonValue.fromStr(current).asObject()
    let rawBundle=teacherReadUtf8File("${source}/atom-tests.jsonl").trimAscii();let canonicalBundle=object.get("knowledgeAtomTestBundle").getOrThrow().toString()
    let currentEvidence=p3CkbString(object,"evidence");let baseEvidence=currentEvidence.split("|teacherAtomHash=")[0]
    let extractor=JsonValue.fromStr(rawBundle).asObject().get("extractor").getOrThrow().asObject();let transcript=p3CkbString(extractor,"transcriptHash")
    let legacyEvidence="${baseEvidence}|teacherAtomHash=sha256:${teacherStableHash(rawBundle)}|extractorTranscriptHash=${transcript}"
    let legacyEvidenceHash="sha256:${teacherStableHash(legacyEvidence)}";let legacyHash=p3CkbCandidateHashFor(object,rawBundle,legacyEvidence,legacyEvidenceHash)
    let legacy=current.replace("\"knowledgeAtomTestBundle\":${canonicalBundle}","\"knowledgeAtomTestBundle\":${rawBundle}")
        .replace("\"evidence\":\"${currentEvidence}\"","\"evidence\":\"${legacyEvidence}\"")
        .replace("\"evidenceHash\":\"${p3CkbString(object,"evidenceHash")}\"","\"evidenceHash\":\"${legacyEvidenceHash}\"")
        .replace("\"candidateHash\":\"${p3CkbString(object,"candidateHash")}\"","\"candidateHash\":\"${legacyHash}\"")
    File.writeTo(Path(path),(legacy+"\n").toArray())
}

private func buildCandidateFixture(root:String,name:String):String{
    Directory.create(Path(root),recursive:true)
    File.writeTo(Path("${root}/manifest.jsonl"),(teacherJoin(caseLines(),"\n")+"\n").toArray())
    Directory.create(Path("${root}/teacher-solutions/CJ-HUMANEVAL-000/src"),recursive:true)
    File.writeTo(Path("${root}/teacher-solutions/CJ-HUMANEVAL-000/src/solution.cj"),"private opaque implementation 987654".toArray())
    let run=TeacherRunManifest("teacher-r1","CJ-HUMANEVAL-000","dataset-v1","gpt-5.6-sol","prompt-hash",2,"complete",0,"evidence-中文😀")
    _=persistCompletedTeacherRuns("${root}/runs/teacher-r1/completed.manifest",[run]);_=persistTeacherRunArtifacts(root,run,"generation","verification");_=persistTeacherSolutionBinding(root,run)
    let evidence="case=confirmed|taxonomy=knowledge_gap|independent=sha256:abc"
    let gap="{\"schemaVersion\":\"ckb-benchmark-gap-v1\",\"datasetVersion\":\"dataset-v1\",\"teacherRunId\":\"teacher-r1\",\"evidenceHash\":\"sha256:${teacherStableHash(evidence)}\",\"evidence\":\"${evidence}\",\"failureTaxonomy\":\"knowledge_gap\",\"knowledgeGapConfirmations\":2,\"caseId\":\"CJ-HUMANEVAL-000\",\"benchmark\":\"Cangjie-HumanEval\",\"taskText\":\"authority bound task\",\"visibleTestExcerpt\":\"\",\"compilerOutput\":\"knowledge gap\",\"missingKnowledge\":\"G-STRING\",\"interfaceId\":\"KI-02\",\"contentFamily\":\"KC-02\",\"updateMechanism\":\"KU-11\",\"targetVersion\":\"1.0.0\",\"officialCitation\":\"https://docs.cangjie-lang.cn/docs/1.0.0/\"}\n"
    File.writeTo(Path("${root}/gap.jsonl"),gap.toArray())
    let options=TeacherCliOptions();options.command="candidate-build";options.root=root;options.manifest="${root}/manifest.jsonl";options.checksum=teacherStableHash(teacherJoin(caseLines(),"\n"));options.authorityGap="${root}/gap.jsonl";options.runId="teacher-r1";options.outputRoot="${root}/exports/${name}";options.model="gpt-5.6-sol"
    let extractorJson="{\"provider\":\"codex\",\"model\":\"gpt-5.6-sol\",\"knowledgeFamily\":\"syntax\",\"concept\":\"UTF-8 String Rune iteration\",\"explanation\":\"Use String Rune iteration for Unicode character boundaries.\",\"example\":\"Declare text.runes(); compare with &&, <, > for 中文😀.\",\"citation\":\"https://docs.cangjie-lang.cn/docs/1.0.0/\",\"sourceClass\":\"official\",\"positiveSource\":\"main() { let text: String = \\\"ok\\\" }\",\"negativeSource\":\"main() { let text: String = unknownName }\",\"boundarySource\":\"main() { let text: String = \\\"中文😀\\\" }\",\"negativeDiagnostic\":\"undefined\",\"positiveDependencyProfile\":\"none\",\"negativeDependencyProfile\":\"none\",\"boundaryDependencyProfile\":\"none\"}"
    let built=buildTeacherCandidates(options,extractorExecutor:RecordingExecutor(results:[TeacherProcessResult(0,extractorJson)]),atomExecutor:AtomRepairExecutor())
    if(!built.ok){throw IllegalStateException(built.diagnostic)}
    options.outputRoot
}

private func reexportOptions(root:String,source:String,name:String):TeacherCliOptions{
    let options=TeacherCliOptions();options.command="candidate-reexport";options.root=root
    options.manifest="${root}/manifest.jsonl";options.checksum=teacherStableHash(teacherJoin(caseLines(),"\n"))
    options.authorityGap="${root}/gap.jsonl";options.runId="teacher-r1";options.sourceExport=source;options.outputRoot="${root}/exports/${name}"
    options
}

private func testCase(id!: String = "CJ-HUMANEVAL-000", version!: String = "dataset-v1"): TeacherCaseManifest {
    TeacherCaseManifest(id, version, "prompt-hash", "starter-hash", "func demo(x: Int64): Int64", "verifier-hash",
        prompt: "Implement demo for 中文😀.", targetVersion: "1.0.0", requiredKnowledgeTags: ["Int64"])
}

private class RecordingExecutor <: TeacherCommandExecutor {
    public let specs = ArrayList<TeacherCommandSpec>()
    private let results: Array<TeacherProcessResult>
    private var index: Int64 = 0
    public var observedInjectedTests = false
    public init(results!: Array<TeacherProcessResult> = [TeacherProcessResult(0, "ok")]) { this.results = results }
    public func execute(spec: TeacherCommandSpec): TeacherProcessResult {
        specs.add(spec)
        if (exists(Path("${spec.cwd}/src/TestMain.cj"))) { observedInjectedTests = true }
        let selected = if (index < results.size) { results[index] } else { results[results.size - 1] }
        index += 1
        for(i in 0..spec.args.size-1){if(spec.args[i]=="--output-last-message"&&i+1<spec.args.size&&selected.exitCode==0&&!selected.timedOut){File.writeTo(Path(spec.args[i+1]),selected.output.toArray())}}
        selected
    }
}
private class AtomRepairExecutor <: TeacherCommandExecutor {
    private var negativeBuilds:Int64=0
    public func execute(spec:TeacherCommandSpec):TeacherProcessResult{
        if(spec.cwd.contains("/negative")&&spec.args.contains("build")){negativeBuilds+=1;return TeacherProcessResult(1,"undefined name 中文😀")}
        TeacherProcessResult(0,"")
    }
}
private class ThrowingCandidateExecutor <: TeacherCommandExecutor {
    public func execute(_: TeacherCommandSpec): TeacherProcessResult {
        throw IllegalStateException("/private/教师😀 token=secret very-long-private-payload-must-not-escape-000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")
    }
}

@Test
public class TeacherRuntimeTest {
    private func tempRoot(name: String): String {
        "/tmp/cangjie-teacher-${name}-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
    }

    @TestCase public func directoryHashSupportsUtf8PathsAndIsStable(): Unit {
        let root = tempRoot("utf8-hash")
        try {
            Directory.create(Path("${root}/中文目录/emoji😀"), recursive: true)
            File.writeTo(Path("${root}/中文目录/emoji😀/知识📚.cj"), "中文内容😀".toArray())
            let first = teacherDirectoryHash(root)
            let second = teacherDirectoryHash(root)
            @Expect(first.startsWith("sha256:"), true)
            @Expect(first, second)
            File.writeTo(Path("${root}/中文目录/emoji😀/知识📚.cj"), "变更内容".toArray())
            @Expect(teacherDirectoryHash(root) != first, true)
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

    // P0-POS-01 / P1-POS-01
    @TestCase public func cliAndFileManifestImport(): Unit {
        let root = tempRoot("manifest")
        try {
            Directory.create(Path(root), recursive: true)
            let text = teacherJoin(caseLines(), "\n") + "\n"
            let path = "${root}/manifest.tsv"
            File.writeTo(Path(path), text.toArray())
            let parsed = parseTeacherCliOptions(["manifest-check", "--manifest", path, "--checksum", teacherStableHash(teacherJoin(caseLines(), "\n"))])
            @Expect(parsed.command, "manifest-check")
            @Expect(parseTeacherCliOptions(["--help"]).command, "help")
            @Expect(loadTeacherDatasetManifestFile(path, parsed.checksum).cases.size, 164)
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

    // P0-NEG-01 / P1-NEG-01
    @TestCase public func malformedUtf8AndUnsafePrivacyAreRejected(): Unit {
        let root = tempRoot("encoding")
        try {
            Directory.create(Path(root), recursive: true)
            File.writeTo(Path("${root}/bad"), [UInt8(0xff), UInt8(0xfe)])
            var invalid = false
            try { _ = teacherReadUtf8File("${root}/bad") } catch (e: Exception) { invalid = e.message == "invalid_response_encoding" }
            @Expect(invalid, true)
            Directory.create(Path("${root}/repo"), recursive: true)
            Directory.create(Path("${root}/private/teacher-runs"), recursive: true)
            @Expect(validateTeacherExecutionPrivacy("${root}/repo", "${root}/repo/runs", true), false)
            @Expect(validateTeacherExecutionPrivacy("${root}/repo", "${root}/private/teacher-runs", true), true)
            @Expect(validateTeacherExecutionPrivacy("${root}/repo", "${root}/private/teacher-runs", false), false)
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

    // P2-UT-01 / P2-BND-01
    @TestCase public func codexUsesExactArgvCwdEnvironmentAndTimeout(): Unit {
        let recorder = RecordingExecutor(results: [TeacherProcessResult(124, "timeout", timedOut: true)])
        let root = tempRoot("process")
        try {
            let result = CodexTeacherProcess("/fake/codex", "gpt-fake", timeoutMillis: 1234, executor: recorder)
                .generate(testCase(), "${root}/workspace", "${root}/session", "${root}/home", "")
            @Expect(result.timedOut, true)
            @Expect(recorder.specs.size, 1)
            @Expect(recorder.specs[0].executable, "/fake/codex")
            @Expect(recorder.specs[0].cwd, "${root}/workspace")
            @Expect(recorder.specs[0].args[0], "exec")
            @Expect(recorder.specs[0].args.contains("workspace-write"), true)
            @Expect(recorder.specs[0].args.contains("-C"), true)
            @Expect(recorder.specs[0].args.contains("--ephemeral"), true)
            @Expect(recorder.specs[0].timeoutMillis, 1234)
            var hasHome = false
            for (entry in recorder.specs[0].env) { if (entry[0] == "CODEX_HOME") { hasHome = true } }
            @Expect(hasHome, false)
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

    // P2-POS-01 / P2-NEG-01
    @TestCase public func verifierInjectsTestsAfterGenerationAndStopsOnFailure(): Unit {
        let root = tempRoot("verify")
        let recorder = RecordingExecutor(results: [TeacherProcessResult(0, "clean"), TeacherProcessResult(7, "build failed")])
        try {
            Directory.create(Path("${root}/tests/CJ-HUMANEVAL-000/tests"), recursive: true)
            Directory.create(Path("${root}/solution/src"), recursive: true)
            File.writeTo(Path("${root}/solution/cjpm.toml"), "original package".toArray())
            File.writeTo(Path("${root}/tests/CJ-HUMANEVAL-000/tests/cjpm.executable.toml"), "package".toArray())
            File.writeTo(Path("${root}/tests/CJ-HUMANEVAL-000/tests/TestMain.cj"), "test".toArray())
            @Expect(exists(Path("${root}/solution/src/TestMain.cj")), false)
            let result = CjpmTeacherVerifier("${root}/tests", executor: recorder).verify(testCase(), "${root}/solution")
            @Expect(recorder.observedInjectedTests, true)
            @Expect(exists(Path("${root}/solution/src/TestMain.cj")), false)
            @Expect(result.exitCode, 7)
            @Expect(recorder.specs.size, 2)
            @Expect(recorder.specs[0].args, ["clean"])
            @Expect(recorder.specs[1].args, ["build", "-i"])
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

    @TestCase public func verifierRejectsExitZeroCangjieEvalFailureWithoutBroadFalsePositives(): Unit {
        let root = tempRoot("verify-business-failure")
        try {
            Directory.create(Path("${root}/tests/CJ-HUMANEVAL-000/tests"), recursive: true)
            Directory.create(Path("${root}/solution/src"), recursive: true)
            File.writeTo(Path("${root}/solution/cjpm.toml"), "original package".toArray())
            File.writeTo(Path("${root}/tests/CJ-HUMANEVAL-000/tests/cjpm.executable.toml"), "package".toArray())
            File.writeTo(Path("${root}/tests/CJ-HUMANEVAL-000/tests/TestMain.cj"), "test".toArray())
            let long=String(Array<Rune>(2000,repeat:r'界'))
            let business="cjpm run finished\nAn exception has occurred:\nException: CangjieEval failure: 中文😀 expected false, actual true /Users/private/token Authorization ${long}"
            let failedRecorder=RecordingExecutor(results:[TeacherProcessResult(0,"clean"),TeacherProcessResult(0,"build"),TeacherProcessResult(0,"test"),TeacherProcessResult(0,business)])
            let failed=CjpmTeacherVerifier("${root}/tests",executor:failedRecorder).verify(testCase(),"${root}/solution")
            @Expect(failed.exitCode,5);@Expect(failedRecorder.specs.size,4)
            @Expect(failed.output.contains("verifier_business_assertion_failed"),true)
            @Expect(failed.output.contains("中文😀 expected false, actual true"),true)
            @Expect(failed.output.contains("/Users"),false);@Expect(failed.output.toAsciiLower().contains("token"),false)
            @Expect(failed.output.contains("Authorization"),false);@Expect(failed.output.toRuneArray().size<512,true)
            let ordinary="CJ-HUMANEVAL-000 ok\nA guide may mention Exception handling and expected/actual values without a benchmark marker."
            let successRecorder=RecordingExecutor(results:[TeacherProcessResult(0,"clean"),TeacherProcessResult(0,"build"),TeacherProcessResult(0,"test"),TeacherProcessResult(0,ordinary)])
            let success=CjpmTeacherVerifier("${root}/tests",executor:successRecorder).verify(testCase(),"${root}/solution")
            @Expect(success.exitCode,0);@Expect(success.output.contains(ordinary),true)
            let encodingRecorder=RecordingExecutor(results:[TeacherProcessResult(0,"clean"),TeacherProcessResult(0,"build"),TeacherProcessResult(0,"test"),TeacherProcessResult(0,"invalid_response_encoding")])
            let encoding=CjpmTeacherVerifier("${root}/tests",executor:encodingRecorder).verify(testCase(),"${root}/solution")
            @Expect(encoding.exitCode,65);@Expect(encoding.output.contains("verifier_invalid_response_encoding"),true)
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

    // P2-E2E-01
    @TestCase public func workspaceEvidenceAtomicPersistenceAndResume(): Unit {
        let root = tempRoot("storage")
        try {
            Directory.create(Path("${root}/starters/CJ-HUMANEVAL-000/starter/src"), recursive: true)
            File.writeTo(Path("${root}/starters/CJ-HUMANEVAL-000/starter/cjpm.toml"), "package".toArray())
            File.writeTo(Path("${root}/starters/CJ-HUMANEVAL-000/starter/src/solution.cj"), "中文😀".toArray())
            let starterHash = teacherDirectoryHash("${root}/starters/CJ-HUMANEVAL-000/starter")
            let actualCase = TeacherCaseManifest("CJ-HUMANEVAL-000", "dataset-v1", "prompt-hash", starterHash,
                "func demo(x: Int64): Int64", "verifier-hash", prompt: "Implement demo")
            let workspace = createTeacherCaseWorkspace(root, "run-1", actualCase, "${root}/starters")
            @Expect(teacherReadUtf8File("${workspace}/src/solution.cj"), "中文😀")
            let run = TeacherRunManifest("run-1", "CJ-HUMANEVAL-000", "dataset-v1", "gpt-fake", "prompt-hash", 1, "complete", 0, "evidence")
            let entries = persistTeacherRunArtifacts(root, run, "generated", "verified")
            @Expect(entries.size, 3)
            @Expect(exists(Path("${root}/runs/run-1/evidence/CJ-HUMANEVAL-000/index.tsv")), true)
            let completedPath = "${root}/runs/run-1/completed.manifest"
            _ = persistCompletedTeacherRuns(completedPath, [run])
            @Expect(loadCompletedTeacherRuns(completedPath).size, 1)
            @Expect(exists(Path(completedPath + ".tmp")), false)
            @Expect(TeacherPaths(root).workspace("run-1", "CJ-HUMANEVAL-000") != TeacherPaths(root).workspace("run-2", "CJ-HUMANEVAL-000"), true)
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }
}
private func testObservation(explanation!: String = "ArrayList stores a growable sequence safely.",
    citation!: String = "https://cangjie-lang.cn/docs/collection", family!: String = "standard_library"): TeacherObservation {
    TeacherObservation("CJ-HUMANEVAL-000", family, "arraylist growth", "1.0.0", explanation, citation, "official", "evidence")
}
private func validCases(): Array<TeacherCaseManifest> {
    let out = ArrayList<TeacherCaseManifest>()
    for (i in 0..164) { out.add(testCase(id: "CJ-HUMANEVAL-${teacherPad3(i)}")) }
    return out.toArray()
}
private func caseLines(): Array<String> { validCases().map({c: TeacherCaseManifest =>
    "{\"schemaVersion\":\"cangjie-humaneval-model-v1\",\"caseId\":\"${c.caseId}\",\"datasetVersion\":\"${c.datasetVersion}\",\"targetVersion\":\"1.0.0\",\"signature\":\"func demo(x: Int64): Int64\",\"prompt\":\"Implement demo\",\"promptHash\":\"prompt-hash\",\"starterHash\":\"starter-hash\",\"requiredKnowledgeTags\":[\"Int64\"]}"
}) }

private class FakeClock <: TeacherClock {
    public func nowMillis(): Int64 { 1000 }
}
private class FakeProcess <: TeacherProcess {
    let result: TeacherProcessResult
    public init(result: TeacherProcessResult) { this.result = result }
    public func generate(caseValue: TeacherCaseManifest, workspace: String, session: String, runtimeHome: String,
        verifierFeedback: String): TeacherProcessResult { result }
}
private class FakeVerifier <: TeacherVerifier {
    let result: TeacherProcessResult
    public init(result: TeacherProcessResult) { this.result = result }
    public func verify(caseValue: TeacherCaseManifest, solutionRoot: String): TeacherProcessResult { result }
}
private class RepairProcess <: TeacherProcess {
    public let feedback = ArrayList<String>()
    public func generate(caseValue: TeacherCaseManifest, workspace: String, session: String, runtimeHome: String,
        verifierFeedback: String): TeacherProcessResult {
        feedback.add(verifierFeedback)
        TeacherProcessResult(0, "generation-${feedback.size}")
    }
}
private class RepairVerifier <: TeacherVerifier {
    var calls: Int64 = 0
    public func verify(caseValue: TeacherCaseManifest, solutionRoot: String): TeacherProcessResult {
        calls += 1
        if (calls == 1) { TeacherProcessResult(1, "编译错误🙂\npublic func leaked(): Unit {}") }
        else { TeacherProcessResult(0, "passed") }
    }
}
private class TransportRetryProcess <: TeacherProcess {
    public var calls: Int64 = 0
    public let feedback = ArrayList<String>()
    public func generate(caseValue: TeacherCaseManifest, workspace: String, session: String, runtimeHome: String,
        verifierFeedback: String): TeacherProcessResult {
        calls += 1
        feedback.add(verifierFeedback)
        if (calls == 1) { return TeacherProcessResult(124, "timeout", timedOut: true) }
        if (calls == 2) { return TeacherProcessResult(7, "provider unavailable") }
        if (calls == 3) { return TeacherProcessResult(0, "") }
        TeacherProcessResult(0, "completed")
    }
}
private func options(generate!: TeacherProcessResult = TeacherProcessResult(0, "solution"),
    verify!: TeacherProcessResult = TeacherProcessResult(0, "tests passed")): TeacherRunOptions {
    TeacherRunOptions("run-1", "/tmp/teacher-fixture", "gpt-fake", FakeProcess(generate), FakeVerifier(verify), FakeClock())
}

@Test
public class TeacherP0P3Test {
    // P0-UT-01
    @TestCase public func p0ContractRoundTripUtf8(): Unit {
        let value = TeacherObservation("CJ-HUMANEVAL-000", "language", "Rune 中文😀", "1.0.0", "换行\n与\t制表", "官方来源", "official", "hash")
        let parsed = parseTeacherObservation(renderTeacherObservation(value))
        @Expect(parsed.concept, value.concept)
        @Expect(parsed.explanation, value.explanation)
        @Expect(teacherStableHash(renderTeacherObservation(parsed)), teacherStableHash(renderTeacherObservation(value)))
        let run = TeacherRunManifest("run", "CJ-HUMANEVAL-000", "v1", "fake", "prompt", 1, "complete", 0, "evidence")
        @Expect(validateTeacherRunManifest(parseTeacherRunManifest(renderTeacherRunManifest(run))), true)
    }
    // P0-BND-01
    @TestCase public func p0MalformedAndBoundaryPathsFailClosed(): Unit {
        var malformedRejected = false
        try { let _ = parseTeacherObservation("not\tenough") } catch (_: Exception) { malformedRejected = true }
        @Expect(malformedRejected, true)
        @Expect(validateTeacherPathBoundary("/tmp/root", "/tmp/root/a/../b"), false)
        @Expect(validateTeacherPathBoundary("/tmp/root", "/tmp/root/中文😀"), true)
    }
    // P0-POS-01
    @TestCase public func p0AllDomainsHaveSeparatedPaths(): Unit {
        let paths = TeacherPaths("/tmp/root")
        @Expect(validateTeacherPathBoundary("/tmp/root", paths.solution("CJ-HUMANEVAL-000"), caseId: "CJ-HUMANEVAL-000"), true)
        @Expect(paths.solution("CJ-HUMANEVAL-000") != paths.observation("CJ-HUMANEVAL-000"), true)
        @Expect(paths.candidateExport().contains("teacher-solutions"), false)
    }
    // P0-NEG-01
    @TestCase public func p0ProductionAndCrossCasePathsRejected(): Unit {
        @Expect(validateTeacherPathBoundary("/tmp/root", "/tmp/root/ckb-data/active"), false)
        @Expect(validateTeacherPathBoundary("/tmp/root", "/tmp/root/runs/CJ-HUMANEVAL-001", caseId: "CJ-HUMANEVAL-000"), false)
        @Expect(validateTeacherPathBoundary("/tmp/root", "/outside/export"), false)
    }

    // P1-UT-01
    @TestCase public func p1ImportsAuthoritativeManifestWithChecksum(): Unit {
        let lines = caseLines()
        let manifest = importTeacherDatasetManifest(lines, teacherStableHash(teacherJoin(lines, "\n")))
        @Expect(manifest.cases.size, 164)
        @Expect(manifest.datasetVersion, "dataset-v1")
    }
    // P1-BND-01
    @TestCase public func p1RejectsDuplicateMissingAndWrongVersion(): Unit {
        let duplicate = validCases()
        duplicate[163] = testCase(id: "CJ-HUMANEVAL-162")
        @Expect(validateTeacherDatasetManifest(TeacherDatasetManifest("dataset-v1", duplicate)), false)
        let wrong = validCases()
        wrong[10] = testCase(id: "CJ-HUMANEVAL-010", version: "other")
        @Expect(validateTeacherDatasetManifest(TeacherDatasetManifest("dataset-v1", wrong)), false)
    }
    // P1-POS-01
    @TestCase public func p1ManifestViewsRemainSeparated(): Unit {
        @Expect(validateTeacherManifestViewBoundary(["promptHash=abc signature=demo"], ["verifierHash=secret"]), true)
    }
    // P1-NEG-01
    @TestCase public func p1ModelVisibleViewRejectsVerifierData(): Unit {
        @Expect(validateTeacherManifestViewBoundary(["reference=/private/answer"], ["verifierHash=x"]), false)
        let lines = caseLines()
        var rejected = false
        try { let _ = importTeacherDatasetManifest(lines, "wrong-checksum") } catch (_: Exception) { rejected = true }
        @Expect(rejected, true)
    }

    // P2-UT-01
    @TestCase public func p2ClassifiesGenerationAndVerificationResults(): Unit {
        @Expect(runTeacherCase(testCase(), options()).status, "verified")
        @Expect(runTeacherCase(testCase(), options(generate: TeacherProcessResult(7, "compile failed"))).status, "generation_failed")
        @Expect(runTeacherCase(testCase(), options(verify: TeacherProcessResult(9, "tests failed"))).status, "verification_failed")
    }
    @TestCase public func p2TeacherRepairsAfterPublicVerifierFailureWithoutLeakingSolution(): Unit {
        let process = RepairProcess(); let verifier = RepairVerifier()
        let run = runTeacherCase(testCase(), TeacherRunOptions("repair-run", "/tmp/teacher-repair-fixture",
            "gpt-5.6-sol", process, verifier, FakeClock(), repairUntilVerified: true))
        @Expect(run.status, "verified")
        @Expect(run.attempt, 2)
        @Expect(process.feedback.size, 2)
        @Expect(process.feedback[0], "")
        @Expect(process.feedback[1].contains("编译错误🙂"), true)
        @Expect(process.feedback[1].contains("public func leaked"), false)
        @Expect(process.feedback[1].contains("[solution_content_redacted]"), true)
    }
    @TestCase public func p2TeacherRetriesTransportFailuresInSameRun(): Unit {
        let process = TransportRetryProcess()
        let run = runTeacherCase(testCase(), TeacherRunOptions("transport-retry-run", "/tmp/teacher-retry-fixture",
            "gpt-5.6-sol", process, FakeVerifier(TeacherProcessResult(0, "passed")), FakeClock(),
            repairUntilVerified: true))
        @Expect(run.status, "verified")
        @Expect(run.attempt, 4)
        @Expect(process.calls, 4)
        @Expect(process.feedback[0], "")
        @Expect(process.feedback[1].contains("transport attempt"), true)
        @Expect(process.feedback[2].contains("transport attempt"), true)
        @Expect(process.feedback[3].contains("transport attempt"), true)
    }
    // P2-BND-01
    @TestCase public func p2TimeoutEmptyUtf8AndResumeAreStable(): Unit {
        @Expect(runTeacherCase(testCase(), options(generate: TeacherProcessResult(0, "", timedOut: true))).status, "timeout")
        @Expect(runTeacherCase(testCase(), options(generate: TeacherProcessResult(0, ""))).status, "empty_output")
        let completed = finalizeTeacherRun(runTeacherCase(testCase(), options(generate: TeacherProcessResult(0, "中文😀"))), true)
        let resumed = runTeacherBatch([testCase()], options(generate: TeacherProcessResult(8, "must not replace")), [completed])
        @Expect(resumed[0].status, "complete")
        @Expect(resumed[0].evidenceHash, completed.evidenceHash)
    }
    // P2-POS-01
    @TestCase public func p2VerifiedRunAndObservationAreSeparated(): Unit {
        let run = finalizeTeacherRun(runTeacherCase(testCase(), options()), true)
        let observation = deriveKnowledgeObservation(testCase(), "language", "Rune boundary", "1.0.0", "Use Rune iteration.", "official-doc", "official", run.evidenceHash)
        @Expect(run.status, "complete")
        @Expect(validateObservationNoSolutionLeak(observation), true)
        @Expect(observation.explanation.contains("solution"), false)
    }
    // P2-NEG-01
    @TestCase public func p2ObservationLeakageIsBlocked(): Unit {
        @Expect(validateObservationNoSolutionLeak(testObservation(explanation: "func solution(x: Int64) { x + 7 }")), false)
        @Expect(validateObservationNoSolutionLeak(testObservation(explanation: "see CJ-HUMANEVAL-099 expectedOutput")), false)
        @Expect(validateObservationNoSolutionLeak(testObservation(citation: "/reference/hidden_test")), false)
    }
    // P2-E2E-01
    @TestCase public func p2ThreeCaseBatchCompletesAndEvidenceVerifies(): Unit {
        let cases = [testCase(), testCase(id: "CJ-HUMANEVAL-001"), testCase(id: "CJ-HUMANEVAL-002")]
        let runs = runTeacherBatch(cases, options(generate: TeacherProcessResult(0, "中文😀 solution")), [])
        @Expect(runs.size, 3)
        var allComplete = true
        for (run in runs) { if (run.status != "complete") { allComplete = false } }
        @Expect(allComplete, true)
        let evidence = ["a", "中文😀", "c"]
        let index = evidence.map({s: String => TeacherEvidenceEntry("fixture", teacherStableHash(s))})
        @Expect(verifyEvidenceIndex(index, evidence), true)
    }

    // P3-UT-01
    @TestCase public func p3IdentityExcludesCaseAndMergeDetectsConflict(): Unit {
        let a = testObservation()
        let b = TeacherObservation("CJ-HUMANEVAL-163", a.knowledgeFamily, a.concept, a.targetVersion, a.explanation, a.citation, a.sourceClass, "other")
        @Expect(canonicalKnowledgeIdentity(a), canonicalKnowledgeIdentity(b))
        @Expect(mergeKnowledgeObservations([a, b]).reviewRequired, false)
        let conflict = testObservation(explanation: "Conflicting semantics")
        @Expect(mergeKnowledgeObservations([a, conflict]).reviewRequired, true)
    }
    // P3-BND-01
    @TestCase public func p3MissingTestCategoryBlocksExport(): Unit {
        var rejected = false
        try { let _ = renderCandidateKnowledgeExport(testObservation(), "independent example", buildKnowledgeAtomTestBundle("positive", "", "boundary")) } catch (_: Exception) { rejected = true }
        @Expect(rejected, true)
    }
    // P3-POS-01
    @TestCase public func p3GeneralAtomPassesExportAndAudits(): Unit {
        let candidate = renderCandidateKnowledgeExport(testObservation(), "Create an empty ArrayList<Int64>.", buildKnowledgeAtomTestBundle("append succeeds", "wrong type rejected", "empty list"))
        @Expect(candidate.tests.isComplete(), true)
        @Expect(validateTeacherCandidateExport(parseTeacherCandidateExport(renderTeacherCandidateExport(candidate))), true)
        @Expect(auditCaseSpecificity(candidate, ["func secretCase"] ).passed, true)
        @Expect(auditCandidateAgainstSolutions(candidate, ["func hiddenAnswer(x: Int64) { return x * 987654 }" ]).passed, true)
    }
    // P3-NEG-01
    @TestCase public func p3CaseSpecificAndSolutionSimilarCandidatesBlocked(): Unit {
        let specific = TeacherCandidateExport("id", "language", "concept", "1.0.0", "For CJ-HUMANEVAL-011", "expectedOutput is 9", "official", "official", "hash", buildKnowledgeAtomTestBundle("p", "n", "b"))
        @Expect(auditCaseSpecificity(specific, []).passed, false)
        let leakedText = "alphaBravo charlieDelta echoFoxtrot golfHotel indiaJuliet kiloLima mikeNovember oscarPapa"
        let leaked = TeacherCandidateExport("id", "language", "concept", "1.0.0", leakedText, "example", "official", "official", "hash", buildKnowledgeAtomTestBundle("p", "n", "b"))
        @Expect(auditCandidateAgainstSolutions(leaked, [leakedText]).passed, false)
        let generic = TeacherCandidateExport("id", "language", "concept", "1.0.0", "Use println for a small demo.", "println(value)", "official", "official", "hash", buildKnowledgeAtomTestBundle("println(value)", "println(value)", "println(value)"))
        @Expect(auditCandidateAgainstSolutions(generic, ["println println println println println println println println println"]).passed, true)
    }

    // P3/P4 candidate control UT/BND/POS/NEG/fake-E2E
    @TestCase public func candidateControlExecutesAllThreeTestCategories(): Unit {
        let bundle = "{\"tests\":[{\"category\":\"positive\",\"source\":\"main() {}\"},{\"category\":\"negative\",\"source\":\"main() { bad }\",\"expectedDiagnostic\":\"undefined\"},{\"category\":\"boundary\",\"source\":\"main() {}\"}]}"
        let passing=RecordingExecutor(results:[TeacherProcessResult(0,""),TeacherProcessResult(0,""),TeacherProcessResult(0,""),TeacherProcessResult(0,""),TeacherProcessResult(1,"undefined name"),TeacherProcessResult(0,""),TeacherProcessResult(0,""),TeacherProcessResult(0,"")])
        @Expect(executeTeacherAtomTestBundle(bundle,"/tmp/teacher-atom-fake",executor:passing).ok, true)
        let failing=RecordingExecutor(results:[TeacherProcessResult(0,""),TeacherProcessResult(2,"build failed")])
        @Expect(executeTeacherAtomTestBundle(bundle,"/tmp/teacher-atom-fail",executor:failing).diagnostic, "atom_test_failed")
        @Expect(executeTeacherAtomTestBundle("not-json","/tmp/teacher-atom-malformed").diagnostic, "malformed_atom_test_bundle")
        try{remove(Path("/tmp/teacher-atom-fake"),recursive:true)}catch(_:Exception){}
        try{remove(Path("/tmp/teacher-atom-fail"),recursive:true)}catch(_:Exception){}
    }

    @TestCase public func candidateControlAcceptsEveryCompletedTeacherAttemptAndRejectsInvalidRuns(): Unit {
        let accepted = TeacherRunManifest("teacher-重试😀", "CJ-HUMANEVAL-000", "dataset-v1", "gpt-5.6-sol",
            "prompt-hash", 1, "complete", 0, "验证证据中文😀")
        let repaired = TeacherRunManifest(accepted.runId, accepted.caseId, accepted.datasetVersion, accepted.modelId,
            accepted.promptHash, 3, accepted.status, accepted.exitCode, accepted.evidenceHash)
        @Expect(teacherRunCompleteForCandidate(accepted, accepted.runId), true)
        @Expect(teacherRunCompleteForCandidate(repaired, accepted.runId), true)
        @Expect(teacherRunCompleteForCandidate(TeacherRunManifest(accepted.runId, accepted.caseId, accepted.datasetVersion,
            accepted.modelId, accepted.promptHash, 0, "complete", 0, accepted.evidenceHash), accepted.runId), false)
        @Expect(teacherRunCompleteForCandidate(TeacherRunManifest(accepted.runId, accepted.caseId, accepted.datasetVersion,
            accepted.modelId, accepted.promptHash, -1, "complete", 0, accepted.evidenceHash), accepted.runId), false)
        @Expect(teacherRunCompleteForCandidate(TeacherRunManifest(accepted.runId, accepted.caseId, accepted.datasetVersion,
            accepted.modelId, accepted.promptHash, 2, "verified", 0, accepted.evidenceHash), accepted.runId), false)
        @Expect(teacherRunCompleteForCandidate(TeacherRunManifest(accepted.runId, accepted.caseId, accepted.datasetVersion,
            accepted.modelId, accepted.promptHash, 2, "complete", 7, accepted.evidenceHash), accepted.runId), false)
        @Expect(teacherRunCompleteForCandidate(repaired, "other-run"), false)
    }

    @TestCase public func candidateAuthorityRelevanceRejectsGenericFloatFactAndAcceptsParseImport():Unit{
        let compiler="error: undeclared identifier 'parse' | Error: failed to compile package `sample`, return code is 1 | '/Users/private/token'"
        let irrelevant=validateTeacherAuthorityRelevance(compiler,"G-FLOAT64",
            "A Float64 variable accepts floating-point literals and rejects Bool.","let value: Float64 = 1.0",
            "main() { let value: Float64 = 1.0 }","main() { let value: Float64 = true }","main() { let value: Float64 = -0.0 }")
        @Expect(irrelevant.ok,false);@Expect(irrelevant.diagnostic,"authority_relevance_failed");@Expect(irrelevant.feedback.contains("parse"),true)
        @Expect(irrelevant.feedback.contains("/Users"),false);@Expect(irrelevant.feedback.toAsciiLower().contains("token"),false)
        let relevant=validateTeacherAuthorityRelevance(compiler,"G-FLOAT64",
            "Import std.convert.* before calling Float64.parse on numeric text.","import std.convert.*\nlet value = Float64.parse(\"1.5\")",
            "import std.convert.*\nmain() { println(Float64.parse(\"1.5\")) }",
            "main() { println(Float64.parse(\"1.5\")) }",
            "import std.convert.*\nmain() { println(Float64.parse(\"-0.0\")) }")
        @Expect(relevant.ok,true);@Expect(relevant.anchors.contains("parse"),true)
        let negativeOnly=validateTeacherAuthorityRelevance(compiler,"G-FLOAT64",
            "Call parse after importing the conversion package.","Float64.parse converts numeric text.",
            "main() { let value: Float64 = 1.0 }","main() { println(Float64.parse(\"bad\")) }","main() { let value: Float64 = -0.0 }")
        @Expect(negativeOnly.ok,false)
        let parseWithoutImport=validateTeacherAuthorityRelevance(compiler,"G-FLOAT64",
            "Float64.parse converts numeric text.","Call Float64.parse on a numeric String.",
            "main() { println(Float64.parse(\"1.5\")) }","main() { println(Float64.parse(\"bad\")) }","main() { println(Float64.parse(\"-0.0\")) }")
        @Expect(parseWithoutImport.ok,false);@Expect(parseWithoutImport.feedback.contains("std.convert"),true)
        let commentOnly=validateTeacherAuthorityRelevance(compiler,"G-FLOAT64",
            "Import std.convert.* and call Float64.parse.","Use Float64.parse after the import.",
            "// import std.convert.*\nmain() { println(\"Float64.parse(\") }","main() { println(Float64.parse(\"bad\")) }",
            "// import std.convert.*\nmain() { println(\"Float64.parse(\") }")
        @Expect(commentOnly.ok,false)
    }

    @TestCase public func candidateAuthorityRelevanceKeepsKnownGapFamiliesAndFeedbackSafe():Unit{
        let fixtures=[
            ("imports package 'std.text' but it is not declared","G-CJPM-DEPENDENCY","Declare std.text as an explicit dependency.","import std.text.*"),
            ("expected 001, actual 484849","G-STRING-INDEX-BYTES","String indexing can yield UTF-8 bytes; use Rune indexing for characters.","String byte UInt8 index"),
            ("expected '{' after 'if', found '||'","G-LOGICAL-OR","Use || inside a complete if condition.","if (a || b)"),
            ("invalid binary operator '==' on type 'UInt8' and 'Rune'","G-RUNE-BYTE-COMPARE","Do not compare UInt8 == Rune without conversion.","UInt8 == Rune")]
        for(f in fixtures){let r=validateTeacherAuthorityRelevance(f[0],f[1],f[2],f[3],f[3],f[3],f[3]);@Expect(r.ok,true)}
        let long="中文😀"+String(Array<Rune>(2000,repeat:r'界'))+" '/Users/private/token' 'parse' Authorization secret"
        let unsafeResult=validateTeacherAuthorityRelevance(long,"G-FLOAT64","generic Float64 fact","Float64 literal","Float64","Float64","Float64")
        @Expect(unsafeResult.ok,false);@Expect(unsafeResult.feedback.toRuneArray().size<=803,true)
        @Expect(unsafeResult.feedback.contains("/Users"),false);@Expect(unsafeResult.feedback.toAsciiLower().contains("token"),false);@Expect(unsafeResult.feedback.contains("Authorization"),false)
    }

    @TestCase public func candidateAuthorityRelevanceRequiresExactLogicalOrConditionPlacement():Unit{
        let compiler="error: expected '{', found '||' | error: trailing closure can only be used on function calls with function or variable names"
        let narrative="Cangjie logical OR uses Bool || Bool inside the complete parenthesized if or while condition; closing the condition before || makes the parser expect the block opening brace. 中文😀"
        let positive="main() { let left: Bool = true; let right: Bool = false; if (left || right) { println(left) } }"
        let boundary="main() { let left: Bool = false; let right: Bool = false; while (left || right) { break } }"
        let negative="main() { let left: Bool = true; let right: Bool = false; if (left) || (right) { println(left) } }"
        let relevant=validateTeacherAuthorityRelevance(compiler,"G-LOGICAL-OR-CONDITION",narrative,narrative,positive,negative,boundary)
        @Expect(relevant.ok,true);@Expect(relevant.anchors.contains("||"),true)

        let typeError="main() { let left: Bool = true; let right: Int64 = 1; if (left || right) { println(left) } }"
        let keyword="main() { let left: Bool = true; let right: Bool = false; if (left or right) { println(left) } }"
        let funcMain=positive.replace("main()","func main()")
        let validNegative=positive
        let disguised="main() { let left: Bool = true; let right: Bool = false; println(\"if (left) || (right) {\"); // if (left) || (right) {\n if (left || right) { println(left) } }"
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-LOGICAL-OR-CONDITION",narrative,narrative,positive,typeError,boundary).ok,false)
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-LOGICAL-OR-CONDITION",narrative,narrative,keyword,negative,boundary).ok,false)
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-LOGICAL-OR-CONDITION",narrative,narrative,funcMain,negative,boundary).ok,false)
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-LOGICAL-OR-CONDITION",narrative,narrative,positive,validNegative,boundary).ok,false)
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-LOGICAL-OR-CONDITION",narrative,narrative,positive,disguised,boundary).ok,false)
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-LOGICAL-OR-CONDITION",narrative,narrative,positive,negative,boundary,
            positiveDependencyProfile:"stdx-magic",negativeDependencyProfile:"none",boundaryDependencyProfile:"none").ok,false)

        let unsafeEvidence=compiler+" /Users/private/token Authorization Bearer secret "+String(Array<Rune>(2000,repeat:r'界'))
        let unsafeResult=validateTeacherAuthorityRelevance(unsafeEvidence,"G-LOGICAL-OR-CONDITION","generic","generic","main(){}","main(){}","main(){}")
        @Expect(unsafeResult.ok,false);@Expect(unsafeResult.feedback.toRuneArray().size<=803,true)
        @Expect(unsafeResult.feedback.contains("/Users"),false);@Expect(unsafeResult.feedback.toAsciiLower().contains("token"),false)
        @Expect(unsafeResult.feedback.contains("Authorization"),false);@Expect(unsafeResult.feedback.contains("😀"),false)

        let unrelated=validateTeacherAuthorityRelevance("invalid binary operator '==' on type 'UInt8' and 'Rune'","G-RUNE-BYTE-COMPARE",
            "Do not compare UInt8 == Rune without conversion.","UInt8 == Rune","UInt8 == Rune","UInt8 == Rune","UInt8 == Rune")
        @Expect(unrelated.ok,true)
    }

    @TestCase public func candidateAuthorityRelevanceRequiresExactStringCaseRuneApis():Unit{
        let compiler="error: 'toLower' is not a member of struct 'String'"
        let narrative="String.toLower() is unavailable. String.toAsciiLower() converts ASCII only and leaves non-ASCII characters unchanged. For Unicode case conversion, import std.unicode.*, obtain Rune values, and call Rune.toLowerCase(). 中文😀"
        let positive="main(){ let text: String = \"XYZ\"; let lowered: String = text.toAsciiLower(); if (lowered != \"xyz\") { throw IllegalStateException(\"ascii lower failed\") } }"
        let boundary="import std.unicode.*\nmain(){ let text: String = \"中😀\"; let lowered: String = text.toAsciiLower(); if (lowered != text) { throw IllegalStateException(\"non ascii changed\") }; let rune: Rune = r'中'; println(rune.toLowerCase()) }"
        let negative="main(){ let text: String = \"ABC\"; println(text.toLower()) }"
        let relevant=validateTeacherAuthorityRelevance(compiler,"G-STRING-CASE-RUNE",narrative,narrative,positive,negative,boundary)
        @Expect(relevant.ok,true);@Expect(relevant.anchors.contains("toasciilower"),true)
        @Expect(relevant.anchors.contains("std.unicode"),true);@Expect(relevant.anchors.contains("tolowercase"),true)

        let generic="Use a lowercase helper when processing text."
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-STRING-CASE-RUNE",generic,generic,positive,negative,boundary).ok,false)
        let wrongApi=positive.replace("toAsciiLower","toLowerAscii")
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-STRING-CASE-RUNE",narrative,narrative,wrongApi,negative,boundary).ok,false)
        let wrongNegative=negative.replace("toLower()","toAsciiLower()")
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-STRING-CASE-RUNE",narrative,narrative,positive,wrongNegative,boundary).ok,false)
        let noPreservation=boundary.replace("if (lowered != text) { throw IllegalStateException(\"non ascii changed\") }; ","")
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-STRING-CASE-RUNE",narrative,narrative,positive,negative,noPreservation).ok,false)
        let stringReceiver=boundary.replace("let rune: Rune = r'中'; println(rune.toLowerCase())","println(text.toLowerCase())")
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-STRING-CASE-RUNE",narrative,narrative,positive,negative,stringReceiver).ok,false)
        let disguised="main(){ let text: String = \"ABC\"; println(\"text.toAsciiLower()\"); // text.toAsciiLower()\n println(text) }"
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-STRING-CASE-RUNE",narrative,narrative,disguised,negative,boundary).ok,false)
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-STRING-CASE-RUNE",narrative,narrative,positive,negative,boundary,
            positiveDependencyProfile:"stdx-magic",negativeDependencyProfile:"none",boundaryDependencyProfile:"none").ok,false)

        let unsafeEvidence=compiler+" /Users/private/token Authorization Bearer secret "+String(Array<Rune>(2000,repeat:r'界'))
        let unsafeResult=validateTeacherAuthorityRelevance(unsafeEvidence,"G-STRING-CASE-RUNE",generic,generic,disguised,wrongNegative,disguised)
        @Expect(unsafeResult.ok,false);@Expect(unsafeResult.feedback.toRuneArray().size<=803,true)
        @Expect(unsafeResult.feedback.contains("/Users"),false);@Expect(unsafeResult.feedback.toAsciiLower().contains("token"),false)
        @Expect(unsafeResult.feedback.contains("Authorization"),false);@Expect(unsafeResult.feedback.contains("😀"),false)

        let unrelated=validateTeacherAuthorityRelevance("invalid binary operator '==' on type 'UInt8' and 'Rune'","G-RUNE-BYTE-COMPARE",
            "Do not compare UInt8 == Rune without conversion.","UInt8 == Rune","UInt8 == Rune","UInt8 == Rune","UInt8 == Rune")
        @Expect(unrelated.ok,true)
    }

    @TestCase public func candidateAuthorityRelevanceRequiresExactRuneUnicodeCaseConversion():Unit{
        let compiler="error: undeclared identifier 'toUpper'; undeclared identifier 'toLower'"
        let narrative="For a Rune, import std.unicode.* and call Rune.toUpperCase() and Rune.toLowerCase(); Rune.toUpper() and Rune.toLower() are not declared. 中文😀"
        let positive="import std.unicode.*\nmain(){ let value: Rune = r'a'; println(value.toUpperCase()); println(value.toLowerCase()) }"
        let boundary="import std.unicode.*\nmain(){ let chinese: Rune = r'中'; let emoji: Rune = r'😀'; println(chinese.toUpperCase()); println(chinese.toLowerCase()); println(emoji.toUpperCase()); println(emoji.toLowerCase()) }"
        let negative="import std.unicode.*\nmain(){ let lower: Rune = r'a'; let upper: Rune = r'Z'; println(lower.toUpper()); println(upper.toLower()) }"
        let relevant=validateTeacherAuthorityRelevance(compiler,"G-RUNE-UNICODE-CASE",narrative,narrative,positive,negative,boundary)
        @Expect(relevant.ok,true);@Expect(relevant.anchors.contains("std.unicode"),true)
        @Expect(relevant.anchors.contains("touppercase"),true);@Expect(relevant.anchors.contains("tolowercase"),true)

        let stale="A Rune literal contains exactly one Unicode scalar."
        let staleSource="main(){ let chinese: Rune = r'中'; let emoji: Rune = r'😀'; println(chinese); println(emoji) }"
        let staleResult=validateTeacherAuthorityRelevance(compiler,"G-RUNE-UNICODE-CASE",stale,staleSource,staleSource,staleSource,staleSource)
        @Expect(staleResult.ok,false);@Expect(staleResult.feedback.contains("Rune.toUpperCase()"),true)
        @Expect(staleResult.feedback.contains("Rune.toLowerCase()"),true);@Expect(staleResult.feedback.contains("CJ-HUMANEVAL"),false)

        let missingImport=positive.replace("import std.unicode.*\n","")
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-RUNE-UNICODE-CASE",narrative,narrative,missingImport,negative,boundary).ok,false)
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-RUNE-UNICODE-CASE",narrative,narrative,positive,negative,positive).ok,false)
        let wrongNegative="import std.unicode.*\nmain(){ let value: Rune = r'a'; println(value.toUpperCase()); println(value.toLowerCase()) }"
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-RUNE-UNICODE-CASE",narrative,narrative,positive,wrongNegative,boundary).ok,false)
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-RUNE-UNICODE-CASE",narrative,narrative,positive,negative,boundary,
            positiveDependencyProfile:"stdx-magic",negativeDependencyProfile:"none",boundaryDependencyProfile:"none").ok,false)
        let stringReceivers="import std.unicode.*\nmain(){ let value: String = \"a\"; println(value.toUpperCase()); println(value.toLowerCase()); let rune: Rune = r'a'; println(rune) }"
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-RUNE-UNICODE-CASE",narrative,narrative,stringReceivers,negative,boundary).ok,false)
        let disguised="import std.unicode.*\nmain(){ let value: Rune = r'a'; println(\"value.toUpperCase() value.toLowerCase()\"); // value.toUpperCase(); value.toLowerCase()\n println(value) }"
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-RUNE-UNICODE-CASE",narrative,narrative,disguised,negative,disguised).ok,false)
        let blockDisguised="import std.unicode.*\nmain(){ let value: Rune = r'a'; /* value.toUpperCase(); value.toLowerCase() */ println(value) }"
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-RUNE-UNICODE-CASE",narrative,narrative,blockDisguised,negative,blockDisguised).ok,false)

        let unsafeEvidence=compiler+" 中文😀 '/Users/private/token' Authorization Bearer secret "+String(Array<Rune>(2000,repeat:r'界'))
        let unsafeResult=validateTeacherAuthorityRelevance(unsafeEvidence,"G-RUNE-UNICODE-CASE",stale,staleSource,staleSource,staleSource,staleSource)
        @Expect(unsafeResult.ok,false);@Expect(unsafeResult.feedback.toRuneArray().size<=803,true)
        @Expect(unsafeResult.feedback.contains("/Users"),false);@Expect(unsafeResult.feedback.toAsciiLower().contains("token"),false)
        @Expect(unsafeResult.feedback.contains("Authorization"),false);@Expect(unsafeResult.feedback.contains("😀"),false)

        let unrelated=validateTeacherAuthorityRelevance("invalid binary operator '==' on type 'UInt8' and 'Rune'","G-RUNE-BYTE-COMPARE",
            "Do not compare UInt8 == Rune without conversion.","UInt8 == Rune","UInt8 == Rune","UInt8 == Rune","UInt8 == Rune")
        @Expect(unrelated.ok,true)
    }

    @TestCase public func candidateAuthorityRelevanceDerivesUnicodeStringAndBytePrerequisites():Unit{
        let unicodeCompiler="undeclared identifier 'isLowerCase'; undeclared identifier 'isUpperCase'"
        let unicodeWithoutImport=validateTeacherAuthorityRelevance(unicodeCompiler,"G-RUNE-UNICODE-IMPORT",
            "Call Rune.isLowerCase and Rune.isUpperCase.","r'a'.isLowerCase(); r'A'.isUpperCase()",
            "main(){ println(r'a'.isLowerCase()); println(r'A'.isUpperCase()) }",
            "main(){ println(r'a'.isLowerCase()); println(r'A'.isUpperCase()) }",
            "main(){ println(r'中'.isLowerCase()); println(r'中'.isUpperCase()) }")
        @Expect(unicodeWithoutImport.ok,false);@Expect(unicodeWithoutImport.feedback.contains("std.unicode"),true)
        @Expect(unicodeWithoutImport.feedback.toAsciiLower().contains("positive and boundary sources must each import std.unicode.*"),true)
        @Expect(unicodeWithoutImport.feedback.contains("isLowerCase() and isUpperCase()"),true)
        @Expect(unicodeWithoutImport.feedback.toAsciiLower().contains("negative source must omit that import"),true)
        @Expect(unicodeWithoutImport.feedback.toAsciiLower().contains("negative source must omit that import and call both"),true)
        @Expect(unicodeWithoutImport.feedback.contains("CJ-HUMANEVAL"),false)
        let unicodeNegativeOnlyOne=validateTeacherAuthorityRelevance(unicodeCompiler,"G-RUNE-UNICODE-IMPORT",
            "Import std.unicode.* for Rune.isLowerCase and Rune.isUpperCase.","import std.unicode.* before both methods.",
            "import std.unicode.*\nmain(){ println(r'a'.isLowerCase()); println(r'A'.isUpperCase()) }",
            "main(){ println(r'a'.isLowerCase()) }",
            "import std.unicode.*\nmain(){ println(r'中'.isLowerCase()); println(r'中'.isUpperCase()) }")
        @Expect(unicodeNegativeOnlyOne.ok,false)
        @Expect(unicodeNegativeOnlyOne.feedback.toAsciiLower().contains("negative source must omit that import and call both"),true)
        let unicodePositiveOnlyOne=validateTeacherAuthorityRelevance(unicodeCompiler,"G-RUNE-UNICODE-IMPORT",
            "Import std.unicode.* for Rune.isLowerCase and Rune.isUpperCase.","import std.unicode.* before both methods.",
            "import std.unicode.*\nmain(){ println(r'a'.isLowerCase()) }",
            "main(){ println(r'a'.isLowerCase()); println(r'A'.isUpperCase()) }",
            "import std.unicode.*\nmain(){ println(r'中'.isLowerCase()); println(r'中'.isUpperCase()) }")
        @Expect(unicodePositiveOnlyOne.ok,false)
        let unicodeRelevant=validateTeacherAuthorityRelevance(unicodeCompiler,"G-RUNE-UNICODE-IMPORT",
            "Import std.unicode.* for Rune.isLowerCase and Rune.isUpperCase.","import std.unicode.* before both methods.",
            "import std.unicode.*\nmain(){ println(r'a'.isLowerCase()); println(r'A'.isUpperCase()) }",
            "main(){ println(r'a'.isLowerCase()); println(r'A'.isUpperCase()) }",
            "import std.unicode.*\nmain(){ println(r'中'.isLowerCase()); println(r'中'.isUpperCase()) }")
        @Expect(unicodeRelevant.ok,true)

        let stringCompiler="expected 'Struct-String', found 'UInt8'; expected 'Rune', found 'UInt8'"
        let generic=validateTeacherAuthorityRelevance(stringCompiler,"G-STRING-RUNE-CONTAINS-STRINGBUILDER-APPEND",
            "A String stores text.","Use String values.","main(){}","main(){ bad }","main(){}")
        @Expect(generic.ok,false);@Expect(generic.feedback.contains("struct-string"),false);@Expect(generic.feedback.toAsciiLower().contains("stringbuilder.append"),true)
        @Expect(generic.feedback.toAsciiLower().contains("positive and boundary sources must each demonstrate uint8, rune, torunearray"),true)
        @Expect(generic.feedback.contains("Array<Rune>.contains(Rune)"),true)
        @Expect(generic.feedback.contains("String.contains(Rune) or Array<UInt8>.contains(Rune)"),true)
        @Expect(generic.feedback.contains("/Users"),false);@Expect(generic.feedback.toAsciiLower().contains("solution"),false)
        let stringSource="main(){ let byte: UInt8 = UInt8(65); let rune: Rune = r'A'; let runes: Array<Rune> = \"A\".toRuneArray(); let found = \"A\".contains(\"A\"); let builder = StringBuilder(); builder.append(rune); println(found); println(byte); println(runes.size) }"
        let stringRelevant=validateTeacherAuthorityRelevance(stringCompiler,"G-STRING-RUNE-CONTAINS-STRINGBUILDER-APPEND",
            "String iteration can yield UInt8; convert to Rune with toRuneArray, pass String to contains, and Rune to StringBuilder.append.",
            "Use contains, StringBuilder.append, UInt8, Rune, and toRuneArray together.",stringSource,
            "main(){ let byte: UInt8 = UInt8(65); println(\"A\".contains(byte)) }",stringSource)
        @Expect(stringRelevant.ok,true)
        let containsSource="main(){ let text:String=\"中😀\"; let byte:UInt8=UInt8(65); let runes:Array<Rune>=text.toRuneArray(); let rune:Rune=r'中'; println(runes.contains(rune)); println(byte) }"
        let containsNegative="main(){ let text:String=\"A\"; let rune:Rune=r'A'; println(text.contains(rune)) }"
        let containsOnly=validateTeacherAuthorityRelevance(stringCompiler,"G-STRING-RUNE-CONTAINS",
            "Direct String iteration yields UInt8; use toRuneArray for an Array<Rune>, then call Array<Rune>.contains with a Rune instead of String.contains(Rune).",
            "Use UInt8, Rune, toRuneArray, and Array<Rune>.contains(Rune) together.",containsSource,containsNegative,containsSource)
        @Expect(containsOnly.ok,true);@Expect(containsOnly.anchors.contains("stringbuilder.append"),false)
        let byteArrayNegative="main(){ let bytes:Array<UInt8>=[UInt8(65)]; let rune:Rune=r'A'; println(bytes.contains(rune)) }"
        @Expect(validateTeacherAuthorityRelevance(stringCompiler,"G-STRING-RUNE-CONTAINS",
            "Direct String iteration yields UInt8; use toRuneArray for an Array<Rune>, then call Array<Rune>.contains with a Rune instead of Array<UInt8>.contains(Rune).",
            "Use UInt8, Rune, toRuneArray, and Array<Rune>.contains(Rune) together.",containsSource,byteArrayNegative,containsSource).ok,true)
        let wrongPositive="main(){ let byte:UInt8=UInt8(65); let rune:Rune=r'A'; let runes:Array<Rune>=\"A\".toRuneArray(); println(\"A\".contains(String(runes))); println(byte); println(rune) }"
        let wrongPositiveResult=validateTeacherAuthorityRelevance(stringCompiler,"G-STRING-RUNE-CONTAINS",
            "Direct String iteration yields UInt8; use toRuneArray for Rune values and contains.","UInt8 Rune toRuneArray contains",wrongPositive,containsNegative,wrongPositive)
        @Expect(wrongPositiveResult.ok,false);@Expect(wrongPositiveResult.feedback.contains("Array<Rune> receiver"),true)
        @Expect(wrongPositiveResult.feedback.contains("runes: Array<Rune>"),true)
        @Expect(wrongPositiveResult.feedback.contains("needle: Rune"),true)
        @Expect(wrongPositiveResult.feedback.contains("text: String"),true)
        @Expect(wrongPositiveResult.feedback.contains("bytes: Array<UInt8>"),true)
        @Expect(wrongPositiveResult.feedback.contains("explanation or example must state exactly Array<Rune>.contains(Rune)"),true)
        for(requiredFeedback in ["explicit type annotations","runes: Array<Rune>","toRuneArray","needle: Rune","byte: UInt8",
            "text: String","text.contains(needle)","bytes: Array<UInt8>","bytes.contains(needle)","mismatched-types diagnostic",
            "String construction from UInt8","String.contains(String)"]){
            @Expect(wrongPositiveResult.feedback.contains(requiredFeedback),true)
        }
        let inferredPositive="main(){ let text=\"A\"; let byte=UInt8(65); let runes=text.toRuneArray(); let needle=r'A'; println(runes.contains(needle)); println(byte) }"
        let inferredResult=validateTeacherAuthorityRelevance(stringCompiler,"G-STRING-RUNE-CONTAINS",
            "Use Array<Rune>.contains(Rune) after toRuneArray with UInt8 kept distinct.","Array<Rune>.contains(Rune)",inferredPositive,containsNegative,inferredPositive)
        @Expect(inferredResult.ok,false);@Expect(inferredResult.feedback.contains("explicit type annotations"),true)
        let observedWrongNegative="main(){ let byte:UInt8=UInt8(65); let rune:Rune=r'A'; let bytes:Array<UInt8>=[byte]; let text=String([byte]); println(\"A\".contains(\"A\")); println(rune); println(bytes.size); println(text) }"
        let wrongNegativeResult=validateTeacherAuthorityRelevance(stringCompiler,"G-STRING-RUNE-CONTAINS",
            "Direct String iteration yields UInt8; use toRuneArray for an Array<Rune>, then call Array<Rune>.contains with a Rune.",
            "Use UInt8, Rune, toRuneArray, and Array<Rune>.contains(Rune) together.",containsSource,observedWrongNegative,containsSource)
        @Expect(wrongNegativeResult.ok,false);@Expect(wrongNegativeResult.feedback.contains("String receiver"),true)
        let disguised="// Array<Rune>.contains(Rune)\nmain(){ println(\"UInt8 Rune toRuneArray contains\") }"
        @Expect(validateTeacherAuthorityRelevance(stringCompiler,"G-STRING-RUNE-CONTAINS","UInt8 Rune toRuneArray contains","UInt8 Rune toRuneArray contains",disguised,containsNegative,disguised).ok,false)
        @Expect(stringRelevant.anchors.contains("stringbuilder.append"),true)

        let byteRelevant=validateTeacherAuthorityRelevance("invalid binary operator '<' on type 'UInt8' and 'Rune'","G-RUNE-BYTE-COMPARE",
            "A UInt8 byte cannot compare with Rune; use toRuneArray for character comparison.","Use UInt8 and Rune values with toRuneArray.",
            "main(){ let byte: UInt8=UInt8(65); let rune: Rune=\"A\".toRuneArray()[0]; println(byte); println(rune) }",
            "main(){ let byte: UInt8=UInt8(65); let rune: Rune=r'A'; println(byte < rune) }",
            "main(){ let byte: UInt8=UInt8(65); let rune: Rune=\"中\".toRuneArray()[0]; println(byte); println(rune) }")
        @Expect(byteRelevant.ok,true)
        let commentOnly=validateTeacherAuthorityRelevance(stringCompiler,"G-STRING-RUNE-CONTAINS-STRINGBUILDER-APPEND",
            "UInt8 Rune contains StringBuilder.append toRuneArray.","UInt8 Rune contains StringBuilder.append toRuneArray.",
            "// UInt8 Rune .contains( StringBuilder .append( .toRuneArray(\nmain(){ println(\"UInt8 Rune contains StringBuilder.append toRuneArray\") }",
            "main(){ bad }","// UInt8 Rune contains StringBuilder.append toRuneArray\nmain(){}")
        @Expect(commentOnly.ok,false)
        let unsafeDerived=validateTeacherAuthorityRelevance(stringCompiler+" 中文😀 '/Users/private/token' Authorization "+String(Array<Rune>(2000,repeat:r'界')),
            "G-STRING-RUNE-CONTAINS-STRINGBUILDER-APPEND","generic","generic","main(){}","main(){bad}","main(){}")
        @Expect(unsafeDerived.ok,false);@Expect(unsafeDerived.feedback.toRuneArray().size<=803,true)
        @Expect(unsafeDerived.feedback.contains("/Users"),false);@Expect(unsafeDerived.feedback.toAsciiLower().contains("token"),false);@Expect(unsafeDerived.feedback.contains("Authorization"),false)
    }

    @TestCase public func candidateAuthorityRelevanceSeparatesPositiveAndNegativeApiAnchors():Unit{
        let repeatRelevant=validateTeacherAuthorityRelevance("unknown named argument prefix 'item:'","G-ARRAY-REPEAT",
            "Use repeat: to fill an Array; item: is not a valid named argument.","Array<Int64>(3, repeat: 7) replaces item:.",
            "main(){ let values=Array<Int64>(3, repeat: 7); println(values.size) }",
            "main(){ let values=Array<Int64>(3, item: 7); println(values.size) }",
            "main(){ let values=Array<Rune>(0, repeat: r'中'); println(values.size) }")
        @Expect(repeatRelevant.ok,true)
        let repeatWrong=validateTeacherAuthorityRelevance("unknown named argument prefix 'item:'","G-ARRAY-REPEAT",
            "Use item: for Array construction.","item:","main(){ let x=Array<Int64>(1,item:1) }","main(){ bad }","main(){ let x=Array<Int64>(0,item:1) }")
        @Expect(repeatWrong.ok,false);@Expect(repeatWrong.feedback.contains("repeat"),true)

        let runeArrayRelevant=validateTeacherAuthorityRelevance("undeclared identifier 'fromRuneArray'","G-STRING-RUNE-ARRAY",
            "Construct String from Array<Rune> with String(runes); fromRuneArray does not exist.","Use String(Array<Rune>) instead of fromRuneArray.",
            "main(){ let runes:Array<Rune>=[r'A']; let text=String(runes); println(text) }",
            "main(){ let runes:Array<Rune>=[r'A']; let text=String.fromRuneArray(runes); println(text) }",
            "main(){ let runes:Array<Rune>=[r'中',r'😀']; let text=String(runes); println(text) }")
        @Expect(runeArrayRelevant.ok,true)
        let runeArrayWrong=validateTeacherAuthorityRelevance("undeclared identifier 'fromRuneArray'","G-STRING-RUNE-ARRAY",
            "Call fromRuneArray.","fromRuneArray", "main(){ let x=String.fromRuneArray([]) }","main(){ let x=String.fromRuneArray([]) }","main(){ let x=String.fromRuneArray([]) }")
        @Expect(runeArrayWrong.ok,false);@Expect(runeArrayWrong.feedback.contains("string-constructor"),true)
    }

    @TestCase public func candidateAuthorityRelevanceRequiresStringRuneIterationEvidence():Unit{
        let compiler="invalid binary operator '==' on type 'UInt8' and 'Rune' 中文😀 /Users/private/token Authorization"
        let narrative="Direct String iteration yields UInt8 bytes, which are distinct from Rune values. Compare values of the same type, or call toRuneArray and compare Rune with Rune using ==."
        let positive="main(){ let text:String=\"中😀\"; for(byte in text){ let same:UInt8=byte; println(byte==same) }; let runes:Array<Rune>=text.toRuneArray(); for(rune in runes){ let same:Rune=rune; println(rune==same) } }"
        let boundary="main(){ let text:String=\"\"; for(byte in text){ let same:UInt8=byte; println(byte==same) }; let runes:Array<Rune>=text.toRuneArray(); for(rune in runes){ let same:Rune=rune; println(rune==same) } }"
        let negative="main(){ let text:String=\"()\"; for(byte in text){ println(byte==r'(') } }"
        let relevant=validateTeacherAuthorityRelevance(compiler,"G-STRING-RUNE-ITERATION",narrative,narrative,positive,negative,boundary)
        @Expect(relevant.ok,true)

        let disguised="// UInt8 Rune toRuneArray ==\nmain(){ println(1==1); println(\"String iteration UInt8 Rune toRuneArray\") }"
        let disguisedResult=validateTeacherAuthorityRelevance(compiler,"G-STRING-RUNE-ITERATION",narrative,narrative,disguised,negative,disguised)
        @Expect(disguisedResult.ok,false)
        @Expect(disguisedResult.feedback.contains("Direct String iteration"),true)
        @Expect(disguisedResult.feedback.contains("positive and boundary"),true)

        let wrongNegative="main(){ let text:String=\"abc\"; for(byte in text){ let same:UInt8=byte; println(byte==same) } }"
        let wrongNegativeResult=validateTeacherAuthorityRelevance(compiler,"G-STRING-RUNE-ITERATION",narrative,narrative,positive,wrongNegative,boundary)
        @Expect(wrongNegativeResult.ok,false)
        let unrelated=validateTeacherAuthorityRelevance("invalid binary operator '<' on type 'UInt8' and 'Rune'","G-RUNE-BYTE-COMPARE",
            "UInt8 and Rune are distinct; use toRuneArray before Rune comparison.","UInt8 Rune toRuneArray",
            positive,"main(){ let byte:UInt8=UInt8(65); println(byte<r'A') }",boundary)
        @Expect(unrelated.feedback.contains("Direct String iteration"),false)
        @Expect(disguisedResult.feedback.contains("/Users"),false);@Expect(disguisedResult.feedback.toAsciiLower().contains("token"),false)
    }

    @TestCase public func candidateAuthorityRelevanceRequiresGlobalFloat64Abs():Unit{
        let compiler="undeclared identifier 'abs' 中文😀 /Users/private/token Authorization"
        let narrative="Float64 absolute value uses the global function abs(value), not a receiver member method value.abs()."
        let positive="main(){ let negative:Float64=-3.5; println(abs(negative)) }"
        let boundary="main(){ let negativeZero:Float64=-0.0; let positiveZero:Float64=0.0; println(abs(-0.0)); println(abs(0.0)); println(negativeZero); println(positiveZero) }"
        let negative="main(){ let value:Float64=-3.5; println(value.abs()) }"
        let relevant=validateTeacherAuthorityRelevance(compiler,"G-FLOAT64-ABS",narrative,narrative,positive,negative,boundary)
        @Expect(relevant.ok,true)

        let wrongPositive="main(){ let value:Float64=-3.5; println(value.abs()) }"
        let wrongPositiveResult=validateTeacherAuthorityRelevance(compiler,"G-FLOAT64-ABS",narrative,narrative,wrongPositive,negative,boundary)
        @Expect(wrongPositiveResult.ok,false);@Expect(wrongPositiveResult.feedback.contains("global abs(value)"),true)
        let wrongNegativeResult=validateTeacherAuthorityRelevance(compiler,"G-FLOAT64-ABS",narrative,narrative,positive,positive,boundary)
        @Expect(wrongNegativeResult.ok,false)
        let wrongBoundary="main(){ let zero:Float64=0.0; println(abs(zero)) }"
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-FLOAT64-ABS",narrative,narrative,positive,negative,wrongBoundary).ok,false)
        let disguised="// abs(-3.5)\nmain(){ let value:Float64=-3.5; println(\"global abs(value)\"); println(value) }"
        let disguisedResult=validateTeacherAuthorityRelevance(compiler,"G-FLOAT64-ABS",narrative,narrative,disguised,negative,boundary)
        @Expect(disguisedResult.ok,false);@Expect(disguisedResult.feedback.contains("global abs(value)"),true)
        let prefixed="main(){ let value:Float64=-3.5; println(fabs(value)) }"
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-FLOAT64-ABS",narrative,narrative,prefixed,negative,boundary).ok,false)
        @Expect(disguisedResult.feedback.contains("/Users"),false);@Expect(disguisedResult.feedback.toAsciiLower().contains("token"),false)
        let unrelated=validateTeacherAuthorityRelevance("undeclared identifier 'parse'","G-FLOAT64",narrative,narrative,positive,negative,boundary)
        @Expect(unrelated.feedback.contains("global abs(value)"),false)
    }

    @TestCase public func candidateAuthorityRelevanceRequiresTwoStepRuneNumericConversion():Unit{
        let compiler="the expression for numeric type conversion must have a numeric type 中文😀 /Users/private/token Authorization"
        let narrative="Rune is not directly numeric. First obtain its Unicode scalar with UInt32(rune), then perform the target numeric conversion such as Float64(UInt32(rune)) or Int64(UInt32(rune))."
        let positive="main(){ let rune:Rune=r'A'; let value:Float64=Float64(UInt32(rune)); println(value) }"
        let boundary="main(){ let zero:Rune=Rune(0); let emoji:Rune=r'😀'; let a:Float64=Float64(UInt32(zero)); let b:Int64=Int64(UInt32(emoji)); println(a); println(b) }"
        let negative="main(){ let rune:Rune=r'中'; let value:Float64=Float64(rune); println(value) }"
        let relevant=validateTeacherAuthorityRelevance(compiler,"G-RUNE-NUMERIC-CONVERSION",narrative,narrative,positive,negative,boundary)
        @Expect(relevant.ok,true)

        let directPositive="main(){ let rune:Rune=r'A'; let value:Float64=Float64(rune); println(value) }"
        let directResult=validateTeacherAuthorityRelevance(compiler,"G-RUNE-NUMERIC-CONVERSION",narrative,narrative,directPositive,negative,boundary)
        @Expect(directResult.ok,false);@Expect(directResult.feedback.contains("Float64(UInt32(rune))"),true)
        let uint32Only="main(){ let rune:Rune=r'A'; let scalar:UInt32=UInt32(rune); println(scalar) }"
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-RUNE-NUMERIC-CONVERSION",narrative,narrative,uint32Only,negative,boundary).ok,false)
        let wrongNegativeResult=validateTeacherAuthorityRelevance(compiler,"G-RUNE-NUMERIC-CONVERSION",narrative,narrative,positive,positive,boundary)
        @Expect(wrongNegativeResult.ok,false);@Expect(wrongNegativeResult.feedback.contains("direct target conversion"),true)
        let disguised="// Float64(UInt32(rune))\nmain(){ let rune:Rune=r'A'; println(\"Float64(UInt32(rune))\"); println(rune) }"
        let disguisedResult=validateTeacherAuthorityRelevance(compiler,"G-RUNE-NUMERIC-CONVERSION",narrative,narrative,disguised,negative,boundary)
        @Expect(disguisedResult.ok,false);@Expect(disguisedResult.feedback.contains("UInt32(rune)"),true)
        @Expect(disguisedResult.feedback.contains("/Users"),false);@Expect(disguisedResult.feedback.toAsciiLower().contains("token"),false)
        let unrelated=validateTeacherAuthorityRelevance("invalid binary operator '<' on type 'UInt8' and 'Rune'","G-RUNE-BYTE-COMPARE",
            narrative,narrative,positive,negative,boundary)
        @Expect(unrelated.feedback.contains("direct target conversion"),false)
    }

    @TestCase public func candidateAuthorityRelevanceRequiresCombinedStringByteRuneEvidence():Unit{
        let compiler="invalid binary operator '==' on type 'UInt8' and 'Rune'; mismatched types expected 'Rune', found 'UInt8' 中文😀 /Users/private/token Authorization"
        let narrative="String element access yields UInt8 bytes. Use toRuneArray for Rune values, compare only the same type, and pass a Rune to a Rune parameter."
        let helper="func acceptRune(value: Rune){ println(value) }\n"
        let positive=helper+"main(){ let text:String=\"A\"; let byte:UInt8=UInt8(65); let otherByte:UInt8=UInt8(65); let runes:Array<Rune>=text.toRuneArray(); let rune:Rune=runes[0]; let otherRune:Rune=r'A'; println(byte==otherByte); println(rune==otherRune); acceptRune(rune) }"
        let boundary=helper+"main(){ let empty:String=\"\"; let byte:UInt8=UInt8(0); let otherByte:UInt8=UInt8(0); let runes:Array<Rune>=\"😀\".toRuneArray(); let rune:Rune=runes[0]; let otherRune:Rune=r'😀'; println(byte==otherByte); println(rune==otherRune); println(empty.size); acceptRune(rune) }"
        let negative=helper+"main(){ let byte:UInt8=UInt8(65); let rune:Rune=r'A'; println(byte==rune); acceptRune(byte) }"
        let relevant=validateTeacherAuthorityRelevance(compiler,"G-STRING",narrative,narrative,positive,negative,boundary)
        @Expect(relevant.ok,true)
        // STRING-BYTE-RUNE-PRED-POS/E2E: the extractor may state the same
        // public type fact without the contiguous English phrase "Rune
        // parameter".  This exact relationship must remain actionable.
        let equivalentNarrative="String element access produces UInt8 while toRuneArray produces Rune values. Equality requires the same type. A parameter declared as Rune requires a Rune argument."
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-STRING",equivalentNarrative,equivalentNarrative,positive,negative,boundary).ok,true)
        // STRING-BYTE-RUNE-PRED-NEG: scattered generic words do not assert
        // the parameter/argument type relationship.
        let scatteredNarrative="String UInt8 toRuneArray Rune values use the same type. Parameter validation is important and a Rune is a scalar."
        let scatteredResult=validateTeacherAuthorityRelevance(compiler,"G-STRING",scatteredNarrative,scatteredNarrative,positive,negative,boundary)
        @Expect(scatteredResult.ok,false)
        @Expect(scatteredResult.feedback.contains("a Rune parameter requires a Rune"),true)
        @Expect(scatteredResult.feedback.contains("a parameter declared as Rune requires a Rune argument"),true)
        let commentMasquerade="// a parameter declared as Rune requires a Rune argument\n"+positive
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-STRING",scatteredNarrative,scatteredNarrative,commentMasquerade,negative,boundary).ok,false)
        let atomHelper="func acceptRune(value: Rune){ println(value) }\\n"
        let atomPositive=atomHelper+"main(){ let text:String=String([r'A']); let byte:UInt8=UInt8(65); let otherByte:UInt8=UInt8(65); let runes:Array<Rune>=text.toRuneArray(); let rune:Rune=runes[0]; let otherRune:Rune=r'A'; println(byte==otherByte); println(rune==otherRune); acceptRune(rune) }"
        let atomBoundary=atomHelper+"main(){ let empty:String=String(Array<Rune>()); let byte:UInt8=UInt8(0); let otherByte:UInt8=UInt8(0); let runes:Array<Rune>=String([r'😀']).toRuneArray(); let rune:Rune=runes[0]; let otherRune:Rune=r'😀'; println(byte==otherByte); println(rune==otherRune); println(empty.size); acceptRune(rune) }"
        let atomNegative=atomHelper+"main(){ let byte:UInt8=UInt8(65); let rune:Rune=r'A'; println(byte==rune); acceptRune(byte) }"
        let atomBundle="{\"tests\":[{\"category\":\"positive\",\"source\":\"${atomPositive}\"},{\"category\":\"negative\",\"source\":\"${atomNegative}\",\"expectedDiagnostic\":\"invalid binary operator\"},{\"category\":\"boundary\",\"source\":\"${atomBoundary}\"}]}"
        let atomRoot="/tmp/teacher-atom-string-byte-rune-combined"
        try{let atomResult=executeTeacherAtomTestBundle(atomBundle,atomRoot);@Expect(atomResult.ok,true);@Expect(atomResult.feedback,"")}finally{try{remove(Path(atomRoot),recursive:true)}catch(_:Exception){}}

        let compareOnly=helper+"main(){ let byte:UInt8=UInt8(65); let rune:Rune=r'A'; println(byte==rune); acceptRune(rune) }"
        let compareOnlyResult=validateTeacherAuthorityRelevance(compiler,"G-STRING",narrative,narrative,positive,compareOnly,boundary)
        @Expect(compareOnlyResult.ok,false);@Expect(compareOnlyResult.feedback.contains("same negative source"),true)
        let argumentOnly=helper+"main(){ let byte:UInt8=UInt8(65); let otherByte:UInt8=UInt8(65); let rune:Rune=r'A'; println(byte==otherByte); acceptRune(byte); println(rune) }"
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-STRING",narrative,narrative,positive,argumentOnly,boundary).ok,false)
        let wrongPositive=helper+"main(){ let text:String=\"A\"; let byte:UInt8=UInt8(65); let runes:Array<Rune>=text.toRuneArray(); let rune:Rune=runes[0]; println(byte==rune); acceptRune(byte) }"
        @Expect(validateTeacherAuthorityRelevance(compiler,"G-STRING",narrative,narrative,wrongPositive,negative,boundary).ok,false)
        let disguised="// UInt8 Rune toRuneArray byte==rune acceptRune(byte)\nmain(){ println(\"UInt8 Rune toRuneArray\") }"
        let disguisedResult=validateTeacherAuthorityRelevance(compiler,"G-STRING",narrative,narrative,disguised,negative,boundary)
        @Expect(disguisedResult.ok,false);@Expect(disguisedResult.feedback.contains("acceptRune(value: Rune)"),true)
        @Expect(disguisedResult.feedback.contains("/Users"),false);@Expect(disguisedResult.feedback.toAsciiLower().contains("token"),false)
        let unrelated=validateTeacherAuthorityRelevance("invalid binary operator '==' on type 'UInt8' and 'Rune'","G-STRING",
            narrative,narrative,positive,negative,boundary)
        @Expect(unrelated.feedback.contains("same negative source"),false)
    }

    @TestCase public func candidateAuthorityRelevanceRequiresStdxDependencyProjectEvidence():Unit{
        let compiler="root package imports package 'stdx.crypto.digest' but it is not added as a dependency in cjpm.toml"
        let source="import stdx.crypto.digest.SHA256\nmain(){ let digest=SHA256(); digest.write(Array<UInt8>()); println(digest.finish().size) }"
        let negative="import stdx.crypto.digest.SHA256\nmain(){ let digest=SHA256(); println(digest.finish().size) }"
        let missingNarrative=validateTeacherAuthorityRelevance(compiler,"G-CJPM-DEPENDENCY",
            "Import stdx.crypto.digest.SHA256 before use.","Call SHA256 from stdx.crypto.digest.",source,negative,source,
            positiveDependencyProfile:"stdx-magic",negativeDependencyProfile:"none",boundaryDependencyProfile:"stdx-magic")
        @Expect(missingNarrative.ok,false);@Expect(missingNarrative.feedback.contains("cjpm.toml"),true)
        @Expect(missingNarrative.feedback.contains("bin-dependencies"),true);@Expect(missingNarrative.feedback.contains("path-option"),true)
        let narrative="Declare stdx in cjpm.toml under target bin-dependencies with path-option, then import stdx.crypto.digest.SHA256."
        let wrongProfiles=validateTeacherAuthorityRelevance(compiler,"G-CJPM-DEPENDENCY",narrative,narrative,source,negative,source,
            positiveDependencyProfile:"none",negativeDependencyProfile:"stdx-magic",boundaryDependencyProfile:"none")
        @Expect(wrongProfiles.ok,false);@Expect(wrongProfiles.feedback.contains("stdx-magic"),true)
        let magic="$"+"{MAGIC_PATH}"
        let landed="In cjpm.toml use [target.aarch64-apple-darwin.bin-dependencies] with a direct path-option = [\"${magic}/libs/cangjie-stdx-mac-aarch64-1.0.0.1/darwin_aarch64_llvm/dynamic/stdx\"] line before importing stdx.crypto.digest.SHA256."
        let relevant=validateTeacherAuthorityRelevance(compiler,"G-CJPM-DEPENDENCY",landed,landed,source,negative,source,
            positiveDependencyProfile:"stdx-magic",negativeDependencyProfile:"none",boundaryDependencyProfile:"stdx-magic")
        @Expect(relevant.ok,true)
        let placeholder=narrative+" [target.<target-triple>.bin-dependencies] stdx = { path-option = [\"<bundled-stdx-path>\"] }"
        let placeholderResult=validateTeacherAuthorityRelevance(compiler,"G-CJPM-DEPENDENCY",placeholder,placeholder,source,negative,source,
            positiveDependencyProfile:"stdx-magic",negativeDependencyProfile:"none",boundaryDependencyProfile:"stdx-magic")
        @Expect(placeholderResult.ok,false);@Expect(placeholderResult.feedback.contains("${magic}"),true)
        @Expect(placeholderResult.feedback.contains("/dynamic/stdx"),true)
        let unsafeResult=validateTeacherAuthorityRelevance(compiler+" 中文😀 /Users/private/token Authorization","G-CJPM-DEPENDENCY","generic","generic",source,negative,source,
            positiveDependencyProfile:"none",negativeDependencyProfile:"none",boundaryDependencyProfile:"none")
        @Expect(unsafeResult.ok,false);@Expect(unsafeResult.feedback.contains("/Users"),false);@Expect(unsafeResult.feedback.toAsciiLower().contains("token"),false)
    }

    @TestCase public func candidateAuthorityRelevanceRemovesUnnecessaryUndeclaredImport():Unit{
        let compiler="root package imports package 'std.text' in source but it is not added as a dependency in cjpm.toml"
        let positive="main(){ let builder=StringBuilder(); let rune:Rune=r'中'; builder.append(rune); println(builder.toString()) }"
        let boundary="main(){ let builder=StringBuilder(); let rune:Rune=r'😀'; builder.append(rune); println(builder.toString()) }"
        let negative="import std.text.*\n"+positive
        let wrongNarrative="Add std.text as a dependency so StringBuilder and Rune APIs compile."
        let wrong=validateTeacherAuthorityRelevance(compiler,"G-UNNECESSARY-UNDECLARED-IMPORT-FOR-AVAILABLE-API",
            wrongNarrative,wrongNarrative,positive,negative,boundary)
        @Expect(wrong.ok,false)
        let narrative="Check which package provides each API, then remove the unnecessary undeclared import std.text; StringBuilder and Rune are already available without adding a dependency."
        let relevant=validateTeacherAuthorityRelevance(compiler,"G-UNNECESSARY-UNDECLARED-IMPORT-FOR-AVAILABLE-API",
            narrative,narrative,positive,negative,boundary)
        @Expect(relevant.ok,true)
        let positiveStillImports=validateTeacherAuthorityRelevance(compiler,"G-UNNECESSARY-UNDECLARED-IMPORT-FOR-AVAILABLE-API",
            narrative,narrative,negative,negative,boundary)
        @Expect(positiveStillImports.ok,false)
        let negativeMissingImport=validateTeacherAuthorityRelevance(compiler,"G-UNNECESSARY-UNDECLARED-IMPORT-FOR-AVAILABLE-API",
            narrative,narrative,positive,positive,boundary)
        @Expect(negativeMissingImport.ok,false)
        let textualImport="import std.textual.*\n"+positive
        let textualIsNotText=validateTeacherAuthorityRelevance(compiler,"G-UNNECESSARY-UNDECLARED-IMPORT-FOR-AVAILABLE-API",
            narrative,narrative,positive,textualImport,boundary)
        @Expect(textualIsNotText.ok,false)
        let runtimeLabel=positive.replace("main(){","main(){ let apiOwner=\"std.text\";")
        let runtimeLabelResult=validateTeacherAuthorityRelevance(compiler,"G-UNNECESSARY-UNDECLARED-IMPORT-FOR-AVAILABLE-API",
            narrative,narrative,runtimeLabel,negative,boundary)
        @Expect(runtimeLabelResult.ok,false)
        let commentDisguise=boundary+" // preserve std.text as context"
        let commentResult=validateTeacherAuthorityRelevance(compiler,"G-UNNECESSARY-UNDECLARED-IMPORT-FOR-AVAILABLE-API",
            narrative,narrative,positive,negative,commentDisguise)
        @Expect(commentResult.ok,false)
        let noisyNarrative="Remove the import but retain the std.text label as runtime data in a string literal for context. StringBuilder and Rune APIs remain available."
        let noisyResult=validateTeacherAuthorityRelevance(compiler,"G-UNNECESSARY-UNDECLARED-IMPORT-FOR-AVAILABLE-API",
            noisyNarrative,noisyNarrative,positive,negative,boundary)
        @Expect(noisyResult.ok,false)
        let negativeNoise=negative+"\n// preserve std.text label"
        let negativeNoiseResult=validateTeacherAuthorityRelevance(compiler,"G-UNNECESSARY-UNDECLARED-IMPORT-FOR-AVAILABLE-API",
            narrative,narrative,positive,negativeNoise,boundary)
        @Expect(negativeNoiseResult.ok,false)
        let sameLineNoise="import std.text.* // preserve std.text label\n"+positive
        let sameLineNoiseResult=validateTeacherAuthorityRelevance(compiler,"G-UNNECESSARY-UNDECLARED-IMPORT-FOR-AVAILABLE-API",
            narrative,narrative,positive,sameLineNoise,boundary)
        @Expect(sameLineNoiseResult.ok,false)
        let unsafeResult=validateTeacherAuthorityRelevance(compiler+" 中文😀 /Users/private/token Authorization","G-UNNECESSARY-UNDECLARED-IMPORT-FOR-AVAILABLE-API",
            "generic","generic",positive,negative,boundary)
        @Expect(unsafeResult.ok,false);@Expect(unsafeResult.feedback.contains("/Users"),false);@Expect(unsafeResult.feedback.toAsciiLower().contains("token"),false)
    }

    @TestCase public func candidateControlFakeEndToEndAndBoundaries(): Unit {
        let root = "/tmp/teacher-candidate-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            Directory.create(Path(root), recursive: true)
            let manifest = teacherJoin(caseLines(), "\n") + "\n"
            File.writeTo(Path("${root}/manifest.jsonl"), manifest.toArray())
            Directory.create(Path("${root}/teacher-solutions/CJ-HUMANEVAL-000/src"), recursive: true)
            File.writeTo(Path("${root}/teacher-solutions/CJ-HUMANEVAL-000/src/solution.cj"), "private opaque implementation 987654".toArray())
            let run = TeacherRunManifest("teacher-r1", "CJ-HUMANEVAL-000", "dataset-v1", "gpt-5.6-sol", "prompt-hash", 2, "complete", 0, "evidence-中文😀")
            _ = persistCompletedTeacherRuns("${root}/runs/teacher-r1/completed.manifest", [run])
            _ = persistTeacherRunArtifacts(root,run,"generation","verification")
            _ = persistTeacherSolutionBinding(root,run)
            let evidence = "case=confirmed|taxonomy=knowledge_gap|independent=sha256:abc"
            let gap = "{\"schemaVersion\":\"ckb-benchmark-gap-v1\",\"datasetVersion\":\"dataset-v1\",\"teacherRunId\":\"development-r1\",\"evidenceHash\":\"sha256:${teacherStableHash(evidence)}\",\"evidence\":\"${evidence}\",\"failureTaxonomy\":\"knowledge_gap\",\"knowledgeGapConfirmations\":2,\"caseId\":\"CJ-HUMANEVAL-000\",\"benchmark\":\"Cangjie-HumanEval\",\"taskText\":\"authority bound task\",\"visibleTestExcerpt\":\"\",\"compilerOutput\":\"knowledge gap\",\"missingKnowledge\":\"G-STRING\",\"interfaceId\":\"KI-02\",\"contentFamily\":\"KC-02\",\"updateMechanism\":\"KU-11\",\"targetVersion\":\"1.0.0\",\"officialCitation\":\"https://docs.cangjie-lang.cn/docs/1.0.0/\"}\n"
            File.writeTo(Path("${root}/gap.jsonl"), gap.toArray())
            let options = TeacherCliOptions(); options.command="candidate-build"; options.root=root; options.manifest="${root}/manifest.jsonl"
            options.checksum=teacherStableHash(teacherJoin(caseLines(), "\n"));options.authorityGap="${root}/gap.jsonl";options.runId="teacher-r1";options.outputRoot="${root}/exports/r1";options.model="gpt-5.6-sol"
            let extractorJson="{\"provider\":\"codex\",\"model\":\"gpt-5.6-sol\",\"knowledgeFamily\":\"syntax\",\"concept\":\"UTF-8 String Rune iteration\",\"explanation\":\"Use String Rune iteration for Unicode character boundaries.\",\"example\":\"Declare a String and iterate over text.runes(); comparisons may contain &&, <, and > for 中文😀 boundaries.\",\"citation\":\"https://docs.cangjie-lang.cn/docs/1.0.0/\",\"sourceClass\":\"official\",\"positiveSource\":\"main() { let text: String = \\\"ok\\\" }\",\"negativeSource\":\"main() { let text: String = unknownName }\",\"boundarySource\":\"main() { let text: String = \\\"中文😀\\\" }\",\"negativeDiagnostic\":\"undefined\"}"
            let irrelevantJson=extractorJson.replace("Use String Rune iteration for Unicode character boundaries.","Use Rune iteration for Unicode boundaries.").replace("Declare a String and iterate over text.runes() for Chinese and emoji.","Iterate over runes.").replace("let text: String", "let value: Int64")
            let badExtractorJson=extractorJson.replace("\"negativeDiagnostic\":\"undefined\"","\"negativeDiagnostic\":\"wrong diagnostic 中文😀\"")
            let extractor=RecordingExecutor(results:[TeacherProcessResult(124,"timeout",timedOut:true),TeacherProcessResult(7,"provider unavailable"),TeacherProcessResult(0,irrelevantJson),TeacherProcessResult(0,badExtractorJson),TeacherProcessResult(0,extractorJson)])
            let atom=AtomRepairExecutor()
            let result = buildTeacherCandidates(options,extractorExecutor:extractor,atomExecutor:atom)
            @Expect(result.ok, true); @Expect(result.accepted, 1)
            @Expect(extractor.specs.size,5)
            @Expect(extractor.specs[4].args.contains("gpt-5.6-sol"), true)
            @Expect(extractor.specs[4].args.contains("read-only"), true)
            @Expect(extractor.specs[4].args.contains("--ephemeral"), true)
            @Expect(extractor.specs[4].args.contains("-C"), true)
            @Expect(extractor.specs[4].args.contains("--output-schema"), true)
            @Expect(extractor.specs[4].args.contains("--output-last-message"), true)
            @Expect(extractor.specs[4].args.contains("--cwd"), false)
            @Expect(extractor.specs[4].args.contains("--full-auto"), false)
            @Expect(extractor.specs[4].args[extractor.specs[4].args.size-1].contains("Set citation to exactly 'https://docs.cangjie-lang.cn/docs/1.0.0/'"),true)
            @Expect(extractor.specs[4].args[extractor.specs[4].args.size-1].contains("negativeDiagnostic must be a short literal substring emitted by the Cangjie compiler"),true)
            @Expect(extractor.specs[3].args[extractor.specs[3].args.size-1].contains("Required public failure anchors and prerequisites: string"),true)
            @Expect(extractor.specs[4].args[extractor.specs[4].args.size-1].contains("wrong diagnostic 中文😀"),true)
            @Expect(extractor.specs[4].args[extractor.specs[4].args.size-1].contains("undefined name 中文😀"),true)
            @Expect(exists(Path("${root}/exports/r1/observations.tsv")), true)
            @Expect(exists(Path("${root}/exports/r1/atom-tests.jsonl")), true)
            @Expect(exists(Path("${root}/exports/r1/candidate-knowledge.tsv")), true)
            let ckb = teacherReadUtf8File("${root}/exports/r1/candidate-knowledge/ckb-benchmark-gap.jsonl")
            @Expect(ckb.contains("\"schemaVersion\":\"ckb-benchmark-gap-v1\""), true)
            @Expect(ckb.contains("\"knowledgeAtomCandidate\":true"), true)
            @Expect(ckb.contains("\"candidateHash\":\"sha256:"), true)
            let ckbObject = JsonValue.fromStr(ckb.trimAscii()).asObject()
            let canonicalBundle = ckbObject.get("knowledgeAtomTestBundle").getOrThrow().toString()
            @Expect(canonicalBundle.contains("\\u0026\\u0026"), true)
            @Expect(canonicalBundle.contains("<"), true)
            @Expect(canonicalBundle.contains(">"), true)
            @Expect(ckb.contains("\"knowledgeAtomTestBundle\":${canonicalBundle}"), true)
            @Expect(p3CkbString(ckbObject, "candidateHash"), p3CkbCandidateHash(ckb))
            @Expect(teacherReadUtf8File("${root}/exports/r1/candidate-knowledge.tsv").toAsciiLower().contains("cj-humaneval-"), false)
            // Multiple cases share one private exports parent. Publishing a
            // second candidate must not try to recreate that existing parent.
            options.outputRoot="${root}/exports/r2"
            let second = buildTeacherCandidates(options,
                extractorExecutor:RecordingExecutor(results:[TeacherProcessResult(0,extractorJson)]),
                atomExecutor:AtomRepairExecutor())
            @Expect(second.ok,true);@Expect(second.accepted,1)
            @Expect(teacherReadUtf8File("${root}/exports/r2/candidate-knowledge/ckb-benchmark-gap.jsonl").contains("中文😀"),true)
            options.outputRoot="${root}/exports/throwing"
            let throwing=buildTeacherCandidates(options,extractorExecutor:ThrowingCandidateExecutor())
            @Expect(throwing.diagnostic,"candidate_extractor_failed")
            @Expect(throwing.diagnostic.contains("private"),false)
            @Expect(throwing.diagnostic.contains("token"),false)
            options.outputRoot="${root}/ckb-data/production"
            @Expect(buildTeacherCandidates(options).diagnostic, "output_path_forbidden")
            options.outputRoot="${root}/exports/../escape"
            @Expect(buildTeacherCandidates(options).diagnostic, "output_path_forbidden")
            File.writeTo(Path("${root}/bad-gap.jsonl"), [UInt8(0xff), UInt8(0xfe)])
            options.authorityGap="${root}/bad-gap.jsonl"; options.outputRoot="${root}/exports/bad-encoding"
            @Expect(buildTeacherCandidates(options).diagnostic, "invalid_response_encoding")
            options.authorityGap="${root}/gap.jsonl";options.outputRoot="${root}/exports/bad-extractor"
            @Expect(buildTeacherCandidates(options,extractorExecutor:RecordingExecutor(results:[TeacherProcessResult(0,"not-json")])).diagnostic,"malformed_extractor_json")
            options.model="unexpected-model";options.outputRoot="${root}/exports/model"
            @Expect(buildTeacherCandidates(options,extractorExecutor:extractor).diagnostic,"extractor_model_identity_invalid")
            options.model="gpt-5.6-sol";_=teacherAtomicWrite("${root}/runs/teacher-r1/evidence/CJ-HUMANEVAL-000/solution.binding","wrong\twrong\twrong\n");options.outputRoot="${root}/exports/binding"
            @Expect(buildTeacherCandidates(options,extractorExecutor:extractor).diagnostic,"solution_evidence_binding_invalid")
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

    @TestCase public func candidateCkbBundleCanonicalizationIsUtf8BoundedAndLeakSafe():Unit{
        let special="{\"atomId\":\"GENERAL\",\"example\":\"left && value < upper > lower 中文😀 quote \\\"ok\\\" slash C:\\\\tmp\"}"
        let canonical=canonicalizeTeacherCkbKnowledgeAtomBundle(special.toArray())
        @Expect(canonical[1],"ok");@Expect(canonical[0].contains("\\u0026\\u0026"),true)
        @Expect(canonical[0].contains("<"),true);@Expect(canonical[0].contains(">"),true)
        @Expect(canonical[0].contains("中文😀"),true);@Expect(canonical[0].contains("\\\"ok\\\""),true)
        let stable="{\"atomId\":\"GENERAL\",\"example\":\"plain ascii\"}"
        let stableCanonical=canonicalizeTeacherCkbKnowledgeAtomBundle(stable.toArray())
        @Expect(stableCanonical[0],stable);@Expect(stableCanonical[1],"ok")
        @Expect(canonicalizeTeacherCkbKnowledgeAtomBundle("{".toArray())[1],"malformed_atom_test_bundle")
        @Expect(canonicalizeTeacherCkbKnowledgeAtomBundle([UInt8(0xff),UInt8(0xfe)])[1],"invalid_response_encoding")
        @Expect(canonicalizeTeacherCkbKnowledgeAtomBundle(Array<UInt8>(262145,repeat:UInt8(65)))[1],"atom_test_bundle_too_large")
        let leaked="{\"atomId\":\"GENERAL\",\"example\":\"/Users/private/token=secret 中文😀\"}"
        let blocked=canonicalizeTeacherCkbKnowledgeAtomBundle(leaked.toArray())
        @Expect(blocked[1],"atom_content_contamination");@Expect(blocked[0],"")
    }

    @TestCase public func candidateReexportReplaysTrustedBundleWithoutModelAndPublishesAtomically():Unit{
        let root="/tmp/teacher-reexport-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            let source=buildCandidateFixture(root,"source")
            let options=TeacherCliOptions();options.command="candidate-reexport";options.root=root
            options.manifest="${root}/manifest.jsonl";options.checksum=teacherStableHash(teacherJoin(caseLines(),"\n"))
            options.authorityGap="${root}/gap.jsonl";options.runId="teacher-r1";options.sourceExport=source
            options.outputRoot="${root}/exports/reexported"
            let replay=RecordingExecutor(results:[TeacherProcessResult(0,""),TeacherProcessResult(0,""),TeacherProcessResult(0,""),TeacherProcessResult(0,""),TeacherProcessResult(1,"undefined"),TeacherProcessResult(0,""),TeacherProcessResult(0,""),TeacherProcessResult(0,"")])
            let result=reexportTeacherCandidateBundle(options,atomExecutor:replay)
            @Expect(result.ok,true);@Expect(result.accepted,1);@Expect(result.diagnostic,"ok")
            @Expect(replay.specs.size,8)
            for(spec in replay.specs){@Expect(spec.executable,"cjpm")}
            let sourceBundle=teacherReadUtf8File("${source}/atom-tests.jsonl").trimAscii()
            let outputBundle=teacherReadUtf8File("${options.outputRoot}/atom-tests.jsonl").trimAscii()
            let sourceObject=JsonValue.fromStr(sourceBundle).asObject();let outputObject=JsonValue.fromStr(outputBundle).asObject()
            @Expect(outputObject.get("atomId").getOrThrow().toString(),sourceObject.get("atomId").getOrThrow().toString())
            @Expect(outputObject.get("tests").getOrThrow().toString(),sourceObject.get("tests").getOrThrow().toString())
            @Expect(outputObject.get("execution").getOrThrow().toString()!=sourceObject.get("execution").getOrThrow().toString(),true)
            let outputCkb=teacherReadUtf8File("${options.outputRoot}/candidate-knowledge/ckb-benchmark-gap.jsonl").trimAscii()
            @Expect(p3CkbString(JsonValue.fromStr(outputCkb).asObject(),"candidateHash"),p3CkbCandidateHash(outputCkb))
            @Expect(outputCkb.contains("\\u0026\\u0026"),true)
        } finally { try{remove(Path(root),recursive:true)}catch(_:Exception){} }
    }

    @TestCase public func candidateReexportAcceptsLegacyRawOuterHashAndEmitsCanonicalCkbHash():Unit{
        let root="/tmp/teacher-reexport-legacy-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            let source=buildCandidateFixture(root,"legacy-source");makeLegacyRawCkb(source)
            let legacy=teacherReadUtf8File("${source}/candidate-knowledge/ckb-benchmark-gap.jsonl").trimAscii()
            @Expect(p3CkbString(JsonValue.fromStr(legacy).asObject(),"candidateHash")!=p3CkbCandidateHash(legacy),true)
            let options=reexportOptions(root,source,"canonical-output")
            let replay=RecordingExecutor(results:[TeacherProcessResult(0,""),TeacherProcessResult(0,""),TeacherProcessResult(0,""),TeacherProcessResult(0,""),TeacherProcessResult(1,"undefined"),TeacherProcessResult(0,""),TeacherProcessResult(0,""),TeacherProcessResult(0,"")])
            let result=reexportTeacherCandidateBundle(options,atomExecutor:replay);@Expect(result.ok,true)
            let canonical=teacherReadUtf8File("${options.outputRoot}/candidate-knowledge/ckb-benchmark-gap.jsonl").trimAscii()
            @Expect(p3CkbString(JsonValue.fromStr(canonical).asObject(),"candidateHash"),p3CkbCandidateHash(canonical))
            @Expect(canonical.contains("\\u0026\\u0026"),true)
        } finally { try{remove(Path(root),recursive:true)}catch(_:Exception){} }
    }

    @TestCase public func candidateReexportFailsClosedForMissingCorruptAndUnsafeSource():Unit{
        let root="/tmp/teacher-reexport-negative-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            let source=buildCandidateFixture(root,"source")
            let options=TeacherCliOptions();options.command="candidate-reexport";options.root=root
            options.manifest="${root}/manifest.jsonl";options.checksum=teacherStableHash(teacherJoin(caseLines(),"\n"))
            options.authorityGap="${root}/gap.jsonl";options.runId="teacher-r1";options.sourceExport=source
            options.outputRoot="${root}/exports/reexported"
            remove(Path("${source}/atoms.tsv"))
            @Expect(reexportTeacherCandidateBundle(options).diagnostic,"source_export_missing_file")
            @Expect(exists(Path(options.outputRoot)),false)
            @Expect(exists(Path(options.outputRoot+".tmp")),false)
            options.sourceExport="${root}/../outside"
            @Expect(reexportTeacherCandidateBundle(options).diagnostic,"source_export_path_forbidden")
            @Expect(parseTeacherCliOptions(["candidate-reexport","--source-export",source,"--output-root",options.outputRoot]).sourceExport,source)
        } finally { try{remove(Path(root),recursive:true)}catch(_:Exception){} }
    }

    @TestCase public func candidateReexportRejectsUtf8SizeRowsAndContractTampering():Unit{
        let base="/tmp/teacher-reexport-tamper-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            let utf8Root="${base}/utf8";let utf8Source=buildCandidateFixture(utf8Root,"source");let utf8Options=reexportOptions(utf8Root,utf8Source,"output")
            File.writeTo(Path("${utf8Source}/atoms.tsv"),[UInt8(0xff),UInt8(0xfe)])
            @Expect(reexportTeacherCandidateBundle(utf8Options).diagnostic,"invalid_response_encoding");@Expect(exists(Path(utf8Options.outputRoot)),false)

            let sizeRoot="${base}/size";let sizeSource=buildCandidateFixture(sizeRoot,"source");let sizeOptions=reexportOptions(sizeRoot,sizeSource,"output")
            File.writeTo(Path("${sizeSource}/atoms.tsv"),Array<UInt8>(262145,repeat:UInt8(65)))
            @Expect(reexportTeacherCandidateBundle(sizeOptions).diagnostic,"source_export_too_large");@Expect(exists(Path(sizeOptions.outputRoot)),false)

            let rowsRoot="${base}/rows";let rowsSource=buildCandidateFixture(rowsRoot,"source");let rowsOptions=reexportOptions(rowsRoot,rowsSource,"output")
            let observation=teacherReadUtf8File("${rowsSource}/observations.tsv").trimAscii();File.writeTo(Path("${rowsSource}/observations.tsv"),"${observation}\n${observation}\n".toArray())
            @Expect(reexportTeacherCandidateBundle(rowsOptions).diagnostic,"source_export_record_count_invalid");@Expect(exists(Path(rowsOptions.outputRoot)),false)

            let purifyRoot="${base}/purify";let purifySource=buildCandidateFixture(purifyRoot,"source");let purifyOptions=reexportOptions(purifyRoot,purifySource,"output")
            let bundlePath="${purifySource}/atom-tests.jsonl";let unpurified=teacherReadUtf8File(bundlePath).replace("\"purificationPassed\":true","\"purificationPassed\":false")
            File.writeTo(Path(bundlePath),unpurified.toArray())
            @Expect(reexportTeacherCandidateBundle(purifyOptions).diagnostic,"atom_purification_required");@Expect(exists(Path(purifyOptions.outputRoot)),false)

            let executeRoot="${base}/execute";let executeSource=buildCandidateFixture(executeRoot,"source");let executeOptions=reexportOptions(executeRoot,executeSource,"output")
            let executePath="${executeSource}/atom-tests.jsonl";let failed=teacherReadUtf8File(executePath).replace("\"passed\":3","\"passed\":2")
            File.writeTo(Path(executePath),failed.toArray())
            @Expect(reexportTeacherCandidateBundle(executeOptions).diagnostic,"atom_execution_invalid");@Expect(exists(Path(executeOptions.outputRoot)),false)

            let hashRoot="${base}/hash";let hashSource=buildCandidateFixture(hashRoot,"source");let hashOptions=reexportOptions(hashRoot,hashSource,"output")
            let ckbPath="${hashSource}/candidate-knowledge/ckb-benchmark-gap.jsonl";let originalCkb=teacherReadUtf8File(ckbPath)
            let declared=p3CkbString(JsonValue.fromStr(originalCkb.trimAscii()).asObject(),"candidateHash")
            let badHash=originalCkb.replace("\"candidateHash\":\"${declared}\"","\"candidateHash\":\"sha256:bad\"")
            File.writeTo(Path(ckbPath),badHash.toArray())
            @Expect(reexportTeacherCandidateBundle(hashOptions).diagnostic,"source_gap_candidate_hash_mismatch");@Expect(exists(Path(hashOptions.outputRoot)),false)
        } finally { try{remove(Path(base),recursive:true)}catch(_:Exception){} }
    }

    @TestCase public func candidateAtomRunsInRealLocalCangjieWorkspaces():Unit {
        let root="/tmp/teacher-real-atom-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        let bundle="{\"tests\":[{\"category\":\"positive\",\"source\":\"main() { let value: Int64 = 1 }\"},{\"category\":\"negative\",\"source\":\"main() { let value: MissingType = 1 }\",\"expectedDiagnostic\":\"undeclared type name\"},{\"category\":\"boundary\",\"source\":\"main() { let text = \\\"中文😀\\\"; let count = text.toRuneArray().size }\"}]}"
        try{@Expect(executeTeacherAtomTestBundle(bundle,root).ok,true)}finally{try{remove(Path(root),recursive:true)}catch(_:Exception){}}
    }

    @TestCase public func candidateLogicalOrAtomReproducesAuthorityDiagnostic():Unit {
        let root="/tmp/teacher-logical-or-atom-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        let bundle="{\"tests\":[{\"category\":\"positive\",\"source\":\"main() { let left: Bool = true; let right: Bool = false; if (left || right) { println(left) } }\"},{\"category\":\"negative\",\"source\":\"main() { let left: Bool = true; let right: Bool = false; if (left) || (right) { println(left) } }\",\"expectedDiagnostic\":\"expected '{', found '||'\"},{\"category\":\"boundary\",\"source\":\"main() { let left: Bool = false; let right: Bool = false; while (left || right) { break } }\"}]}"
        try{@Expect(executeTeacherAtomTestBundle(bundle,root).ok,true)}finally{try{remove(Path(root),recursive:true)}catch(_:Exception){}}
    }

    @TestCase public func candidateStringCaseRuneAtomReproducesAuthorityDiagnostic():Unit {
        let root="/tmp/teacher-string-case-rune-atom-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        let positive="main() { let text: String = \\\"XYZ\\\"; let lowered: String = text.toAsciiLower(); if (lowered != \\\"xyz\\\") { throw IllegalStateException(\\\"ascii lower failed\\\") } }"
        let negative="main() { let text: String = \\\"ABC\\\"; println(text.toLower()) }"
        let boundary="import std.unicode.*\\nmain() { let text: String = \\\"中😀\\\"; let lowered: String = text.toAsciiLower(); if (lowered != text) { throw IllegalStateException(\\\"non ascii changed\\\") }; let rune: Rune = r'中'; println(rune.toLowerCase()) }"
        let bundle="{\"tests\":[{\"category\":\"positive\",\"source\":\"${positive}\"},{\"category\":\"negative\",\"source\":\"${negative}\",\"expectedDiagnostic\":\"'toLower' is not a member of struct 'String'\"},{\"category\":\"boundary\",\"source\":\"${boundary}\"}]}"
        try{@Expect(executeTeacherAtomTestBundle(bundle,root).ok,true)}finally{try{remove(Path(root),recursive:true)}catch(_:Exception){}}
    }

    @TestCase public func candidateAtomDependencyProfileIsFixedAndRejectsPathInjection():Unit {
        let root="/tmp/teacher-project-atom-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        let bundle="{\"tests\":[{\"category\":\"positive\",\"dependencyProfile\":\"stdx-magic\",\"source\":\"main() {}\"},{\"category\":\"negative\",\"dependencyProfile\":\"none\",\"source\":\"main() { bad }\",\"expectedDiagnostic\":\"undefined\"},{\"category\":\"boundary\",\"dependencyProfile\":\"stdx-magic\",\"source\":\"main() {}\"}]}"
        let passing=RecordingExecutor(results:[TeacherProcessResult(0,""),TeacherProcessResult(0,""),TeacherProcessResult(0,""),TeacherProcessResult(0,""),TeacherProcessResult(1,"undefined"),TeacherProcessResult(0,""),TeacherProcessResult(0,""),TeacherProcessResult(0,"")])
        try {
            @Expect(executeTeacherAtomTestBundle(bundle,root,executor:passing).ok,true)
            let positive=teacherReadUtf8File("${root}/positive/cjpm.toml")
            let negative=teacherReadUtf8File("${root}/negative/cjpm.toml")
            @Expect(positive.contains("[target.aarch64-apple-darwin.bin-dependencies]"),true)
            @Expect(positive.contains("$"+"{MAGIC_PATH}"),true)
            @Expect(positive.contains("/Users/"),false)
            @Expect(negative.contains("bin-dependencies"),false)
            let injected=bundle.replace("stdx-magic","/Users/private/秘密😀")
            @Expect(executeTeacherAtomTestBundle(injected,"${root}-injected",executor:passing).diagnostic,"atom_dependency_profile_forbidden")
        } finally { try{remove(Path(root),recursive:true)}catch(_:Exception){};try{remove(Path("${root}-injected"),recursive:true)}catch(_:Exception){} }
    }

    @TestCase public func candidateAtomValidatesStdxImportWithProjectDependency():Unit {
        let root="/tmp/teacher-stdx-atom-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        let source="import stdx.crypto.digest.SHA256\\n\\nmain() { let digest = SHA256(); digest.write(Array<UInt8>()); println(digest.finish().size) }"
        let bundle="{\"tests\":[{\"category\":\"positive\",\"dependencyProfile\":\"stdx-magic\",\"source\":\"${source}\"},{\"category\":\"negative\",\"dependencyProfile\":\"none\",\"source\":\"${source}\",\"expectedDiagnostic\":\"imports package 'stdx.crypto.digest'\"},{\"category\":\"boundary\",\"dependencyProfile\":\"stdx-magic\",\"source\":\"${source}\"}]}"
        try{@Expect(executeTeacherAtomTestBundle(bundle,root).ok,true)}finally{try{remove(Path(root),recursive:true)}catch(_:Exception){}}
    }

    @TestCase public func candidateControlFailsClosedForCliAndCorruptEvidence(): Unit {
        var unknown=false;try{_=parseTeacherCliOptions(["candidate-build","--unknown","x"])}catch(e:Exception){unknown=e.message=="unknown_cli_option"};@Expect(unknown,true)
        var duplicate=false;try{_=parseTeacherCliOptions(["candidate-build","--root","a","--root","b"])}catch(e:Exception){duplicate=e.message=="duplicate_cli_option"};@Expect(duplicate,true)
        let options=TeacherCliOptions();options.command="candidate-build"
        @Expect(buildTeacherCandidates(options).diagnostic,"missing_required_cli_option")
    }
}
