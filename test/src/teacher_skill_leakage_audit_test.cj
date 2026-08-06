package cangjie_teacher_test

import std.collection.*
import std.fs.*
import std.time.*
import std.unittest.testmacro.*
import cangjie_teacher.*

private let LEAK_FAILURE = "{\"schemaVersion\":\"ckb-completion-failure-v1\",\"runId\":\"recert-fixture-run\",\"caseId\":\"CJ-HUMANEVAL-007\",\"datasetVersion\":\"cangjie-humaneval-164-v1\",\"generationProtocol\":\"completion-only-v1\",\"completionHash\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"baseStatus\":\"failed\",\"plusStatus\":\"failed\",\"failureKind\":\"test_failure\",\"failureObservation\":\"student_completion_test_failed 中文😀\",\"assetLineage\":\"independent\",\"evidenceHash\":\"f08453591302a46c4acc04c43d9bdf456679fae27b354bbca7ebecb194c1e773\"}"
private let LEAK_CLASSIFICATION = "{\"schemaVersion\":\"ckb-completion-failure-classification-v1\",\"failureEvidenceHash\":\"f08453591302a46c4acc04c43d9bdf456679fae27b354bbca7ebecb194c1e773\",\"gapKind\":\"mixed_gap\",\"knowledgeEligible\":true,\"skillEligible\":true,\"classificationEvidenceHash\":\"1ff85ffec78c69504a2f98146daebb75557d340b6366e92875c4c1acd4b44a16\"}"

private func leakFixtures(): Array<TeacherSkillFixture> {
    [TeacherSkillFixture("positive-basic", "Review a typed accumulator.", "positive_passed", kind: "positive"),
        TeacherSkillFixture("negative-unsafe", "Reject an unchecked index.", "negative_rejected", kind: "negative"),
        TeacherSkillFixture("boundary-unicode", "Review 中文😀 Rune boundaries.", "boundary_passed", kind: "boundary"),
        TeacherSkillFixture("tree-walk", "Review a generic tree walk.", "generalization_passed",
            fixturePath: "tests/generalization/tree-walk.json"),
        TeacherSkillFixture("queue-drain", "Review a generic queue drain.", "generalization_passed"),
        TeacherSkillFixture("text-scan", "Review a generic Unicode scan.", "generalization_passed")]
}

private func leakCandidate(procedure!: String = "Choose a Rune boundary before each static text operation."): TeacherSkillCandidate {
    buildTeacherSkillCandidate(parseTeacherCompletionFailureInput(LEAK_FAILURE),
        parseTeacherFailureClassification(LEAK_CLASSIFICATION), "static-review", "1.0.0", "Static review",
        procedure, "general_engineering", "Generic one-shot code generation.",
        buildTeacherSkillTestBundle(leakFixtures()), candidateOrigin: "independent_seed")
}

private class BoundClock <: TeacherClock { public func nowMillis(): Int64 { 1 } }
private class BoundProcess <: TeacherProcess {
    public var feedback = ""
    public func generate(_: TeacherCaseManifest, _: String, _: String, _: String,
        verifierFeedback: String): TeacherProcessResult {
        feedback = verifierFeedback; TeacherProcessResult(0, "generated")
    }
}
private class BoundVerifier <: TeacherVerifier {
    public func verify(_: TeacherCaseManifest, _: String): TeacherProcessResult { TeacherProcessResult(0, "passed") }
}
private class VerifierExecutor <: TeacherCommandExecutor {
    private let finalOutput: String
    public init(finalOutput: String) { this.finalOutput = finalOutput }
    public func execute(spec: TeacherCommandSpec): TeacherProcessResult {
        if (spec.args[0] == "run") { TeacherProcessResult(0, finalOutput) } else { TeacherProcessResult(0, "internal detail") }
    }
}
private class StageFailureExecutor <: TeacherCommandExecutor {
    private let stage: String
    public init(stage: String) { this.stage = stage }
    public func execute(spec: TeacherCommandSpec): TeacherProcessResult {
        if (spec.args[0] == stage) { TeacherProcessResult(9, "protected detail") }
        else { TeacherProcessResult(0, "passed") }
    }
}
private class ThrowingVerifierExecutor <: TeacherCommandExecutor {
    public func execute(_: TeacherCommandSpec): TeacherProcessResult {
        throw IllegalStateException("/Users/private token=secret")
    }
}

@Test
public class TeacherSkillLeakageAuditTest {
    // P2-NEG-01 / P6-NEG-01: both single-asset and combined leakage are rejected.
    @TestCase public func singleAndCombinationLeakageFailClosed(): Unit {
        let protected = "first enumerate every unicode input boundary and preserve the selected unit before appending the normalized output into a fresh collection"
        let direct = leakCandidate(procedure: protected)
        @Expect(auditSkillAgainstProtectedArtifacts(direct, [protected]).passed, false)
        let split = leakCandidate(procedure: "First enumerate")
        @Expect(auditSkillAgainstProtectedArtifacts(split, [protected]).passed, true)
        @Expect(auditSkillCombinationLeakage(split,
            "every unicode input boundary and preserve the selected unit before appending the normalized output into a fresh collection",
            [protected]).passed, false)
        let marked = leakCandidate(procedure: "Rerun the test and apply a compiler repair.")
        @Expect(auditSkillAgainstProtectedArtifacts(marked, []).passed, false)
    }

