package cangjie_teacher_test

import std.collection.*
import std.fs.*
import std.time.*
import std.unittest.testmacro.*
import cangjie_teacher.*

private class CombineStudentExecutor <: TeacherAssetFixtureExecutor {
    private let identity = sealTeacherValidationIdentity("codex", "gpt-5.6-sol", "claude-code-2.1.0",
        "sha256:${teacherStableHash("combine-runtime")}",
        "sha256:${teacherStableHash("combine-control")}",
        "sha256:${teacherStableHash("combine-prompt")}")
    public var calls: Int64 = 0
    public let hashes = ArrayList<String>()
    public func executorKind(): String { "student_completion_non_humaneval" }
    public func providerIdentityHash(): String { identity.identityHash }
    public func modelVersion(): String { identity.modelVersion }
    public func validationIdentity(): TeacherValidationIdentity { identity }
    public func execute(target: TeacherAssetValidationTarget,
        fixture: TeacherAssetFixture): (Int64, String, String) {
        calls += 1; hashes.add(target.candidateProjectionHash)
        let transcript = buildTeacherStudentValidationTranscript(fixture, target,
            fixture.expectedEvidence, "sha256:${teacherStableHash("combine-${calls}")}", 0)
        (0, fixture.expectedEvidence, renderTeacherStudentValidationTranscript(transcript))
    }
}

private func combineFixtures(): Array<TeacherAssetFixture> {
    [
        TeacherAssetFixture("combine-unit", "unit", "non_humaneval_experiment", "Unit text boundary.", "unit-ok"),
        TeacherAssetFixture("combine-positive", "positive", "non_humaneval_experiment", "Positive text boundary.", "positive-ok"),
        TeacherAssetFixture("combine-negative", "negative", "non_humaneval_experiment", "Reject invalid boundary.", "negative-ok"),
        TeacherAssetFixture("combine-boundary", "boundary", "non_humaneval_experiment", "中文🙂 boundary.", "boundary-ok"),
        TeacherAssetFixture("combine-general-a", "generalization", "non_humaneval_experiment", "General label.", "general-a-ok"),
        TeacherAssetFixture("combine-general-b", "generalization", "non_humaneval_experiment", "General list.", "general-b-ok"),
        TeacherAssetFixture("combine-general-c", "generalization", "non_humaneval_experiment", "General empty text.", "general-c-ok")
    ]
}

private func combineProposal(index: Int64): TeacherFailureAssetGenerationResponse {
    let title = "Preserve Rune boundary ${index} 中文🙂"
    let content = "Apply Rune-safe boundary policy ${index} to reusable output. 中文🙂"
    let trigger = "When rendering reusable text ${index}"
    let scope = "Cangjie text output ${index}"
    let evidence = "{\"schemaVersion\":\"teacher-failure-asset-generation-response-v1\",\"lane\":\"rules\"," +
        "\"title\":\"${title}\",\"content\":\"${content}\",\"trigger\":\"${trigger}\"," +
        "\"scope\":\"${scope}\",\"priority\":${100 + index}}"
    TeacherFailureAssetGenerationResponse("rules", title, content, trigger, scope, 100 + index,
        "sha256:${teacherStableHash(evidence)}")
}

private func combineClassification(hash: String): TeacherFailureAssetClassification {
    sealTeacherFailureAssetClassification(TeacherFailureAssetClassification(
        "ckb-completion-failure-classification-v2", hash, "rules_gap", false, false, true,
        "missing_global_invariant", ""))
}

private func combinePrepare(root: String): (TeacherContextBaseStateV2, TeacherContextSourceClosure) {
    teacherCopyTree("fixtures/failure_assets_e2e/base-context", "${root}/base-context")
    teacherCopyTree("fixtures/failure_assets_e2e/scaffold-delta/source-root", "${root}/source-root")
    teacherCopyTree("fixtures/failure_assets_e2e/scaffold-delta/protected-root", "${root}/protected-root")
    Directory.create(Path("${root}/exports"), recursive: true)
    (loadTeacherContextBaseStateV2(root, "${root}/base-context"),
        loadTeacherContextSourceClosure(root, "${root}/source-root", "${root}/protected-root"))
}

