package cangjie_teacher_test

import std.collection.*
import std.fs.*
import std.time.*
import std.unittest.testmacro.*
import cangjie_teacher.*

private func s5Root(name: String): String {
    "/tmp/cangjie-teacher-s5-${name}-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
}

private func s5Case(): TeacherCaseManifest {
    TeacherCaseManifest("CJ-HUMANEVAL-125", "dataset-clean-v1", "prompt-clean-hash", "starter-clean-hash",
        "func boundedRuneCount(value: String): Int64", "verifier-clean-hash",
        prompt: "Count Unicode runes in the supplied String without splitting UTF-8 sequences.",
        targetVersion: "1.0.0", requiredKnowledgeTags: ["String", "Rune"])
}

private class S5Clock <: TeacherClock {
    public func nowMillis(): Int64 { 1 }
}

private class S5TransportThenRepairProcess <: TeacherProcess {
    public var calls: Int64 = 0
    public let feedback = ArrayList<String>()
    public func generate(_: TeacherCaseManifest, workspace: String, _: String, _: String,
        verifierFeedback: String): TeacherProcessResult {
        calls += 1
        feedback.add(verifierFeedback)
        if (calls == 1) { return TeacherProcessResult(124, "timeout", timedOut: true) }
        if (calls == 2) { return TeacherProcessResult(7, "provider unavailable") }
        if (calls == 3) { return TeacherProcessResult(0, "") }
        File.writeTo(Path("${workspace}/src/solution.cj"), "solution-${calls} 中文😀".toArray())
        TeacherProcessResult(0, "generated")
    }
}

private class S5RepairVerifier <: TeacherVerifier {
    private var calls: Int64 = 0
    public func verify(_: TeacherCaseManifest, _: String): TeacherProcessResult {
        calls += 1
        if (calls == 1) {
            var diagnostic = "编译失败😀 "
            for (_ in 0..3000) { diagnostic += "边界" }
            TeacherProcessResult(5, diagnostic +
                " /Users/private/reference token=must-not-survive")
        } else { TeacherProcessResult(0, "passed") }
    }
}

private class S5UnexpectedProcess <: TeacherProcess {
    public var called = false
    public func generate(_: TeacherCaseManifest, _: String, _: String, _: String, _: String): TeacherProcessResult {
        called = true
        TeacherProcessResult(9, "must not be reused or executed")
    }
}

private class S5FixedVerifier <: TeacherVerifier {
    public func verify(_: TeacherCaseManifest, _: String): TeacherProcessResult {
        TeacherProcessResult(0, "passed")
    }
}

private func s5Options(root: String, runId: String, process: TeacherProcess): TeacherRunOptions {
    TeacherRunOptions(runId, root, "gpt-5.6-sol", process, S5RepairVerifier(), S5Clock(),
        repairUntilVerified: true, persistAttemptProgress: true)
}

