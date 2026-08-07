package cangjie_teacher_test

import std.unittest.testmacro.*
import std.fs.*
import std.time.*
import cangjie_teacher.*

@Test
public class TeacherFailureAssetOrchestratorTest {
    @TestCase public func candidateSetV2GoldenTreeBindsInventoryAndApproval(): Unit {
        let fixtureRoot = "fixtures/student_context_candidate_v2"
        let candidateRoot = "${fixtureRoot}/candidate-set-v2"
        let candidate = parseTeacherContextCandidateSetDirectoryV2(candidateRoot)
        @Expect(candidate.candidateSetHash,
            "sha256:93f007c7b27d288a7999b79aed876832a6df4e9fc3ec57df7b9f4ead4816a213")
        @Expect(candidate.assetInventoryHash,
            "sha256:32c55bf2fadaca204c1a889460371d32db93b85c1da2bc43cf5e790b0151f044")
        @Expect(candidate.rules.treeHash,
            "sha256:00f8456795b3739b4623a85dd223ec31e32dd1094cd74fe99acb68a6100d7f1c")
        @Expect(candidate.skills.treeHash,
            "sha256:dabc128b1f21889c7a9d48661caefd3b148b248533e4a8e4b55fd840c3ee5bd9")
        @Expect(candidate.knowledge.treeHash,
            "sha256:2a307aa2890878a1cb99f84af3cc95e992adcc882040c1773b598d5cda08d09a")
        @Expect(renderTeacherContextCandidateSetManifestV2(candidate),
            teacherReadUtf8File("${candidateRoot}/candidate-set-manifest.json").trimAscii())
        let approval = teacherReadUtf8File("${fixtureRoot}/approval-v2.json").trimAscii()
        @Expect(validateTeacherContextApprovalV2(approval, candidate), "approve")
        @Expect(teacherStableHash(teacherReadUtf8File("${fixtureRoot}/SHA256SUMS")),
            "085adc27c2686b5fc286f9a6600ad215ca49cf18500594e46af8534d0ab549ca")

        let root = "/tmp/teacher-context-v2-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            Directory.create(Path("${root}/exports"), recursive: true)
            @Expect(exportTeacherContextCandidateSetV2(candidate, root, "${root}/exports"),
                renderTeacherContextCandidateSetManifestV2(candidate))
            let exported = "${root}/exports/${candidate.candidateSetId}"
            @Expect(parseTeacherContextCandidateSetDirectoryV2(exported).candidateSetHash,
                candidate.candidateSetHash)
            @Expect(exportTeacherContextCandidateSetV2(candidate, root, "${root}/exports"),
                renderTeacherContextCandidateSetManifestV2(candidate))

            let tampered = "${root}/tampered"
            teacherCopyTree(candidateRoot, tampered)
            _ = teacherAtomicWrite("${tampered}/skills/rune-safe-review/SKILL.md", "tampered\n")
            var tamperDiagnostic = ""
            try { _ = parseTeacherContextCandidateSetDirectoryV2(tampered) }
            catch (e: Exception) { tamperDiagnostic = e.message }
            @Expect(tamperDiagnostic, "candidate_lane_hash_mismatch")

            let symlinked = "${root}/symlinked"
            teacherCopyTree(candidateRoot, symlinked)
            remove(Path("${symlinked}/knowledge/knowledge-candidate-reference.json"))
            SymbolicLink.create(Path("${symlinked}/knowledge/knowledge-candidate-reference.json"),
                to: Path("${candidateRoot}/knowledge/knowledge-candidate-reference.json"))
            var symlinkDiagnostic = ""
            try { _ = parseTeacherContextCandidateSetDirectoryV2(symlinked) }
            catch (e: Exception) { symlinkDiagnostic = e.message }
            @Expect(symlinkDiagnostic, "candidate_set_schema_invalid")

            var approvalDiagnostic = ""
            try { _ = validateTeacherContextApprovalV2(approval.replace(
                candidate.assetInventoryHash, "sha256:${String(Array<Rune>(64, repeat: r'0'))}"), candidate) }
            catch (e: Exception) { approvalDiagnostic = e.message }
            @Expect(approvalDiagnostic, "candidate_approval_hash_mismatch")
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

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
