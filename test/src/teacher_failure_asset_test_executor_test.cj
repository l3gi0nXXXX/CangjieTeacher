package cangjie_teacher_test

import std.unittest.testmacro.*
import std.fs.*
import std.time.*
import stdx.encoding.json.*
import cangjie_teacher.*

class S2FailingFixtureExecutor <: TeacherAssetFixtureExecutor {
    private let identity = sealTeacherValidationIdentity("scaffold", "fake-scaffold-v1", "scaffold",
        "sha256:${teacherStableHash("s2-fake-runtime")}",
        "sha256:${teacherStableHash("s2-fake-control")}",
        "sha256:${teacherStableHash("s2-fake-prompt")}")
    public func executorKind(): String { "fake_contract" }
    public func providerIdentityHash(): String { "sha256:${teacherStableHash("fake")}" }
    public func modelVersion(): String { "fake-scaffold-v1" }
    public func validationIdentity(): TeacherValidationIdentity { identity }
    public func execute(target: TeacherAssetValidationTarget,
        fixture: TeacherAssetFixture): (Int64, String, String) {
        (1, "different", "synthetic failure transcript")
    }
}

public func s2Fixtures(): Array<TeacherAssetFixture> {
    [
        TeacherAssetFixture("positive-rune", "positive", "non_humaneval_experiment",
            "Render 中文🙂 at a Rune boundary.", "positive_passed"),
        TeacherAssetFixture("negative-byte", "negative", "non_humaneval_experiment",
            "Reject splitting one encoded Rune.", "negative_rejected"),
        TeacherAssetFixture("boundary-max", "boundary", "non_humaneval_experiment",
            "Accept the exact UTF-8 byte budget.", "boundary_passed"),
        TeacherAssetFixture("generalization-label", "generalization", "non_humaneval_experiment",
            "Apply the invariant to a generic label renderer.", "generalization_passed")
    ]
}

private class R6StudentVerifierRunner <: TeacherStudentRuntimeExecutor {
    public var calls: Int64 = 0
    public var request = ""
    public var candidateProjection = ""
    public var launchCommand = ""
    public var sandboxProfile = ""
    public var tamperFixture = false
    public var invalidEncoding = false
    public var malformed = false
    public var streamArray = false
    public var duplicateTerminal = false
    public var trailingAfterTerminal = false
    public var invalidNestedEvidence = false
    public var nestedEvidence = false
    public var streamPaddingSize: Int64 = 0
    public var exitCode: Int64 = 0
    public func execute(spec: TeacherStudentRuntimeSpec): TeacherStudentRuntimeResult {
        calls += 1
        request = teacherReadUtf8File("${spec.cwd}/prompt.final.md")
        candidateProjection = request
        launchCommand = spec.args[1]
        sandboxProfile = teacherReadUtf8File("${spec.cwd}/sandbox.sb")
        let structured = if (tamperFixture) {
            "{\"solution_cj\":\"positive_passed\",\"extra\":true}"
        } else if (invalidNestedEvidence) {
            "{\"solution_cj\":\"{\\\"actualEvidence\\\":\\\"positive_passed\\\",\\\"extra\\\":true}\"}"
        } else if (nestedEvidence) {
            "{\"solution_cj\":\"{\\\"actualEvidence\\\":\\\"positive_passed\\\"}\"}"
        } else { "{\"solution_cj\":\"positive_passed\"}" }
        let envelope = "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false," +
            "\"modelUsage\":{\"gpt-5.6-sol\":{}},\"structured_output\":${structured}}"
        let padding = String(Array<Rune>(streamPaddingSize, repeat: r'x'))
        let initEvent = "{\"type\":\"system\",\"subtype\":\"init\",\"padding\":\"${padding}\"}"
        let output = if (malformed) { "{malformed" }
            else if (duplicateTerminal) { "[${initEvent},${envelope},${envelope}]" }
            else if (trailingAfterTerminal) { "[${initEvent},${envelope},${initEvent}]" }
            else if (streamArray) { "[${initEvent},${envelope}]" }
            else { envelope }
        if (invalidEncoding) {
            File.writeTo(Path("${spec.cwd}/transcript.json"), [UInt8(0xff)])
        }
        TeacherStudentRuntimeResult(exitCode,
            if (invalidEncoding) { "" } else { output },
            "provider stderr must stay separate")
    }
}