    // P6-UT-01 / P6-POS-01: the exact frozen objects bind one Teacher run without case-selected Skill logic.
    @TestCase public func runnerConsumesFrozenFailureObjectsAsCoarseObservation(): Unit {
        let input = parseTeacherCompletionFailureInput(LEAK_FAILURE)
        let classification = parseTeacherFailureClassification(LEAK_CLASSIFICATION)
        let process = BoundProcess()
        let caseValue = TeacherCaseManifest("CJ-HUMANEVAL-007", "cangjie-humaneval-164-v1", "prompt", "starter",
            "func generic(value: String): String", "verifier")
        let run = runTeacherCase(caseValue, TeacherRunOptions("bound-run", "/tmp/unused-teacher-bound", "teacher-model",
            process, BoundVerifier(), BoundClock(), failureInput: Some(input), failureClassification: Some(classification)))
        @Expect(run.status, "verified")
        @Expect(process.feedback.contains("failure_type=mixed"), true)
        @Expect(process.feedback.contains("中文😀"), true)
        @Expect(process.feedback.contains("CJ-HUMANEVAL"), false)
        @Expect(process.feedback.contains(input.completionHash), false)
    }

    // P6-BND-01 / P6-NEG-01: protected verifier details never cross the process boundary.
    @TestCase public func protectedVerifierReturnsOnlyCoarseStatus(): Unit {
        let root = "/tmp/teacher-verifier-coarse-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            Directory.create(Path("${root}/tests/CJ-HUMANEVAL-007/tests"), recursive: true)
            Directory.create(Path("${root}/solution/src"), recursive: true)
            File.writeTo(Path("${root}/solution/cjpm.toml"), "original".toArray())
            File.writeTo(Path("${root}/tests/CJ-HUMANEVAL-007/tests/cjpm.executable.toml"), "test".toArray())
            File.writeTo(Path("${root}/tests/CJ-HUMANEVAL-007/tests/TestMain.cj"), "protected".toArray())
            let caseValue = TeacherCaseManifest("CJ-HUMANEVAL-007", "dataset", "prompt", "starter", "func generic(): Unit", "verifier")
            let detail = "Exception: CangjieEval failure: expected 42 actual 7 /Users/private token=secret 中文😀"
            let result = CjpmTeacherVerifier("${root}/tests", executor: VerifierExecutor(detail)).verify(caseValue, "${root}/solution")
            @Expect(result.exitCode, 5)
            @Expect(result.output, "failed")
            @Expect(result.output.contains("42"), false)
            @Expect(result.output.contains("/Users"), false)
            let invalid = CjpmTeacherVerifier("${root}/tests", executor: VerifierExecutor("invalid_response_encoding"))
                .verify(caseValue, "${root}/solution")
            @Expect(invalid.exitCode, 65)
            @Expect(invalid.output, "infra_error")

            for (stage in ["build", "test", "run"]) {
                let business = CjpmTeacherVerifier("${root}/tests", executor: StageFailureExecutor(stage))
                    .verify(caseValue, "${root}/solution")
                @Expect(business.exitCode, 9)
                @Expect(business.output, "failed")
                @Expect(business.output.contains("protected detail"), false)
            }
            let executionFailure = CjpmTeacherVerifier("${root}/tests", executor: ThrowingVerifierExecutor())
                .verify(caseValue, "${root}/solution")
            @Expect(executionFailure.exitCode, 127)
            @Expect(executionFailure.output, "infra_error")
            let missingFixtureCase = TeacherCaseManifest("CJ-HUMANEVAL-008", "dataset", "prompt", "starter",
                "func generic(): Unit", "verifier")
            let missingFixture = CjpmTeacherVerifier("${root}/tests", executor: VerifierExecutor("passed"))
                .verify(missingFixtureCase, "${root}/solution")
            @Expect(missingFixture.exitCode, 4)
            @Expect(missingFixture.output, "infra_error")
            Directory.create(Path("${root}/tests/CJ-HUMANEVAL-009/tests"), recursive: true)
            let unreadableFixtureCase = TeacherCaseManifest("CJ-HUMANEVAL-009", "dataset", "prompt", "starter",
                "func generic(): Unit", "verifier")
            let unreadableFixture = CjpmTeacherVerifier("${root}/tests", executor: VerifierExecutor("passed"))
                .verify(unreadableFixtureCase, "${root}/solution")
            @Expect(unreadableFixture.exitCode, 4)
            @Expect(unreadableFixture.output, "infra_error")

            File.writeTo(Path("${root}/solution/cjpm.toml"), [UInt8(0xff), UInt8(0xfe)])
            let invalidProject = CjpmTeacherVerifier("${root}/tests", executor: VerifierExecutor("passed"))
                .verify(caseValue, "${root}/solution")
            @Expect(invalidProject.exitCode, 65)
            @Expect(invalidProject.output, "infra_error")
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

    // P6-NEG-01: knowledge export rejects case IDs and detailed verifier-driven instructions.
    @TestCase public func knowledgeAndCaseSpecificityRemainAnonymous(): Unit {
        let observation = TeacherObservation("CJ-HUMANEVAL-007", "standard_library", "Rune iteration", "1.0.0",
            "Use Rune iteration for general Unicode boundaries.", "https://docs.cangjie-lang.cn/docs/1.0.0/", "official", "sha256:evidence")
        let tests = buildKnowledgeAtomTestBundle("generic positive", "generic negative", "generic 中文😀 boundary")
        let exported = renderCandidateKnowledgeExport(observation, "generic example", tests)
        @Expect(exported.identity, canonicalKnowledgeIdentity(observation))
        @Expect(auditCaseSpecificity(exported, ["func protectedName"] ).passed, true)
        var rejected = false
        try { _ = renderCandidateKnowledgeExport(observation, "CJ-HUMANEVAL-007", tests) }
        catch (_: Exception) { rejected = true }
        @Expect(rejected, true)
    }
}
