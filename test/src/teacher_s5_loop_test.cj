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

private class S5CrashTransportProcess <: TeacherProcess {
    public func generate(_: TeacherCaseManifest, _: String, _: String, _: String, _: String): TeacherProcessResult {
        throw IllegalStateException("simulated_teacher_process_crash")
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

private func s5PersistSuccessfulTransport(root: String, runId: String,
    caseValue: TeacherCaseManifest, businessAttempt: Int64): Unit {
    _ = persistTeacherTransportStarted(root, runId, caseValue, businessAttempt, 1, "")
    let started = parseTeacherTransportEvidence(teacherReadUtf8File(
        teacherTransportManifestPath(root, runId, caseValue.caseId, businessAttempt, 1)))
    _ = persistTeacherTransportCompleted(root, started, TeacherProcessResult(0, "replacement"))
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
            let firstTransport = loadTeacherTransportEvidence(root, "teacher-s5", caseValue, 1)
            @Expect(firstTransport.size, 4)
            @Expect(firstTransport[0].status, "timeout")
            @Expect(firstTransport[1].status, "process_failed")
            @Expect(firstTransport[2].status, "empty_output")
            @Expect(firstTransport[3].status, "succeeded")
            @Expect(firstTransport[1].previousEvidenceHash, teacherTransportEvidenceHash(firstTransport[0]))
            let transportText = teacherJoin(firstTransport.map({entry: TeacherTransportEvidence =>
                renderTeacherTransportEvidence(entry)}), "\n")
            @Expect(transportText.contains("provider unavailable"), false)
            @Expect(transportText.toAsciiLower().contains("token="), false)
            @Expect(firstTransport[0].safeOutputHash.startsWith("sha256:"), true)
            @Expect(history[0].transportCount, firstTransport.size)
            @Expect(history[0].transportRootHash, teacherTransportChainRootHash(firstTransport))
            let timeoutPath = teacherTransportManifestPath(root, "teacher-s5", caseValue.caseId, 1, 1)
            let timeoutRaw = teacherReadUtf8File(timeoutPath)
            File.writeTo(Path(timeoutPath), timeoutRaw.replace("timeout", "succeeded").toArray())
            var statusTamperRejected = false
            try { _ = loadTeacherTransportEvidence(root, "teacher-s5", caseValue, 1) }
            catch (e: Exception) { statusTamperRejected = e.message == "teacher_transport_evidence_invalid" }
            @Expect(statusTamperRejected, true)
            File.writeTo(Path(timeoutPath), timeoutRaw.toArray())
            @Expect(process.feedback[1].contains("transport attempt"), true)
            @Expect(process.feedback[3].contains("attempt 1"), true)
            @Expect(process.feedback[4].contains("attempt 2"), true)
            @Expect(process.feedback[4].contains("😀"), true)
            @Expect(process.feedback[4].contains("/Users"), false)
            @Expect(process.feedback[4].toAsciiLower().contains("token="), false)
            @Expect(process.feedback[4].toRuneArray().size <= 4003, true)
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

    // S5-BND-01: a crash while a transport call is active leaves only transport
    // lineage and resumes the same effective business attempt.
    @TestCase public func transportCrashResumeKeepsSameBusinessAttempt(): Unit {
        let root = s5Root("transport-crash-resume")
        try {
            let caseValue = s5Case()
            let workspace = TeacherPaths(root).workspace("teacher-crash", caseValue.caseId)
            Directory.create(Path("${workspace}/src"), recursive: true)
            File.writeTo(Path("${workspace}/src/solution.cj"), "starter 中文😀".toArray())
            var crashed = false
            try {
                _ = runTeacherCase(caseValue, TeacherRunOptions("teacher-crash", root, "gpt-5.6-sol",
                    S5CrashTransportProcess(), S5FixedVerifier(), S5Clock(),
                    repairUntilVerified: true, persistAttemptProgress: true))
            } catch (e: Exception) { crashed = e.message == "simulated_teacher_process_crash" }
            @Expect(crashed, true)
            @Expect(loadTeacherAttemptEvidence(root, "teacher-crash", caseValue).size, 0)
            let interruptedTransport = loadTeacherTransportEvidence(root, "teacher-crash", caseValue, 1)
            @Expect(interruptedTransport.size, 1)
            @Expect(interruptedTransport[0].status, "started")

            let resumedProcess = S5TransportThenRepairProcess()
            let resumed = runTeacherCase(caseValue, TeacherRunOptions("teacher-crash", root, "gpt-5.6-sol",
                resumedProcess, S5FixedVerifier(), S5Clock(),
                repairUntilVerified: true, persistAttemptProgress: true))
            @Expect(resumed.status, "verified")
            @Expect(resumed.attempt, 1)
            @Expect(loadTeacherAttemptEvidence(root, "teacher-crash", caseValue).size, 1)
            let lineage = loadTeacherTransportEvidence(root, "teacher-crash", caseValue, 1)
            @Expect(lineage.size, 5)
            @Expect(lineage[0].status, "interrupted")
            @Expect(lineage[1].previousEvidenceHash, teacherTransportEvidenceHash(lineage[0]))
            let lastTransport = teacherTransportManifestPath(root, "teacher-crash", caseValue.caseId, 1, 5)
            File.writeTo(Path(lastTransport), [UInt8(0xff), UInt8(0xfe)])
            var transportRejected = false
            try { _ = loadTeacherTransportEvidence(root, "teacher-crash", caseValue, 1) }
            catch (e: Exception) { transportRejected = e.message == "teacher_transport_evidence_invalid" }
            @Expect(transportRejected, true)
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
            s5PersistSuccessfulTransport(root, "teacher-resume", caseValue, 1)
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
        let root = s5Root("completed-binding")
        let process = S5UnexpectedProcess()
        let options = TeacherRunOptions("teacher-s5", root, "gpt-5.6-sol", process,
            S5FixedVerifier(), S5Clock(), repairUntilVerified: true, persistAttemptProgress: true)
        try {
            let workspace = TeacherPaths(root).workspace("teacher-s5", caseValue.caseId)
            Directory.create(Path("${workspace}/src"), recursive: true)
            File.writeTo(Path("${workspace}/src/solution.cj"), "starter".toArray())
            let producer = S5TransportThenRepairProcess()
            let exact = finalizeTeacherRun(runTeacherCase(caseValue, TeacherRunOptions("teacher-s5", root,
                "gpt-5.6-sol", producer, S5FixedVerifier(), S5Clock(),
                repairUntilVerified: true, persistAttemptProgress: true)), true)
            teacherCopyTree(workspace, TeacherPaths(root).solution(caseValue.caseId))
            _ = persistTeacherRunArtifacts(root, exact, "generation", "verification")
            _ = persistTeacherSolutionBinding(root, exact)
            _ = persistTeacherCompletedAttemptBinding(root, exact, caseValue)
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

            remove(Path("${root}/runs/${exact.runId}/evidence/${exact.caseId}/solution.binding"))
            @Expect(teacherCompletedRunReusable(exact, caseValue, options), false)
            _ = persistTeacherSolutionBinding(root, exact)
            File.writeTo(Path("${root}/teacher-solutions/${caseValue.caseId}/src/solution.cj"), "tampered".toArray())
            @Expect(teacherCompletedRunReusable(exact, caseValue, options), false)
            teacherCopyTree(workspace, TeacherPaths(root).solution(caseValue.caseId))
            _ = persistTeacherSolutionBinding(root, exact)

            let lineage = loadTeacherTransportEvidence(root, exact.runId, caseValue, 1)
            let raw = lineage.map({entry: TeacherTransportEvidence =>
                renderTeacherTransportEvidence(entry) + "\n"})
            let lastPath = teacherTransportManifestPath(root, exact.runId, caseValue.caseId, 1, lineage.size)
            let lastRaw = raw[raw.size - 1]
            File.writeTo(Path(lastPath), lastRaw.replace(lineage[lineage.size - 1].safeOutputHash,
                "sha256:forged").toArray())
            @Expect(teacherCompletedRunReusable(exact, caseValue, options), false)
            File.writeTo(Path(lastPath), lastRaw.toArray())
            remove(Path(lastPath))
            @Expect(teacherCompletedRunReusable(exact, caseValue, options), false)
            File.writeTo(Path(lastPath), lastRaw.toArray())

            let transportRoot = Path("${root}/runs/${exact.runId}/transport/${caseValue.caseId}/business-1")
            remove(transportRoot, recursive: true)
            @Expect(teacherCompletedRunReusable(exact, caseValue, options), false)
            Directory.create(transportRoot, recursive: true)
            for (i in 0..raw.size) {
                File.writeTo(Path(teacherTransportManifestPath(root, exact.runId, caseValue.caseId, 1, i + 1)),
                    raw[i].toArray())
            }
            @Expect(teacherCompletedRunReusable(exact, caseValue, options), true)
            remove(transportRoot, recursive: true)
            s5PersistSuccessfulTransport(root, exact.runId, caseValue, 1)
            @Expect(teacherCompletedRunReusable(exact, caseValue, options), false)
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
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

        let longCompiler = "compiler diagnostic prefix: the original implementation attempted an invalid " +
            "conversion from a UTF-8 byte sequence into one Rune without validating the boundary first"
        let partialLeak = TeacherObservation(caseValue.caseId, "diagnostic", "Compile repair",
            "1.0.0", "the original implementation attempted an invalid conversion from a UTF-8 byte sequence " +
            "into one Rune", "", "teacher_empirical", empirical.evidenceHash)
        @Expect(validateObservationAgainstAuthority(partialLeak, caseValue, [longCompiler]), false)
        let shortCommon = TeacherObservation(caseValue.caseId, "algorithm_pattern", "Rune iteration",
            "1.0.0", "Iterate Rune values safely.", "", "teacher_empirical", empirical.evidenceHash)
        @Expect(validateObservationAgainstAuthority(shortCommon, caseValue, ["Rune"]), true)
    }

    // S5-NEG-01: adaptive similarity catches short, seven-token, and periodically
    // edited authority material without rejecting short reusable vocabulary.
    @TestCase public func adaptiveAuthoritySimilarityCoversEditsAndKeepsLegalControl(): Unit {
        let shortArtifact = "sensitive boundary phrase"
        @Expect(teacherProtectedArtifactSimilar("sensitive boundXry phrase", shortArtifact), true)
        @Expect(teacherProtectedArtifactSimilar("secret key", "secret key"), true)

        let sevenTokens = "alphaBravo charlieDelta echoFoxtrot golfHotel indiaJuliet kiloLima mikeNovember"
        let sixOfSeven = "alphaBravo charlieDelta echoFoxtrot golfHotel indiaJuliet kiloLima changedToken"
        @Expect(teacherProtectedArtifactSimilar(sixOfSeven, sevenTokens), true)

        let longArtifact = "This authority material describes a private benchmark transformation with " +
            "several distinctive clauses and a compiler-specific consequence for the generated answer."
        let editedRunes = longArtifact.toRuneArray()
        for (i in 15..editedRunes.size: 32) { editedRunes[i] = r'X' }
        @Expect(teacherProtectedArtifactSimilar(String(editedRunes), longArtifact), true)
        @Expect(teacherProtectedArtifactSimilar("Do not expose caseKey9.", "caseKey9"), true)
        @Expect(teacherProtectedArtifactSimilar("The visible literal is amberfox.", "amberfox"), true)
        @Expect(teacherProtectedArtifactSimilar("Use a different identifier.", "caseKey9"), false)
        @Expect(teacherProtectedArtifactSimilar("Iterate Rune values safely.", "Rune"), false)
    }

    // S5-NEG-01: every Student-visible candidate field, including atom-test
    // sources and serialized bundle metadata, is checked against authority.
    @TestCase public func candidateAllStudentVisibleFieldsUseOneAuthorityGate(): Unit {
        let caseValue = s5Case()
        let tests = KnowledgeAtomTestBundle("positive independent", "negative independent", "boundary independent")
        let base = TeacherCandidateExport("G-RUNE-COUNT", "algorithm_pattern", "Rune counting",
            "1.0.0", "Count one value for each Rune.", "Use a generic Rune iterator.", "",
            "teacher_empirical", "sha256:provenance", tests)
        let protected = ["compiler diagnostic with seven distinctive reusable authority tokens"]
        @Expect(validateTeacherCandidateAgainstAuthority(base, "{\"metadata\":\"independent\"}",
            caseValue, protected), true)
        let exampleLeak = TeacherCandidateExport(base.identity, base.knowledgeFamily, base.concept,
            base.targetVersion, base.explanation, caseValue.prompt, base.citation, base.sourceClass,
            base.provenanceHash, base.tests)
        @Expect(validateTeacherCandidateAgainstAuthority(exampleLeak, "{}", caseValue, protected), false)
        let positiveLeak = TeacherCandidateExport(base.identity, base.knowledgeFamily, base.concept,
            base.targetVersion, base.explanation, base.example, base.citation, base.sourceClass,
            base.provenanceHash, KnowledgeAtomTestBundle(caseValue.prompt, "negative", "boundary"))
        @Expect(validateTeacherCandidateAgainstAuthority(positiveLeak, "{}", caseValue, protected), false)
        @Expect(validateTeacherCandidateAgainstAuthority(base,
            "{\"metadata\":\"${caseValue.prompt}\"}", caseValue, protected), false)
    }
}