private func combineSibling(root: String, base: TeacherContextBaseStateV2,
    closure: TeacherContextSourceClosure, index: Int64, executor: CombineStudentExecutor): String {
    let hash = "77271cefb38180b274bc6e41f8a5e9feddc035db05c30947dffbd544d2cd4319"
    let classification = combineClassification(hash)
    let proposal = combineProposal(index)
    let ruleId = "combine-rule-${index}"
    let projected = buildTeacherRuleCandidate(classification, ruleId, "combine-concept-${index}",
        proposal.title, proposal.content, proposal.trigger, proposal.scope, proposal.priority,
        "completion_failure", hash, TeacherRuleTestBundle(executeTeacherAssetFixtureBundle(
            combineFixtures(), executor, buildTeacherAssetValidationTarget("rules",
                base.rulesVisible, base.compositeHash, executor.validationIdentity()))))
    let operation = buildTeacherContextAssetOperation("rules", ruleId, "add", "",
        projected.canonicalHash, base.rulesAssets)
    let single = renderTeacherAgentsMarkdown([projected])
    let fragment = String(single.toRuneArray()["# Student Rules\n".toRuneArray().size..])
    let visible = teacherContextAssetProjection("rules", applyTeacherContextAssetOperation(
        base.rulesAssets, operation, fragment, priority: projected.priority))
    let executions = executeTeacherAssetFixtureBundle(combineFixtures(), executor,
        buildTeacherAssetValidationTarget("rules", visible, base.compositeHash,
            executor.validationIdentity()))
    let candidateRule = buildTeacherRuleCandidate(classification, ruleId, "combine-concept-${index}",
        proposal.title, proposal.content, proposal.trigger, proposal.scope, proposal.priority,
        "completion_failure", hash, TeacherRuleTestBundle(executions))
    let finalOperation = buildTeacherContextAssetOperation("rules", ruleId, "add", "",
        candidateRule.canonicalHash, base.rulesAssets)
    let files = teacherRuleCandidateArtifactFiles(candidateRule, finalOperation)
    let rules = TeacherContextLaneV2(true, "sha256:${teacherStableHash(visible)}",
        teacherContextLaneTreeHashV2(files), base.rulesAssets.size + 1,
        "humaneval_164_derived", visible, files)
    let skills = TeacherContextLaneV2(false, base.skillsHash, teacherContextLaneTreeHashV2([]),
        base.skillsCount, base.skillsLineage, base.skillsVisible, [])
    let knowledge = TeacherContextLaneV2(false, base.knowledgeHash, teacherContextLaneTreeHashV2([]),
        1, base.knowledgeLineage, base.knowledgeVisible, [])
    let bound = bindTeacherContextSourceClosureToBase(closure, base.closureBindings)
    let candidate = sealTeacherContextCandidateSetV2("sibling-${index}", base.compositeHash,
        "student_validated", "sha256:${String(Array<Rune>(64, repeat: r'a'))}", bound,
        rules, skills, knowledge, base.knowledgeVersion)
    _ = exportTeacherContextCandidateSetV2(candidate, root, "${root}/exports",
        baseContextRoot: "${root}/base-context")
    "${root}/exports/sibling-${index}"
}

