package cangjie_teacher_test

import std.collection.*
import std.fs.*
import std.time.*
import std.unittest.testmacro.*
import cangjie_teacher.*

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
            ("error: undeclared identifier 'toUpper'; undeclared identifier 'toLower'","G-RUNE-UNICODE-CASE","Use Rune.toUpperCase and Rune.toLowerCase.","r.toUpperCase(); r.toLowerCase()"),
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
            let extractorJson="{\"provider\":\"codex\",\"model\":\"gpt-5.6-sol\",\"knowledgeFamily\":\"syntax\",\"concept\":\"UTF-8 String Rune iteration\",\"explanation\":\"Use String Rune iteration for Unicode character boundaries.\",\"example\":\"Declare a String and iterate over text.runes() for Chinese and emoji.\",\"citation\":\"https://docs.cangjie-lang.cn/docs/1.0.0/\",\"sourceClass\":\"official\",\"positiveSource\":\"main() { let text: String = \\\"ok\\\" }\",\"negativeSource\":\"main() { let text: String = unknownName }\",\"boundarySource\":\"main() { let text: String = \\\"中文😀\\\" }\",\"negativeDiagnostic\":\"undefined\"}"
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

    @TestCase public func candidateAtomRunsInRealLocalCangjieWorkspaces():Unit {
        let root="/tmp/teacher-real-atom-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        let bundle="{\"tests\":[{\"category\":\"positive\",\"source\":\"main() { let value: Int64 = 1 }\"},{\"category\":\"negative\",\"source\":\"main() { let value: MissingType = 1 }\",\"expectedDiagnostic\":\"undeclared type name\"},{\"category\":\"boundary\",\"source\":\"main() { let text = \\\"中文😀\\\"; let count = text.toRuneArray().size }\"}]}"
        try{@Expect(executeTeacherAtomTestBundle(bundle,root).ok,true)}finally{try{remove(Path(root),recursive:true)}catch(_:Exception){}}
    }

    @TestCase public func candidateControlFailsClosedForCliAndCorruptEvidence(): Unit {
        var unknown=false;try{_=parseTeacherCliOptions(["candidate-build","--unknown","x"])}catch(e:Exception){unknown=e.message=="unknown_cli_option"};@Expect(unknown,true)
        var duplicate=false;try{_=parseTeacherCliOptions(["candidate-build","--root","a","--root","b"])}catch(e:Exception){duplicate=e.message=="duplicate_cli_option"};@Expect(duplicate,true)
        let options=TeacherCliOptions();options.command="candidate-build"
        @Expect(buildTeacherCandidates(options).diagnostic,"missing_required_cli_option")
    }
}
