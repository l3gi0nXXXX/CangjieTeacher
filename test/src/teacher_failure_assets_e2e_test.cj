package cangjie_teacher_test

import std.unittest.testmacro.*
import std.collection.*
import std.fs.*
import std.time.*
import cangjie_teacher.*

private let S5_FIXTURE_ROOT = "fixtures/failure_assets_e2e"

private func s5SourceManifest(): TeacherContextSourceManifest {
    buildTeacherContextSourceManifest("independent_sources", [
        "sha256:${teacherStableHash(teacherReadUtf8File("${S5_FIXTURE_ROOT}/official-source.md"))}",
        "sha256:${teacherStableHash(teacherReadUtf8File("${S5_FIXTURE_ROOT}/community-source.md"))}"
    ])
}

private func s5Seed(): TeacherContextCandidateSet {
    buildTeacherIndependentContextSeed(s5SourceManifest(), "synthetic-e2e-seed-v1",
        teacherReadUtf8File("${S5_FIXTURE_ROOT}/AGENTS.md"),
        teacherReadUtf8File("${S5_FIXTURE_ROOT}/SKILL.md"),
        teacherReadUtf8File("${S5_FIXTURE_ROOT}/knowledge-reference.json"),
        "cangjie-1.0.0-synthetic")
}

private func s5SyntheticFailure(): TeacherCompletionFailureInput {
    TeacherCompletionFailureInput("synthetic-e2e-run", "SYNTHETIC-RUNE-CASE", "synthetic-non-humaneval-v1",
        "completion-only-v1", String(Array<Rune>(64, repeat: r'a')), "failed", "failed", "test_failure",
        "Unicode boundary contract failed on a synthetic fixture.", "humaneval_164_derived",
        "f08453591302a46c4acc04c43d9bdf456679fae27b354bbca7ebecb194c1e773")
}

private class S5FakeCompletion {
    public var completionCount: Int64 = 0
    public var providerCount: Int64 = 0
    public func complete(prompt: String): String {
        providerCount += 1; completionCount += 1
        if (!prompt.contains("complete Rune boundary") || !prompt.contains("String.toRuneArray")) {
            throw IllegalArgumentException("completion_context_evidence_mismatch")
        }
        "func renderLabel(value: String): String { value }"
    }
}