private func r6Control(model: String): String {
    renderTeacherStudentCompletionControl(TeacherStudentCompletionControl(
        "D-ckb-mcp-http", "completion-only-v1", 1,
        "sha256:${teacherStableHash(teacherStudentCompletionOutputSchema())}",
        "sha256:${teacherStableHash("sampling")}", 65536, 0, 600,
        "sha256:${teacherStableHash("runtime-config")}",
        teacherStudentCompletionCommandHash(model)))
}

private func r6Identity(runtimeExecutable: String, control: String): TeacherValidationIdentity {
    sealTeacherValidationIdentity("codex", "gpt-5.6-sol", "claude-code-2.1.0",
        teacherValidationExecutableHash(runtimeExecutable),
        "sha256:${teacherStableHash(control)}",
        "sha256:${teacherStableHash("prompt-capability-v1")}")
}

private class R6CandidateDriftExecutor <: TeacherAssetFixtureExecutor {
    private let identity: TeacherValidationIdentity
    public init(identity: TeacherValidationIdentity) { this.identity = identity }
    public func executorKind(): String { "student_completion_non_humaneval" }
    public func providerIdentityHash(): String { identity.identityHash }
    public func modelVersion(): String { identity.modelVersion }
    public func validationIdentity(): TeacherValidationIdentity { identity }
    public func execute(target: TeacherAssetValidationTarget,
        fixture: TeacherAssetFixture): (Int64, String, String) {
        let drifted = buildTeacherAssetValidationTarget(target.lane,
            target.candidateVisibleProjection + " drift", target.baseCompositeHash, identity)
        let transcript = buildTeacherStudentValidationTranscript(fixture, drifted,
            fixture.expectedEvidence, "sha256:${teacherStableHash("verified")}", 0)
        (0, fixture.expectedEvidence, renderTeacherStudentValidationTranscript(transcript))
    }
}

@Test
public class TeacherFailureAssetTestExecutorTest {
    // R6-T1-UT: canonical identity bytes and transcript hashes are deterministic.
    @TestCase public func r6T1IdentityAndTranscriptContract(): Unit {
        // Frozen against CKB ckbStudentCompletionCommandHash("GLM-5.2").
        @Expect(teacherStudentCompletionCommandHash("GLM-5.2"),
            "sha256:314643ecc3a5aeadbf2ca066c3e02542f57cc5a9da11ce4e76378067cf93120f")
        let identity = sealTeacherValidationIdentity("codex", "gpt-5.6-sol", "claude-code-2.1.0",
            "sha256:${teacherStableHash("runtime")}", "sha256:${teacherStableHash("control")}",
            "sha256:${teacherStableHash("prompt")}")
        let raw = renderTeacherValidationIdentity(identity)
        @Expect(raw.endsWith("\n"), true)
        @Expect(parseTeacherValidationIdentity(raw).identityHash, identity.identityHash)
        let fixture = s2Fixtures()[0]
        let target = buildTeacherAssetValidationTarget("rules", "# Student Rules\n\n中文🙂\n",
            "none", identity)
        let transcript = buildTeacherStudentValidationTranscript(fixture, target,
            fixture.expectedEvidence, "sha256:${teacherStableHash("verified")}", 0)
        @Expect(parseTeacherStudentValidationTranscript(
            renderTeacherStudentValidationTranscript(transcript)).candidateVisibleHash,
            target.candidateProjectionHash)
    }

