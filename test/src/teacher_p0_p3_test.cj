package cangjie_teacher_test

import std.collection.*
import std.fs.*
import std.time.*
import std.unittest.testmacro.*
import cangjie_teacher.*

private func testCase(id!: String = "CJ-HUMANEVAL-000", version!: String = "dataset-v1"): TeacherCaseManifest {
    TeacherCaseManifest(id, version, "prompt-hash", "starter-hash", "func demo(x: Int64): Int64", "verifier-hash")
}

private class RecordingExecutor <: TeacherCommandExecutor {
    public let specs = ArrayList<TeacherCommandSpec>()
    private let results: Array<TeacherProcessResult>
    private var index: Int64 = 0
    public init(results!: Array<TeacherProcessResult> = [TeacherProcessResult(0, "ok")]) { this.results = results }
    public func execute(spec: TeacherCommandSpec): TeacherProcessResult {
        specs.add(spec)
        let selected = if (index < results.size) { results[index] } else { results[results.size - 1] }
        index += 1
        selected
    }
}

@Test
public class TeacherRuntimeTest {
    private func tempRoot(name: String): String {
        "/tmp/cangjie-teacher-${name}-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
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
            @Expect(validateTeacherExecutionPrivacy("/repo", "/repo/runs", true), false)
            @Expect(validateTeacherExecutionPrivacy("/repo", "/private/teacher-runs", true), true)
            @Expect(validateTeacherExecutionPrivacy("/repo", "/private/teacher-runs", false), false)
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

    // P2-UT-01 / P2-BND-01
    @TestCase public func codexUsesExactArgvCwdEnvironmentAndTimeout(): Unit {
        let recorder = RecordingExecutor(results: [TeacherProcessResult(124, "timeout", timedOut: true)])
        let root = tempRoot("process")
        try {
            let result = CodexTeacherProcess("/fake/codex", "gpt-fake", timeoutMillis: 1234, executor: recorder)
                .generate(testCase(), "${root}/workspace", "${root}/session", "${root}/home")
            @Expect(result.timedOut, true)
            @Expect(recorder.specs.size, 1)
            @Expect(recorder.specs[0].executable, "/fake/codex")
            @Expect(recorder.specs[0].cwd, "${root}/workspace")
            @Expect(recorder.specs[0].args[0], "exec")
            @Expect(recorder.specs[0].args.contains("--full-auto"), true)
            @Expect(recorder.specs[0].timeoutMillis, 1234)
            var hasHome = false
            for (entry in recorder.specs[0].env) { if (entry[0] == "CODEX_HOME" && entry[1] == "${root}/home") { hasHome = true } }
            @Expect(hasHome, true)
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

    // P2-POS-01 / P2-NEG-01
    @TestCase public func verifierInjectsTestsAfterGenerationAndStopsOnFailure(): Unit {
        let root = tempRoot("verify")
        let recorder = RecordingExecutor(results: [TeacherProcessResult(0, "clean"), TeacherProcessResult(7, "build failed")])
        try {
            Directory.create(Path("${root}/tests/CJ-HUMANEVAL-000/test/src"), recursive: true)
            Directory.create(Path("${root}/solution"), recursive: true)
            File.writeTo(Path("${root}/tests/CJ-HUMANEVAL-000/test/src/case_test.cj"), "test".toArray())
            @Expect(exists(Path("${root}/solution/test")), false)
            let result = CjpmTeacherVerifier("${root}/tests", executor: recorder).verify(testCase(), "${root}/solution")
            @Expect(exists(Path("${root}/solution/test/src/case_test.cj")), true)
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
            Directory.create(Path("${root}/starters/CJ-HUMANEVAL-000/src"), recursive: true)
            File.writeTo(Path("${root}/starters/CJ-HUMANEVAL-000/cjpm.toml"), "package".toArray())
            File.writeTo(Path("${root}/starters/CJ-HUMANEVAL-000/src/main.cj"), "中文😀".toArray())
            let workspace = createTeacherCaseWorkspace(root, "run-1", testCase(), "${root}/starters")
            @Expect(teacherReadUtf8File("${workspace}/src/main.cj"), "中文😀")
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
private func caseLines(): Array<String> { validCases().map({c: TeacherCaseManifest => renderTeacherCaseManifest(c)}) }

private class FakeClock <: TeacherClock {
    public func nowMillis(): Int64 { 1000 }
}
private class FakeProcess <: TeacherProcess {
    let result: TeacherProcessResult
    public init(result: TeacherProcessResult) { this.result = result }
    public func generate(caseValue: TeacherCaseManifest, workspace: String, session: String, runtimeHome: String): TeacherProcessResult { result }
}
private class FakeVerifier <: TeacherVerifier {
    let result: TeacherProcessResult
    public init(result: TeacherProcessResult) { this.result = result }
    public func verify(caseValue: TeacherCaseManifest, solutionRoot: String): TeacherProcessResult { result }
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
    }
}