@Test
public class TeacherFailureAssetsE2ETest {
    @TestCase public func syntheticFailureAssetsExportPass(): Unit {
        let seed = s5Seed()
        let root = "/tmp/teacher-assets-e2e-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            let manifest = exportTeacherContextCandidateSet(seed, root)
            let candidateRoot = "${root}/${seed.candidateSetId}"
            let firstHash = teacherDirectoryHash(candidateRoot)
            @Expect(exportTeacherContextCandidateSet(seed, root), manifest)
            @Expect(teacherDirectoryHash(candidateRoot), firstHash)
            @Expect(seed.validationLevel, "scaffold_contract")
            let approvalPath = "${root}/review/${seed.candidateSetId}.approval.json"
            @Expect(cangjieTeacherCliMain(["failure-assets-approve", "--source-export", candidateRoot,
                "--candidate-set-hash", seed.candidateSetHash, "--decision", "approve",
                "--reviewer", "synthetic-e2e-reviewer", "--reason", "Synthetic non-HumanEval fixtures passed.",
                "--approved-at-utc", "2026-08-07T00:00:00Z", "--output", approvalPath]), Int64(0))
            @Expect(teacherDirectoryHash(candidateRoot), firstHash)
            @Expect(exists(Path(approvalPath)), true)

            let internal = s2InternalClassification("all_assets_gap", true, true, true,
                "multiple_reusable_gaps")
            let delta = buildTeacherFailureAssets(s5SyntheticFailure(), internal, internal,
                "Synthetic Unicode rendering gap", S2Generator())
            @Expect(delta.proposals.size, 3)
            @Expect(delta.classification.schemaVersion, "ckb-completion-failure-classification-v2")
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

    @TestCase public func syntheticFailureAssetsBoundaryIsolationPass(): Unit {
        let seed = s5Seed()
        @Expect(seed.rules.content.contains("Rune"), true)
        @Expect(seed.skills.content.contains("UTF-8"), true)
        @Expect(seed.knowledge.content.contains("toRuneArray"), true)
        let oversized = String(Array<Rune>(4097, repeat: r'界'))
        let internal = s2InternalClassification("rules_gap", false, false, true, "missing_global_invariant")
        let shared = reconcileTeacherFailureAssetClassifications(internal, internal)
        var oversizeRejected = ""
        try { _ = buildTeacherRuleCandidate(shared, "oversize-rule", "oversize-concept", "Oversize",
            oversized, "Unicode rendering", "Cangjie rendering", 1, "completion_failure",
            shared.failureEvidenceHash,
            TeacherRuleTestBundle(executeTeacherAssetFixtureBundle(s2Fixtures(), FakeTeacherAssetFixtureExecutor()))) }
        catch (e: Exception) { oversizeRejected = e.message }
        @Expect(oversizeRejected, "candidate_test_evidence_invalid")

        let invalid = teacherReadUtf8File("fixtures/completion_failure_assets/classification-invalid-utf8.hex")
        @Expect(invalid.trimAscii(), "fffe")
        var invalidEncoding = ""
        try { _ = String.fromUtf8([UInt8(0xff), UInt8(0xfe)]) }
        catch (_: Exception) { invalidEncoding = "invalid_response_encoding" }
        @Expect(invalidEncoding, "invalid_response_encoding")
    }

    @TestCase public func syntheticFailureAssetsProduceSingleFrozenCompletion(): Unit {
        let seed = s5Seed()
        let prompt = "Protocol: completion only.\n${seed.rules.content}\n${seed.skills.content}\n" +
            "${seed.knowledge.content}\nPublic task: render a generic label."
        @Expect(prompt.contains("candidateSetHash"), false)
        @Expect(prompt.contains("approval"), false)
        @Expect(prompt.contains("SYNTHETIC-RUNE-CASE"), false)
        let fake = S5FakeCompletion()
        let answer = fake.complete(prompt)
        let answerHash = teacherStableHash(answer)
        let basePassed = answer.contains("func renderLabel")
        let plusPassed = answer.contains("value: String")
        @Expect(basePassed && plusPassed, true)
        @Expect(teacherStableHash(answer), answerHash)
        @Expect(fake.completionCount, Int64(1))
        @Expect(fake.providerCount, Int64(1))
    }

    @TestCase public func syntheticFailureAssetsFailClosedAtEveryBoundary(): Unit {
        let internal = s2InternalClassification("all_assets_gap", true, true, true,
            "multiple_reusable_gaps")
        var classifierBlocked = ""
        try { _ = buildTeacherFailureAssets(s5SyntheticFailure(), internal,
            s2InternalClassification("none", false, false, false, "no_reusable_gap"),
            "safe gap", S2Generator()) }
        catch (e: Exception) { classifierBlocked = e.message }
        @Expect(classifierBlocked, "classification_requires_review")

        var combinationBlocked = ""
        try { _ = buildTeacherIndependentContextSeed(s5SourceManifest(), "leaking-e2e",
            "first protected segment", "middle protected segment", "last protected segment", "v1",
            protectedArtifacts: ["first protected segment middle protected segment last protected segment"]) }
        catch (e: Exception) { combinationBlocked = e.message }
        @Expect(combinationBlocked, "protected_asset_combination")

        let root = "/tmp/teacher-assets-e2e-negative-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            let seed = s5Seed(); _ = exportTeacherContextCandidateSet(seed, root)
            let candidateRoot = "${root}/${seed.candidateSetId}"
            let before = teacherDirectoryHash(candidateRoot)
            let approvalPath = "${root}/review/invalid.approval.json"
            @Expect(cangjieTeacherCliMain(["failure-assets-approve", "--source-export", candidateRoot,
                "--candidate-set-hash", "sha256:${String(Array<Rune>(64, repeat: r'0'))}",
                "--decision", "approve", "--reviewer", "reviewer", "--reason", "reason",
                "--approved-at-utc", "2026-08-07T00:00:00Z", "--output", approvalPath]), Int64(1))
            @Expect(exists(Path(approvalPath)), false)
            @Expect(teacherDirectoryHash(candidateRoot), before)
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }
}
