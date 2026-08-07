package cangjie_teacher_test

import std.unittest.testmacro.*
import cangjie_teacher.*

public func s2InternalClassification(gap: String, knowledge: Bool, skill: Bool, rules: Bool,
    reason: String): TeacherFailureAssetClassification {
    let evidence = "{\"schemaVersion\":\"teacher-failure-asset-classification-v2\"," +
        "\"failureEvidenceHash\":\"f08453591302a46c4acc04c43d9bdf456679fae27b354bbca7ebecb194c1e773\"," +
        "\"gapKind\":\"${gap}\",\"knowledgeEligible\":${knowledge},\"skillEligible\":${skill}," +
        "\"rulesEligible\":${rules},\"classificationReasonCode\":\"${reason}\"}"
    TeacherFailureAssetClassification("teacher-failure-asset-classification-v2",
        "f08453591302a46c4acc04c43d9bdf456679fae27b354bbca7ebecb194c1e773",
        gap, knowledge, skill, rules, reason, teacherStableHash(evidence))
}

@Test
public class TeacherFailureAssetClassifierTest {
    @TestCase public func failureAssetClassifiersMustAgreeBeforeSeal(): Unit {
        let first = s2InternalClassification("all_assets_gap", true, true, true, "multiple_reusable_gaps")
        let raw = renderTeacherFailureAssetClassifierResponse(first)
        let second = parseTeacherFailureAssetClassifierResponse(raw)
        let sealed = reconcileTeacherFailureAssetClassifications(first, second)
        @Expect(sealed.schemaVersion, "ckb-completion-failure-classification-v2")
        @Expect(classifyTeacherAssetOutputKind(sealed), "all")
        @Expect(renderTeacherFailureAssetClassification(sealed).contains("teacher-failure-asset-classification-v2"), false)

        var disagreed = ""
        try { _ = reconcileTeacherFailureAssetClassifications(first,
            s2InternalClassification("rules_gap", false, false, true, "missing_global_invariant")) }
        catch (e: Exception) { disagreed = e.message }
        @Expect(disagreed, "classification_requires_review")

        let request = TeacherFailureAssetClassifierRequest(first.failureEvidenceHash,
            "编译摘要🙂不含私有输入", "public test summary", "official Cangjie 1.0 authority")
        @Expect(renderTeacherFailureAssetClassifierRequest(request).contains("中文"), false)
        var leakRejected = false
        try { _ = renderTeacherFailureAssetClassifierRequest(TeacherFailureAssetClassifierRequest(
            first.failureEvidenceHash, "token=secret", "summary", "authority")) }
        catch (_: Exception) { leakRejected = true }
        @Expect(leakRejected, true)
    }
}
