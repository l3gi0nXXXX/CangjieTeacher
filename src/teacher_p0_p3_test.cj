package cangjie_teacher

import std.collection.*
import std.unittest.testmacro.*

private func testCase(id!: String = "CJ-HUMANEVAL-000", version!: String = "dataset-v1"): TeacherCaseManifest {
    TeacherCaseManifest(id, version, "prompt-hash", "starter-hash", "func demo(x: Int64): Int64", "verifier-hash")
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
