package cangjie_teacher_test

import std.unittest.testmacro.*
import std.collection.*
import std.fs.*
import std.time.*
import cangjie_teacher.*

private let S5_FIXTURE_ROOT = "fixtures/failure_assets_e2e"
private let S5_SCAFFOLD_ROOT = "${S5_FIXTURE_ROOT}/scaffold-delta"
private let S5_BASE_MANIFEST = "${S5_FIXTURE_ROOT}/base-context/student-context-manifest.json"
private let S5_FAILURE_HASH = "31916209b2bdd910bb8875f9a51e43153af24315145da8a9bf9120f4976bdc8d"

private func s5ScaffoldBuildArgs(outputRoot: String, fixtureRoot!: String = S5_SCAFFOLD_ROOT,
    failurePath!: String = "${S5_FIXTURE_ROOT}/synthetic-failure.txt",
    expectedHash!: String = S5_FAILURE_HASH, baseHash!: String = "",
    baseManifest!: String = S5_BASE_MANIFEST, scaffold!: Bool = true): Array<String> {
    let actualBaseHash = if (baseHash.isEmpty()) {
        "sha256:${teacherStableHash(teacherReadUtf8File(baseManifest))}"
    } else { baseHash }
    let out = ArrayList<String>(); out.add("failure-assets-build")
    if (scaffold) { out.add("--scaffold-contract") }
    for (value in ["--fixture-root", fixtureRoot, "--failure", failurePath,
        "--expected-hash", expectedHash, "--source-manifest", "${S5_SCAFFOLD_ROOT}/source-manifest.json",
        "--base-context-manifest", baseManifest, "--base-context-hash", actualBaseHash,
        "--run-id", "synthetic-cli-delta-v1", "--output-root", outputRoot]) { out.add(value) }
    out.toArray()
}

private func s5CandidateSetHash(raw: String): String {
    let marker = "\"candidateSetHash\":\""
    let tail = raw.split(marker)
    if (tail.size != 2) { return "" }
    tail[1].split("\"")[0]
}

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

            let deltaRoot = "${root}/delta"
            @Expect(cangjieTeacherCliMain(s5ScaffoldBuildArgs(deltaRoot)), Int64(0))
            let exported = "${deltaRoot}/synthetic-cli-delta-v1"
            let exportedManifest = teacherReadUtf8File("${exported}/candidate-set-manifest.json")
            let exportedHash = s5CandidateSetHash(exportedManifest)
            @Expect(exportedManifest.contains("\"validationLevel\":\"scaffold_contract\""), true)
            @Expect(exportedManifest.contains("\"rulesEligible\":true"), true)
            @Expect(exportedManifest.contains("\"skillsEligible\":false"), true)
            @Expect(exportedManifest.contains("\"knowledgeEligible\":false"), true)
            @Expect(exists(Path("${exported}/rules/AGENTS.md")), true)
            @Expect(exists(Path("${exported}/rules/candidate-manifest.json")), true)
            @Expect(exists(Path("${exported}/skills/student-skills.prompt.md")), false)
            @Expect(exists(Path("${exported}/knowledge/knowledge-candidate-reference.json")), true)
            let deltaApproval = "${root}/review/synthetic-cli-delta-v1.approval.json"
            @Expect(cangjieTeacherCliMain(["failure-assets-approve", "--source-export", exported,
                "--candidate-set-hash", exportedHash, "--decision", "approve",
                "--reviewer", "synthetic-e2e-reviewer", "--reason", "Synthetic scaffold contract passed.",
                "--approved-at-utc", "2026-08-07T00:00:00Z", "--output", deltaApproval]), Int64(0))
            @Expect(exists(Path(deltaApproval)), true)
            let human = renderTeacherFailureAssetsBuildOutput("synthetic-cli-delta-v1", exportedHash, false)
            @Expect(human.contains("\"ok\""), false)
            @Expect(human.contains("\"result\""), false)
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

            let scaffoldOutput = "${root}/scaffold-negative"
            @Expect(cangjieTeacherCliMain(s5ScaffoldBuildArgs(scaffoldOutput,
                scaffold: false)), Int64(1))
            @Expect(exists(Path(scaffoldOutput)), false)

            let markerFailure = "${root}/real-marker.txt"
            _ = teacherAtomicWrite(markerFailure, "CJ-HUMANEVAL-REAL protected marker\n")
            let markerHash = teacherStableHash(teacherReadUtf8File(markerFailure))
            @Expect(cangjieTeacherCliMain(s5ScaffoldBuildArgs(scaffoldOutput,
                failurePath: markerFailure, expectedHash: markerHash)), Int64(1))
            @Expect(exists(Path(scaffoldOutput)), false)

            @Expect(cangjieTeacherCliMain(s5ScaffoldBuildArgs(scaffoldOutput,
                expectedHash: String(Array<Rune>(64, repeat: r'0')))), Int64(1))
            @Expect(exists(Path(scaffoldOutput)), false)

            @Expect(cangjieTeacherCliMain(s5ScaffoldBuildArgs(scaffoldOutput,
                baseHash: "sha256:${String(Array<Rune>(64, repeat: r'0'))}")), Int64(1))
            @Expect(exists(Path(scaffoldOutput)), false)

            let driftedBaseRoot = "${root}/drifted-base"
            teacherCopyTree("${S5_FIXTURE_ROOT}/base-context", driftedBaseRoot)
            let driftedBase = "${driftedBaseRoot}/student-context-manifest.json"
            _ = teacherAtomicWrite(driftedBase, teacherReadUtf8File(driftedBase) + "\n")
            @Expect(cangjieTeacherCliMain(s5ScaffoldBuildArgs(scaffoldOutput,
                baseManifest: driftedBase,
                baseHash: "sha256:${teacherStableHash(teacherReadUtf8File(S5_BASE_MANIFEST))}")), Int64(1))
            @Expect(exists(Path(scaffoldOutput)), false)

            let incompleteFixtures = "${root}/incomplete-fixtures"
            teacherCopyTree(S5_SCAFFOLD_ROOT, incompleteFixtures)
            remove(Path("${incompleteFixtures}/classification-b.json"))
            @Expect(cangjieTeacherCliMain(s5ScaffoldBuildArgs(scaffoldOutput,
                fixtureRoot: incompleteFixtures)), Int64(1))
            @Expect(exists(Path(scaffoldOutput)), false)
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }
}