@Test
public class TeacherContextCandidateCombineTest {
    @TestCase public func combinesThreeRulesWithFreshExecutionAndRepeatableCliParsing(): Unit {
        let root = "/tmp/teacher-combine-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            Directory.create(Path(root), recursive: true)
            let prepared = combinePrepare(root); let siblingExecutor = CombineStudentExecutor()
            let siblings = [combineSibling(root, prepared[0], prepared[1], 1, siblingExecutor),
                combineSibling(root, prepared[0], prepared[1], 2, siblingExecutor),
                combineSibling(root, prepared[0], prepared[1], 3, siblingExecutor)]
            let oldCalls = siblingExecutor.calls
            let executor = CombineStudentExecutor()
            let combined = combineTeacherContextCandidateSetsV2(TeacherContextCandidateCombineRequestV2(
                root, siblings, "${root}/base-context", prepared[1], combineFixtures(), executor,
                "combined-three-rules", "${root}/exports"))
            @Expect(combined.rules.count, prepared[0].rulesCount + 3)
            @Expect(combined.rules.visibleContent.contains("中文🙂"), true)
            @Expect(executor.calls, combineFixtures().size)
            @Expect(siblingExecutor.calls, oldCalls)
            for (hash in executor.hashes) { @Expect(hash, combined.rules.hash) }
            let oldExecution = teacherReadUtf8File("${siblings[0]}/rules/combine-rule-1/tests/combine-unit/execution.json")
            let newExecution = teacherReadUtf8File("${root}/exports/combined-three-rules/rules/" +
                "combine-rule-1/tests/combine-unit/execution.json")
            @Expect(newExecution == oldExecution, false)
            for (file in combined.rules.files) {
                if (file.path.endsWith("/execution.json")) {
                    @Expect(file.content.contains(executor.providerIdentityHash()), true)
                }
            }
            let parsed = parseTeacherCliOptions(["candidate-combine", "--source-export", siblings[0],
                "--source-export", siblings[1], "--source-export", siblings[2]])
            @Expect(parsed.sourceExports.size, Int64(3))
            let reloaded = parseTeacherContextCandidateSetDirectoryV2(root,
                "${root}/exports/combined-three-rules", baseContextRoot: "${root}/base-context")
            @Expect(reloaded.candidateSetHash, combined.candidateSetHash)
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

    @TestCase public func rejectsDuplicateAssetAndProtectedCombination(): Unit {
        let root = "/tmp/teacher-combine-negative-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            Directory.create(Path(root), recursive: true)
            let prepared = combinePrepare(root); let old = CombineStudentExecutor()
            let sibling = combineSibling(root, prepared[0], prepared[1], 1, old)
            let siblingCopy = "${root}/exports/sibling-copy"
            teacherCopyTree(sibling, siblingCopy)
            var duplicate = ""
            try { _ = combineTeacherContextCandidateSetsV2(TeacherContextCandidateCombineRequestV2(
                root, [sibling, siblingCopy], "${root}/base-context", prepared[1], combineFixtures(),
                CombineStudentExecutor(), "duplicate", "${root}/exports")) }
            catch (e: Exception) { duplicate = e.message }
            @Expect(duplicate, "candidate_operation_conflict")

            let mismatch = "${root}/exports/base-mismatch"
            teacherCopyTree(sibling, mismatch)
            _ = teacherAtomicWrite("${mismatch}/candidate-set-manifest.json",
                teacherReadUtf8File("${mismatch}/candidate-set-manifest.json").replace(
                    prepared[0].compositeHash,
                    "sha256:${String(Array<Rune>(64, repeat: r'b'))}"))
            var baseMismatch = ""
            try { _ = combineTeacherContextCandidateSetsV2(TeacherContextCandidateCombineRequestV2(
                root, [sibling, mismatch], "${root}/base-context", prepared[1], combineFixtures(),
                CombineStudentExecutor(), "base-mismatch", "${root}/exports")) }
            catch (e: Exception) { baseMismatch = e.message }
            @Expect(baseMismatch, "candidate_base_composite_mismatch")

            Directory.create(Path("${root}/protected-leak"), recursive: true)
            _ = teacherAtomicWrite("${root}/protected-leak/leak.txt", "existing-rule Apply Rune-safe boundary policy 1")
            let leakClosure = loadTeacherContextSourceClosure(root, "${root}/source-root",
                "${root}/protected-leak")
            var leak = ""
            try { _ = combineTeacherContextCandidateSetsV2(TeacherContextCandidateCombineRequestV2(
                root, [sibling, combineSibling(root, prepared[0], prepared[1], 2, old)],
                "${root}/base-context", leakClosure, combineFixtures(), CombineStudentExecutor(),
                "protected-leak", "${root}/exports")) }
            catch (e: Exception) { leak = e.message }
            @Expect(leak, "protected_asset_combination")
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }
}
