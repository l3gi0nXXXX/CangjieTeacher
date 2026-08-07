package cangjie_teacher_test

import std.unittest.testmacro.*
import std.fs.*
import std.time.*
import cangjie_teacher.*

@Test
public class TeacherFailureAssetOrchestratorTest {
    @TestCase public func failureKnowledgeUsesAtomAdapterWithoutLegacySchemaCoercion(): Unit {
        let internal = s2InternalClassification("knowledge_gap", true, false, false, "missing_versioned_fact")
        let shared = reconcileTeacherFailureAssetClassifications(internal, internal)
        let rejected = buildTeacherKnowledgeCandidateFromFailureAsset(shared,
            "{\"schemaVersion\":\"ckb-benchmark-gap-v1\"}", "/tmp/not-used")
        @Expect(rejected.ok, false)
        @Expect(rejected.diagnostic, "failure_knowledge_adapter_invalid")
        let delegated = buildTeacherKnowledgeCandidateFromFailureAsset(shared, "{malformed-atom-bundle",
            "/tmp/not-used")
        @Expect(delegated.ok, false)
        @Expect(delegated.diagnostic == "failure_knowledge_adapter_invalid", false)
    }

    @TestCase public func failureAssetsRouteSealApproveOrFailClosed(): Unit {
        let failure = parseTeacherCompletionFailureInput(teacherReadUtf8File(
            "fixtures/completion_failure_assets/completion-failure-v1-utf8.json").trimAscii())
        let internal = s2InternalClassification("all_assets_gap", true, true, true, "multiple_reusable_gaps")
        let built = buildTeacherFailureAssets(failure, internal, internal,
            "Reusable Unicode boundary gap 中文🙂", S2Generator())
        @Expect(built.proposals.size, 3)
        @Expect(built.classification.failureEvidenceHash, failure.evidenceHash)

        let source = buildTeacherContextSourceManifest("independent_sources", [
            "sha256:${teacherStableHash("official Cangjie Rune docs")}",
            "sha256:${teacherStableHash("non-HumanEval Unicode fixtures")}" ])
        @Expect(parseTeacherContextSourceManifest(renderTeacherContextSourceManifest(source)).sourceManifestHash,
            source.sourceManifestHash)
        let seed = buildTeacherIndependentContextSeed(source, "synthetic-seed-v1",
            "# Rules\n\nPreserve complete Rune boundaries.\n",
            "# Skill\n\nInspect text, select a Rune boundary, then verify the rendered byte budget.\n",
            "{\"schemaVersion\":\"ckb-frozen-knowledge-reference-v1\",\"knowledge\":\"Rune boundary facts\"}\n",
            "cangjie-1.0.0-synthetic")
        @Expect(seed.rules.lineage, "independent")
        @Expect(seed.skills.lineage, "independent")
        @Expect(seed.knowledge.lineage, "independent")
        let root = "/tmp/teacher-context-s2-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            let manifest = exportTeacherContextCandidateSet(seed, root)
            let candidateRoot = "${root}/${seed.candidateSetId}"
            let before = teacherDirectoryHash(candidateRoot)
            @Expect(exportTeacherContextCandidateSet(seed, root), manifest)
            let approvalPath = "${root}/review/${seed.candidateSetId}.approval.json"
            @Expect(cangjieTeacherCliMain(["failure-assets-approve", "--source-export", candidateRoot,
                "--candidate-set-hash", seed.candidateSetHash, "--decision", "approve",
                "--reviewer", "synthetic-reviewer", "--reason", "Synthetic scaffold fixtures passed.",
                "--approved-at-utc", "2026-08-07T00:00:00Z", "--output", approvalPath]), Int64(0))
            @Expect(teacherReadUtf8File(approvalPath).contains("\"decision\":\"approve\""), true)
            @Expect(teacherDirectoryHash(candidateRoot), before)
            @Expect(exists(Path("${candidateRoot}/rules")), true)
            @Expect(exists(Path("${candidateRoot}/skills")), true)
            @Expect(exists(Path("${candidateRoot}/knowledge/knowledge-candidate-reference.json")), true)
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }

        var leakRejected = ""
        try { _ = buildTeacherIndependentContextSeed(source, "bad-seed",
            "safe rule prefix", "safe skill middle", "protected suffix", "v1",
            protectedArtifacts: ["prefix safe skill middle protected"]) }
        catch (e: Exception) { leakRejected = e.message }
        @Expect(leakRejected, "protected_asset_combination")

        var disagreement = ""
        try { _ = buildTeacherFailureAssets(failure, internal,
            s2InternalClassification("rules_gap", false, false, true, "missing_global_invariant"),
            "safe gap", S2Generator()) }
        catch (e: Exception) { disagreement = e.message }
        @Expect(disagreement, "classification_requires_review")

        let parsedCli = parseTeacherCliOptions(["failure-assets-build", "--failure", "failure.json",
            "--expected-hash", "abc", "--base-context-manifest", "none", "--output-root", "out"])
        @Expect(parsedCli.failurePath, "failure.json")
        @Expect(parsedCli.baseContextManifest, "none")
    }
}
