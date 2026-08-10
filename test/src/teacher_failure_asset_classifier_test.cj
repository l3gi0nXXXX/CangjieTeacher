package cangjie_teacher_test

import std.unittest.testmacro.*
import std.fs.*
import std.time.*
import cangjie_teacher.*

private class R6ClassifierProcess <: TeacherCommandExecutor {
    public let response: String
    public var calls: Int64 = 0
    public var invalidEncoding = false
    public init(response: String) { this.response = response }
    public func execute(spec: TeacherCommandSpec): TeacherProcessResult {
        calls += 1
        if (invalidEncoding) { File.writeTo(Path(spec.args[3]), [UInt8(0xff)]) }
        else { _ = teacherAtomicWrite(spec.args[3], response + "\n") }
        TeacherProcessResult(0, "ignored provider console output")
    }
}

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
    // R6-T2-UT/POS/BND/NEG: strict process adapter accepts canonical Unicode requests only.
    @TestCase public func r6T2StrictClassifierProcessContract(): Unit {
        let root = "/tmp/teacher-r6-classifier-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            Directory.create(Path("${root}/workspace"), recursive: true)
            _ = teacherAtomicWrite("${root}/classifier", "deterministic classifier adapter\n")
            let canonical = canonicalize(Path(root)).toString()
            let executable = "${canonical}/classifier"
            let response = renderTeacherFailureAssetClassifierResponse(
                s2InternalClassification("rules_gap", false, false, true,
                    "missing_global_invariant"))
            let process = R6ClassifierProcess(response)
            let adapter = StrictProcessTeacherFailureAssetClassifier(executable,
                teacherValidationExecutableHash(executable), canonical, "${canonical}/workspace",
                executor: process)
            let request = TeacherFailureAssetClassifierRequest(
                "f08453591302a46c4acc04c43d9bdf456679fae27b354bbca7ebecb194c1e773",
                "公开编译摘要🙂", "public summary", "official Cangjie authority")
            @Expect(adapter.classify(request), response); @Expect(process.calls, 1)

            Directory.create(Path("${root}/workspace-invalid"), recursive: true)
            let invalid = R6ClassifierProcess(response); invalid.invalidEncoding = true
            let invalidAdapter = StrictProcessTeacherFailureAssetClassifier(executable,
                teacherValidationExecutableHash(executable), canonical,
                "${canonical}/workspace-invalid", executor: invalid)
            var encoding = ""
            try { _ = invalidAdapter.classify(request) }
            catch (e: Exception) { encoding = e.message }
            @Expect(encoding, "invalid_response_encoding")

            var drift = ""
            try { _ = StrictProcessTeacherFailureAssetClassifier(executable,
                "sha256:${teacherStableHash("wrong-binary")}", canonical,
                "${canonical}/workspace-invalid", executor: process) }
            catch (e: Exception) { drift = e.message }
            @Expect(drift, "classification_requires_review")
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

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