@Test
public class TeacherS5LoopTest {
    // S5-UT-01 / S5-POS-01: three transport failures consume no business attempt;
    // one verifier failure is fed to the next effective business attempt.
    @TestCase public func transportRetriesDoNotConsumeBusinessAttemptsAndRepairConverges(): Unit {
        let root = s5Root("transport-business-attempt")
        try {
            let caseValue = s5Case()
            let workspace = TeacherPaths(root).workspace("teacher-s5", caseValue.caseId)
            Directory.create(Path("${workspace}/src"), recursive: true)
            File.writeTo(Path("${workspace}/src/solution.cj"), "starter 中文😀".toArray())
            let process = S5TransportThenRepairProcess()
            let run = runTeacherCase(caseValue, s5Options(root, "teacher-s5", process))
            @Expect(run.status, "verified")
            @Expect(run.attempt, 2)
            @Expect(process.calls, 5)
            let history = loadTeacherAttemptEvidence(root, "teacher-s5", caseValue)
            @Expect(history.size, 2)
            @Expect(history[0].status, "verification_failed")
            @Expect(history[1].status, "verified")
            @Expect(process.feedback[1].contains("transport attempt"), true)
            @Expect(process.feedback[3].contains("attempt 1"), true)
            @Expect(process.feedback[4].contains("attempt 2"), true)
            @Expect(process.feedback[4].contains("😀"), true)
            @Expect(process.feedback[4].contains("/Users"), false)
            @Expect(process.feedback[4].toAsciiLower().contains("token="), false)
            @Expect(process.feedback[4].toRuneArray().size <= 4003, true)
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

    // S5-BND-01: an interrupted UTF-8 workspace resumes, while malformed UTF-8 evidence fails closed.
    @TestCase public func interruptedUtf8ResumeAndMalformedLedgerFailClosed(): Unit {
        let root = s5Root("resume-utf8")
        try {
            let caseValue = s5Case()
            let workspace = TeacherPaths(root).workspace("teacher-resume", caseValue.caseId)
            Directory.create(Path("${workspace}/src"), recursive: true)
            File.writeTo(Path("${workspace}/src/solution.cj"), "中断前😀".toArray())
            _ = persistTeacherAttemptStarted(root, "teacher-resume", caseValue, 1, "",
                teacherDirectoryHash("${workspace}/src"))
            File.writeTo(Path("${workspace}/src/solution.cj"), "中断后😀".toArray())
            let process = S5TransportThenRepairProcess()
            let resumed = runTeacherCase(caseValue, s5Options(root, "teacher-resume", process))
            @Expect(resumed.status, "verified")
            @Expect(loadTeacherAttemptEvidence(root, "teacher-resume", caseValue)[0].status, "interrupted")
            let manifest = teacherAttemptManifestPath(root, "teacher-resume", caseValue.caseId, 1)
            File.writeTo(Path(manifest), [UInt8(0xff), UInt8(0xfe)])
            var rejected = false
            try { _ = loadTeacherAttemptEvidence(root, "teacher-resume", caseValue) }
            catch (e: Exception) { rejected = e.message == "teacher_attempt_evidence_invalid" }
            @Expect(rejected, true)
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

    // S5-NEG-01: completed work is reusable only under the exact run/case/dataset/prompt/model binding.
    @TestCase public func completedRunReuseRejectsEveryIdentityDrift(): Unit {
        let caseValue = s5Case()
        let process = S5UnexpectedProcess()
        let options = TeacherRunOptions("teacher-s5", "/tmp/unused", "gpt-5.6-sol", process,
            S5FixedVerifier(), S5Clock())
        let exact = TeacherRunManifest("teacher-s5", caseValue.caseId, caseValue.datasetVersion,
            "gpt-5.6-sol", caseValue.promptHash, 3, "complete", 0, "sha256:evidence")
        @Expect(teacherCompletedRunReusable(exact, caseValue, options), true)
        @Expect(teacherCompletedRunReusable(TeacherRunManifest("other-run", exact.caseId, exact.datasetVersion,
            exact.modelId, exact.promptHash, 3, "complete", 0, exact.evidenceHash), caseValue, options), false)
        @Expect(teacherCompletedRunReusable(TeacherRunManifest(exact.runId, exact.caseId, exact.datasetVersion,
            "gpt-5.6-wol", exact.promptHash, 3, "complete", 0, exact.evidenceHash), caseValue, options), false)
        @Expect(teacherCompletedRunReusable(TeacherRunManifest(exact.runId, exact.caseId, "old-dataset",
            exact.modelId, exact.promptHash, 3, "complete", 0, exact.evidenceHash), caseValue, options), false)
        @Expect(teacherCompletedRunReusable(TeacherRunManifest(exact.runId, exact.caseId, exact.datasetVersion,
            exact.modelId, "old-prompt", 3, "complete", 0, exact.evidenceHash), caseValue, options), false)
        let reused = runTeacherBatch([caseValue], options, [exact])
        @Expect(reused[0].evidenceHash, exact.evidenceHash)
        @Expect(process.called, false)
    }

    // S5-NEG-01 / S5-REG-01: user-visible observation fields reject authority text,
    // while a reusable empirical rule with recomputable evidence hash remains valid.
    @TestCase public func observationRejectsAuthorityTextAndAcceptsAtomicEmpiricalRule(): Unit {
        let caseValue = s5Case()
        let empirical = TeacherObservation(caseValue.caseId, "algorithm_pattern", "Rune-safe counting",
            "1.0.0", "Iterate String.runes() and increment one counter for each Rune, including 中文😀.",
            "", "teacher_empirical", teacherStableHash("experiment-positive|negative|boundary"))
        @Expect(validateObservationAgainstAuthority(empirical, caseValue,
            ["compiler error: unrelated fixture"]), true)
        @Expect(validateTeacherObservation(empirical), true)
        let taskLeak = TeacherObservation(caseValue.caseId, "algorithm_pattern", "Rune-safe counting",
            "1.0.0", caseValue.prompt, "", "teacher_empirical", empirical.evidenceHash)
        @Expect(validateObservationAgainstAuthority(taskLeak, caseValue, []), false)
        let compiler = "compiler error: undeclared identifier originalName"
        let compilerLeak = TeacherObservation(caseValue.caseId, "diagnostic", "Compile repair",
            "1.0.0", compiler, "", "teacher_empirical", empirical.evidenceHash)
        @Expect(validateObservationAgainstAuthority(compilerLeak, caseValue, [compiler]), false)
        var deriveRejected = false
        try {
            _ = deriveKnowledgeObservation(caseValue, "algorithm_pattern", "Rune-safe counting", "1.0.0",
                caseValue.prompt, "", "teacher_empirical", "evidence")
        } catch (e: Exception) { deriveRejected = e.message == "teacher_observation_authority_leak" }
        @Expect(deriveRejected, true)
    }
}
