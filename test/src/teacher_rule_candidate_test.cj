package cangjie_teacher_test

import std.unittest.testmacro.*
import std.fs.*
import std.time.*
import cangjie_teacher.*

public func s2RuleCandidate(): TeacherRuleCandidate {
    let internal = s2InternalClassification("rules_gap", false, false, true, "missing_global_invariant")
    let shared = reconcileTeacherFailureAssetClassifications(internal, internal)
    buildTeacherRuleCandidate(shared, "rune-safe-visible-text", "cangjie-rune-boundary",
        "Preserve Rune boundaries", "Bounded user-visible text must end at a complete Rune boundary. 中文🙂",
        "When rendering bounded user-visible text.", "Cangjie text rendering", 100,
        "completion_failure", shared.failureEvidenceHash,
        TeacherRuleTestBundle(executeTeacherAssetFixtureBundle(s2Fixtures(), FakeTeacherAssetFixtureExecutor())))
}

@Test
public class TeacherRuleCandidateTest {
    @TestCase public func ruleCandidateRendersDeterministically(): Unit {
        let candidate = s2RuleCandidate()
        let first = renderTeacherAgentsMarkdown([candidate])
        let second = renderTeacherAgentsMarkdown([candidate])
        @Expect(first, second)
        @Expect(candidate.assetLineage, "humaneval_164_derived")
        @Expect(first.contains("中文🙂"), true)
        @Expect(first.toArray().size <= 8192, true)
        let root = "/tmp/teacher-rule-s2-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            let manifest = exportTeacherRuleCandidateDirectory(candidate, root)
            @Expect(exportTeacherRuleCandidateDirectory(candidate, root), manifest)
            @Expect(exists(Path("${root}/${candidate.ruleId}/AGENTS.md")), true)
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
        var secretRejected = ""
        try { _ = buildTeacherRuleCandidate(
            reconcileTeacherFailureAssetClassifications(
                s2InternalClassification("rules_gap", false, false, true, "missing_global_invariant"),
                s2InternalClassification("rules_gap", false, false, true, "missing_global_invariant")),
            "bad-rule", "bad-concept", "Unsafe", "token=secret", "Generic trigger", "Generic scope", 1,
            "completion_failure", "f08453591302a46c4acc04c43d9bdf456679fae27b354bbca7ebecb194c1e773",
            TeacherRuleTestBundle(executeTeacherAssetFixtureBundle(s2Fixtures(), FakeTeacherAssetFixtureExecutor()))) }
        catch (e: Exception) { secretRejected = e.message }
        @Expect(secretRejected, "candidate_test_evidence_invalid")
    }
}