    // R6-T1-POS/BND: production runner receives the exact Unicode candidate projection.
    @TestCase public func r6T1StudentExecutorIsCandidateAware(): Unit {
        let root = "/tmp/teacher-r6-t1-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            Directory.create(Path("${root}/workspace"), recursive: true)
            _ = teacherAtomicWrite("${root}/runtime", "deterministic provider runtime\n")
            let canonical = canonicalize(Path(root)).toString()
            let runtime = "${canonical}/runtime"
            let control = r6Control("gpt-5.6-sol")
            _ = teacherAtomicWrite("${root}/completion-control.json", control)
            let runner = R6StudentVerifierRunner(); runner.streamArray = true
            runner.streamPaddingSize = 40000
            let identity = r6Identity(runtime, control)
            let executor = StudentCompletionNonHumanEvalExecutor(runtime, canonical, "${canonical}/workspace",
                "${canonical}/completion-control.json", identity, executor: runner)
            let projection = "# Student Rules\n\nKeep 中文🙂 on Rune boundaries.\n"
            let target = buildTeacherAssetValidationTarget("rules", projection, "none", identity)
            let results = executeTeacherAssetFixtureBundle([s2Fixtures()[0]], executor, target)
            @Expect(results[0].passed, true); @Expect(runner.calls, 1)
            @Expect(runner.candidateProjection.contains(projection.replace("\n", "\\n")), true)
            @Expect(runner.request.contains("positive_passed"), false)
            @Expect(runner.request.contains("expectedEvidence"), false)
            @Expect(runner.request.contains("only the exact evidence token requested by input"), true)
            @Expect(runner.request.contains("do not add explanations, punctuation, prefixes, or suffixes"), true)
            @Expect(runner.launchCommand.contains("--tools ''"), true)
            @Expect(runner.launchCommand.contains("--setting-sources ''"), true)
            @Expect(runner.launchCommand.contains("< '${canonical}/workspace/"), true)
            @Expect(runner.sandboxProfile.contains("(deny default)"), true)
            @Expect(runner.sandboxProfile.contains("(allow default)"), false)
            @Expect(runner.sandboxProfile.contains("/Users/"), false)
            @Expect(runner.sandboxProfile.contains(".claude"), false)
            @Expect(parseTeacherStudentValidationTranscript(results[0].transcript)
                .validationIdentityHash, identity.identityHash)

            Directory.create(Path("${root}/workspace-nested"), recursive: true)
            let nestedRunner = R6StudentVerifierRunner(); nestedRunner.nestedEvidence = true
            let nestedExecutor = StudentCompletionNonHumanEvalExecutor(runtime, canonical,
                "${canonical}/workspace-nested", "${canonical}/completion-control.json",
                identity, executor: nestedRunner)
            @Expect(executeTeacherAssetFixtureBundle([s2Fixtures()[0]], nestedExecutor, target)[0].passed, true)
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

    // R6-T1-NEG: runner response tamper and executable identity drift fail closed.
    @TestCase public func r6T1StudentExecutorRejectsTamper(): Unit {
        let root = "/tmp/teacher-r6-t1-neg-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            Directory.create(Path("${root}/workspace"), recursive: true)
            _ = teacherAtomicWrite("${root}/runtime", "runtime-a\n")
            let canonical = canonicalize(Path(root)).toString()
            let runtime = "${canonical}/runtime"
            let control = r6Control("gpt-5.6-sol")
            _ = teacherAtomicWrite("${root}/completion-control.json", control)
            let identity = r6Identity(runtime, control); let runner = R6StudentVerifierRunner()
            runner.tamperFixture = true
            let executor = StudentCompletionNonHumanEvalExecutor(runtime, canonical, "${canonical}/workspace",
                "${canonical}/completion-control.json", identity, executor: runner)
            let target = buildTeacherAssetValidationTarget("rules", "candidate", "none", identity)
            var diagnostic = ""
            try { _ = executeTeacherAssetFixtureBundle([s2Fixtures()[0]], executor, target) }
            catch (e: Exception) { diagnostic = e.message }
            @Expect(diagnostic, "candidate_test_evidence_invalid")
            _ = teacherAtomicWrite("${root}/other-runtime", "runtime-b\n")
            var drift = ""
            try { _ = StudentCompletionNonHumanEvalExecutor("${canonical}/other-runtime", canonical,
                "${canonical}/workspace",
                "${canonical}/completion-control.json", identity, executor: runner) }
            catch (e: Exception) { drift = e.message }
            @Expect(drift, "student_validation_identity_mismatch")

            var escaped = ""
            try { _ = StudentCompletionNonHumanEvalExecutor(runtime, canonical, "${canonical}/../",
                "${canonical}/completion-control.json", identity, executor: runner) }
            catch (e: Exception) { escaped = e.message }
            @Expect(escaped, "artifact_input_invalid")

            Directory.create(Path("${root}/workspace-invalid-utf8"), recursive: true)
            let invalidRunner = R6StudentVerifierRunner(); invalidRunner.invalidEncoding = true
            let invalidExecutor = StudentCompletionNonHumanEvalExecutor(runtime, canonical,
                "${canonical}/workspace-invalid-utf8", "${canonical}/completion-control.json",
                identity, executor: invalidRunner)
            var encoding = ""
            try { _ = executeTeacherAssetFixtureBundle([s2Fixtures()[0]], invalidExecutor,
                buildTeacherAssetValidationTarget("rules", "different-candidate", "none", identity)) }
            catch (e: Exception) { encoding = e.message }
            @Expect(encoding, "invalid_response_encoding")

            var candidateDrift = ""
            try { _ = executeTeacherAssetFixtureBundle([s2Fixtures()[0]],
                R6CandidateDriftExecutor(identity),
                buildTeacherAssetValidationTarget("rules", "bound-candidate", "none", identity)) }
            catch (e: Exception) { candidateDrift = e.message }
            @Expect(candidateDrift, "candidate_test_evidence_invalid")

            Directory.create(Path("${root}/workspace-control-drift"), recursive: true)
            let controlRunner = R6StudentVerifierRunner()
            let controlExecutor = StudentCompletionNonHumanEvalExecutor(runtime, canonical,
                "${canonical}/workspace-control-drift", "${canonical}/completion-control.json",
                identity, executor: controlRunner)
            _ = teacherAtomicWrite("${root}/completion-control.json",
                control.replace("\"transportRetryBudget\":0", "\"transportRetryBudget\":1"))
            var controlDrift = ""
            try { _ = executeTeacherAssetFixtureBundle([s2Fixtures()[0]], controlExecutor,
                buildTeacherAssetValidationTarget("rules", "control-bound", "none", identity)) }
            catch (e: Exception) { controlDrift = e.message }
            @Expect(controlDrift, "student_validation_identity_mismatch")
            @Expect(controlRunner.calls, Int64(0))

            Directory.create(Path("${root}/workspace-nonzero"), recursive: true)
            let nonzeroRunner = R6StudentVerifierRunner(); nonzeroRunner.exitCode = 9
            // Restore the frozen control before exercising the process-exit boundary.
            _ = teacherAtomicWrite("${root}/completion-control.json", control)
            let nonzeroExecutor = StudentCompletionNonHumanEvalExecutor(runtime, canonical,
                "${canonical}/workspace-nonzero", "${canonical}/completion-control.json",
                identity, executor: nonzeroRunner)
            var nonzero = ""
            try { _ = executeTeacherAssetFixtureBundle([s2Fixtures()[0]], nonzeroExecutor,
                buildTeacherAssetValidationTarget("rules", "nonzero-bound", "none", identity)) }
            catch (e: Exception) { nonzero = e.message }
            @Expect(nonzero, "candidate_test_evidence_invalid")

            Directory.create(Path("${root}/workspace-malformed"), recursive: true)
            let malformedRunner = R6StudentVerifierRunner(); malformedRunner.malformed = true
            let malformedExecutor = StudentCompletionNonHumanEvalExecutor(runtime, canonical,
                "${canonical}/workspace-malformed", "${canonical}/completion-control.json",
                identity, executor: malformedRunner)
            var malformed = ""
            try { _ = executeTeacherAssetFixtureBundle([s2Fixtures()[0]], malformedExecutor,
                buildTeacherAssetValidationTarget("rules", "malformed-bound", "none", identity)) }
            catch (e: Exception) { malformed = e.message }
            @Expect(malformed, "malformed_json")

            Directory.create(Path("${root}/workspace-duplicate-terminal"), recursive: true)
            let duplicateRunner = R6StudentVerifierRunner(); duplicateRunner.duplicateTerminal = true
            let duplicateExecutor = StudentCompletionNonHumanEvalExecutor(runtime, canonical,
                "${canonical}/workspace-duplicate-terminal", "${canonical}/completion-control.json",
                identity, executor: duplicateRunner)
            var duplicate = ""
            try { _ = executeTeacherAssetFixtureBundle([s2Fixtures()[0]], duplicateExecutor,
                buildTeacherAssetValidationTarget("rules", "duplicate-terminal", "none", identity)) }
            catch (e: Exception) { duplicate = e.message }
            @Expect(duplicate, "candidate_test_evidence_invalid")

            Directory.create(Path("${root}/workspace-trailing-terminal"), recursive: true)
            let trailingRunner = R6StudentVerifierRunner(); trailingRunner.trailingAfterTerminal = true
            let trailingExecutor = StudentCompletionNonHumanEvalExecutor(runtime, canonical,
                "${canonical}/workspace-trailing-terminal", "${canonical}/completion-control.json",
                identity, executor: trailingRunner)
            var trailing = ""
            try { _ = executeTeacherAssetFixtureBundle([s2Fixtures()[0]], trailingExecutor,
                buildTeacherAssetValidationTarget("rules", "trailing-terminal", "none", identity)) }
            catch (e: Exception) { trailing = e.message }
            @Expect(trailing, "candidate_test_evidence_invalid")

            Directory.create(Path("${root}/workspace-over-budget"), recursive: true)
            let overBudgetRunner = R6StudentVerifierRunner(); overBudgetRunner.streamArray = true
            overBudgetRunner.streamPaddingSize = 70000
            let overBudgetExecutor = StudentCompletionNonHumanEvalExecutor(runtime, canonical,
                "${canonical}/workspace-over-budget", "${canonical}/completion-control.json",
                identity, executor: overBudgetRunner)
            var overBudget = ""
            try { _ = executeTeacherAssetFixtureBundle([s2Fixtures()[0]], overBudgetExecutor,
                buildTeacherAssetValidationTarget("rules", "over-budget", "none", identity)) }
            catch (e: Exception) { overBudget = e.message }
            @Expect(overBudget, "candidate_test_evidence_invalid")

            Directory.create(Path("${root}/workspace-invalid-nested"), recursive: true)
            let nestedRunner = R6StudentVerifierRunner(); nestedRunner.invalidNestedEvidence = true
            let nestedExecutor = StudentCompletionNonHumanEvalExecutor(runtime, canonical,
                "${canonical}/workspace-invalid-nested", "${canonical}/completion-control.json",
                identity, executor: nestedRunner)
            var nested = ""
            try { _ = executeTeacherAssetFixtureBundle([s2Fixtures()[0]], nestedExecutor,
                buildTeacherAssetValidationTarget("rules", "invalid-nested", "none", identity)) }
            catch (e: Exception) { nested = e.message }
            @Expect(nested, "candidate_test_evidence_invalid")
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

    @TestCase public func failureAssetFixtureResultsComeOnlyFromExecutor(): Unit {
        let results = executeTeacherAssetFixtureBundle(s2Fixtures(), FakeTeacherAssetFixtureExecutor())
        @Expect(results.size, 4)
        for (result in results) {
            @Expect(result.passed, true)
            @Expect(renderTeacherAssetFixtureExecution(result).contains("\"executorKind\":\"fake_contract\""), true)
            let files = teacherAssetFixtureExecutionFiles(result, "fixture")
            @Expect(files[1].content, result.fixture.expectedEvidence + "\n")
            @Expect(files[2].content, result.actualEvidence + "\n")
            @Expect(files[3].content, result.transcript + "\n")
        }
        let base = results[0]; let transcript = "normalized transcript\r\n\n"
        let suffixed = TeacherAssetFixtureExecution(base.fixture, base.fixtureHash, base.executorKind,
            base.providerIdentityHash, base.modelVersion, base.actualEvidence,
            "sha256:${teacherStableHash(teacherTranscriptSemantic(transcript))}",
            base.exitCode, base.passed,
            transcript: transcript)
        @Expect(teacherAssetFixtureExecutionFiles(suffixed, "fixture")[3].content,
            "normalized transcript\n")
        let invalidFixture = TeacherAssetFixture("invalid-line-ending", "unit",
            "non_humaneval_experiment", "input", "expected\n")
        let invalidExecution = TeacherAssetFixtureExecution(invalidFixture,
            teacherAssetFixtureHash(invalidFixture), "fake_contract", base.providerIdentityHash,
            base.modelVersion, "expected\n",
            "sha256:${teacherStableHash(teacherTranscriptSemantic("transcript"))}",
            0, true, transcript: "transcript")
        var lineEndingDiagnostic = ""
        try { _ = teacherAssetFixtureExecutionFiles(invalidExecution, "fixture") }
        catch (e: Exception) { lineEndingDiagnostic = e.message }
        @Expect(lineEndingDiagnostic, "candidate_test_evidence_invalid")
        let failed = executeTeacherAssetFixtureBundle([s2Fixtures()[0]], S2FailingFixtureExecutor())
        @Expect(failed[0].passed, false)
        @Expect(renderTeacherAssetFixtureExecution(failed[0]).contains("\"passed\":false"), true)
        var benchmarkRejected = ""
        try { _ = executeTeacherAssetFixtureBundle([TeacherAssetFixture("bad", "unit", "non_humaneval_experiment",
            "CJ-HUMANEVAL-007 hidden_test", "passed")], FakeTeacherAssetFixtureExecutor()) }
        catch (e: Exception) { benchmarkRejected = e.message }
        @Expect(benchmarkRejected, "candidate_test_evidence_invalid")
    }
}
