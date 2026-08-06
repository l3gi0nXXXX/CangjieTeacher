package cangjie_teacher_test

import std.unittest.testmacro.*
import std.fs.*
import std.time.*
import cangjie_teacher.*

private let FAILURE_FIXTURE = "{\"schemaVersion\":\"ckb-completion-failure-v1\",\"runId\":\"recert-fixture-run\",\"caseId\":\"CJ-HUMANEVAL-007\",\"datasetVersion\":\"cangjie-humaneval-164-v1\",\"generationProtocol\":\"completion-only-v1\",\"completionHash\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"baseStatus\":\"failed\",\"plusStatus\":\"failed\",\"failureKind\":\"test_failure\",\"failureObservation\":\"student_completion_test_failed 中文😀\",\"assetLineage\":\"independent\",\"evidenceHash\":\"f08453591302a46c4acc04c43d9bdf456679fae27b354bbca7ebecb194c1e773\"}"
private let CLASSIFICATION_FIXTURE = "{\"schemaVersion\":\"ckb-completion-failure-classification-v1\",\"failureEvidenceHash\":\"f08453591302a46c4acc04c43d9bdf456679fae27b354bbca7ebecb194c1e773\",\"gapKind\":\"mixed_gap\",\"knowledgeEligible\":true,\"skillEligible\":true,\"classificationEvidenceHash\":\"1ff85ffec78c69504a2f98146daebb75557d340b6366e92875c4c1acd4b44a16\"}"

private func skillFixtures(): Array<TeacherSkillFixture> {
    [
        TeacherSkillFixture("generic-rune-review", "Review a Unicode label formatter.", "Lists Rune boundaries before indexing."),
        TeacherSkillFixture("generic-empty-review", "Review an empty collection reducer.", "States the empty-input invariant."),
        TeacherSkillFixture("generic-overflow-review", "Review a bounded counter.", "Checks the numeric bound before addition.")
    ]
}

private func skillCandidate(): TeacherSkillCandidate {
    buildTeacherSkillCandidate(parseTeacherCompletionFailureInput(FAILURE_FIXTURE),
        parseTeacherFailureClassification(CLASSIFICATION_FIXTURE), "static-boundary-review", "1.0.0",
        "Static boundary review", "Before emitting code, enumerate input boundaries and verify one invariant for each.",
        "general_engineering", "One-shot statically typed implementation tasks.",
        buildTeacherSkillTestBundle(skillFixtures()), candidateOrigin: "independent_seed")
}

@Test
public class TeacherSkillCandidateTest {
    // P2-UT-01 / P6-UT-01 / L2: exact bytes and hashes are shared with CKB's frozen fixture.
    @TestCase public func frozenFailureFixtureAndSkillExportAreDeterministic(): Unit {
        let input = parseTeacherCompletionFailureInput(FAILURE_FIXTURE)
        let classification = parseTeacherFailureClassification(CLASSIFICATION_FIXTURE)
        @Expect(input.evidenceHash, "f08453591302a46c4acc04c43d9bdf456679fae27b354bbca7ebecb194c1e773")
        @Expect(classification.classificationEvidenceHash, "1ff85ffec78c69504a2f98146daebb75557d340b6366e92875c4c1acd4b44a16")
        @Expect(renderTeacherCompletionFailureInput(input), FAILURE_FIXTURE)
        @Expect(renderTeacherFailureClassification(classification), CLASSIFICATION_FIXTURE)
        @Expect(classifyTeacherOutputKind(input, classification), "mixed")
        let first = renderCandidateSkillExport(skillCandidate())
        let second = renderCandidateSkillExport(skillCandidate())
        @Expect(first, second)
        @Expect(first.contains("name: static-boundary-review"), true)
        @Expect(skillCandidate().tests.fixtures.size, 3)
    }

    // P2-POS-01 / P6-POS-01: one Skill proves generalization on three unrelated non-benchmark tasks.
    @TestCase public func threeIndependentFixturesProvideGeneralizationEvidence(): Unit {
        let candidate = skillCandidate()
        @Expect(validateSkillGeneralizationEvidence(candidate), true)
        @Expect(candidate.tests.fixtures[0].sourceClass, "non_humaneval")
        @Expect(candidate.tests.fixtures[1].sourceClass, "non_humaneval")
        @Expect(candidate.tests.fixtures[2].sourceClass, "non_humaneval")
    }

    // P2-BND-01 / P2-NEG-01 / P6-BND-01: strict JSON, Unicode, size, eligibility and hash fail closed.
    @TestCase public func failureSchemaRejectsEveryContractDrift(): Unit {
        for (raw in [
            FAILURE_FIXTURE.replace("\"runId\":", "\"unknown\":\"x\",\"runId\":"),
            FAILURE_FIXTURE.replace("\"runId\":", "\"runId\":\"duplicate\",\"runId\":"),
            FAILURE_FIXTURE.replace("test_failure", "other_failure"),
            FAILURE_FIXTURE.replace("student_completion_test_failed 中文😀", "Authorization token=secret /Users/private"),
            FAILURE_FIXTURE.replace("student_completion_test_failed 中文😀", String(Array<Rune>(513, repeat: r'界'))),
            FAILURE_FIXTURE.replace("f08453591302a46c4acc04c43d9bdf456679fae27b354bbca7ebecb194c1e773", String(Array<Rune>(64, repeat: r'0'))),
            " ${FAILURE_FIXTURE}",
            "{malformed-json"
        ]) {
            var rejected = false
            try { _ = parseTeacherCompletionFailureInput(raw) } catch (_: Exception) { rejected = true }
            @Expect(rejected, true)
        }
        var classificationRejected = false
        try { _ = parseTeacherFailureClassification(CLASSIFICATION_FIXTURE.replace("\"skillEligible\":true", "\"skillEligible\":false")) }
        catch (_: Exception) { classificationRejected = true }
        @Expect(classificationRejected, true)
        var insufficient = false
        try { _ = buildTeacherSkillTestBundle(skillFixtures()[..2]) } catch (_: Exception) { insufficient = true }
        @Expect(insufficient, true)

        let path = "/tmp/teacher-skill-invalid-utf8-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            File.writeTo(Path(path), [UInt8(0xff), UInt8(0xfe)])
            var invalidEncoding = false
            try { _ = parseTeacherCompletionFailureInput(teacherReadUtf8File(path)) }
            catch (e: Exception) { invalidEncoding = e.message == "invalid_response_encoding" }
            @Expect(invalidEncoding, true)
        } finally { try { remove(Path(path)) } catch (_: Exception) {} }
    }

    // P6-NEG-01: P5-derived candidates can never inherit an independent input lineage.
    @TestCase public func p6CandidateAlwaysUsesDerivedLineage(): Unit {
        let input = parseTeacherCompletionFailureInput(FAILURE_FIXTURE)
        let classification = parseTeacherFailureClassification(CLASSIFICATION_FIXTURE)
        let candidate = buildTeacherSkillCandidate(input, classification, "derived-review", "1.0.0",
            "Derived review", "Check a reusable static invariant.", "teacher_derived",
            "Generic one-shot code generation.", buildTeacherSkillTestBundle(skillFixtures()),
            candidateOrigin: "p6_failure_derived")
        @Expect(input.assetLineage, "independent")
        @Expect(candidate.lineage, "humaneval_164_derived")
    }
}
