package cangjie_teacher_test

import std.unittest.testmacro.*
import std.collection.*
import std.fs.*
import std.time.*
import cangjie_teacher.*

private let S5_FIXTURE = "fixtures/failure_assets_e2e/scaffold-delta"
private let S5_ALL_FIXTURE = "fixtures/failure_assets_e2e/scaffold-all-assets"
private let S5_BASE = "fixtures/failure_assets_e2e/base-context"
private let S5_FAILURE_HASH = "77271cefb38180b274bc6e41f8a5e9feddc035db05c30947dffbd544d2cd4319"
private let S5_ALL_FAILURE_HASH = "dff82ac343306bb5609bb20bb9458315c8e5297f649f892cad7f96cdad470940"

private func s5BuildArgs(root: String, scaffold!: Bool = true,
    fixtureHash!: String = ""): Array<String> {
    let fixture = "${root}/fixture"
    let out = ArrayList<String>(); out.add("failure-assets-build")
    if (scaffold) { out.add("--scaffold-contract") }
    for (value in ["--allowed-root", root, "--scaffold-fixture-root", fixture,
        "--fixture-root-hash", if (fixtureHash.isEmpty()) { teacherDirectoryHash(fixture) } else { fixtureHash },
        "--failure", "${fixture}/completion-failure.json", "--expected-hash", S5_FAILURE_HASH,
        "--source-root", "${fixture}/source-root", "--protected-root", "${fixture}/protected-root",
        "--base-context-root", "${root}/base-context", "--run-id", "synthetic-cli-delta-v2",
        "--output-root", "${root}/exports"]) { out.add(value) }
    out.toArray()
}

private func s5Prepare(root: String): Unit {
    Directory.create(Path(root), recursive: true)
    teacherCopyTree(S5_FIXTURE, "${root}/fixture")
    teacherCopyTree(S5_BASE, "${root}/base-context")
    Directory.create(Path("${root}/exports"), recursive: true)
    Directory.create(Path("${root}/review"), recursive: true)
}

private func s5PrepareAll(root: String): Unit {
    Directory.create(Path(root), recursive: true)
    teacherCopyTree(S5_ALL_FIXTURE, "${root}/fixture")
    teacherCopyTree(S5_BASE, "${root}/base-context")
    Directory.create(Path("${root}/exports"), recursive: true)
    Directory.create(Path("${root}/review"), recursive: true)
}

private func s5PrepareGenesis(root: String): Unit {
    s5PrepareAll(root)
    remove(Path("${root}/fixture/source-root"), recursive: true)
    remove(Path("${root}/fixture/protected-root"), recursive: true)
    Directory.create(Path("${root}/fixture/source-root/sources"), recursive: true)
    Directory.create(Path("${root}/fixture/protected-root"), recursive: true)
    let sources = [("official-rune.md", "official-source.md"),
        ("community-rune.md", "community-source.md"),
        ("non-humaneval-rune.txt", "non-humaneval-source.txt")]
    let hashes = ArrayList<String>()
    for (source in sources) {
        let raw = teacherReadUtf8File("${root}/fixture/${source[1]}").trimAscii()
        hashes.add("sha256:${teacherStableHash(raw)}")
        _ = teacherAtomicWrite("${root}/fixture/source-root/sources/${source[0]}", raw)
    }
    let manifest = buildTeacherContextSourceManifest("independent_sources", hashes.toArray())
    _ = teacherAtomicWrite("${root}/fixture/source-root/source-manifest.json",
        renderTeacherContextSourceManifest(manifest) + "\n")
    _ = teacherAtomicWrite("${root}/fixture/protected-root/opaque-sentinel.txt",
        "quartz zebra sentinel 78291\n")
    let reference = teacherReadUtf8File("${root}/fixture/knowledge-reference.json")
        .replace("\"assetLineage\":\"humaneval_164_derived\"",
            "\"assetLineage\":\"independent\"")
    _ = teacherAtomicWrite("${root}/fixture/knowledge-reference.json", reference)
}

private func s5GenesisArgs(root: String, scaffold!: Bool = true): Array<String> {
    let out = ArrayList<String>(); out.add("context-seed-build")
    if (scaffold) { out.add("--scaffold-contract") }
    for (value in ["--allowed-root", root, "--scaffold-fixture-root", "${root}/fixture",
        "--fixture-root-hash", teacherDirectoryHash("${root}/fixture"),
        "--source-root", "${root}/fixture/source-root", "--protected-root",
        "${root}/fixture/protected-root", "--run-id", "synthetic-cli-genesis-v2",
        "--output-root", "${root}/exports"]) { out.add(value) }
    out.toArray()
}

private func s5AllBuildArgs(root: String, runId!: String = "synthetic-cli-all-assets-v2"):
    Array<String> {
    let fixture = "${root}/fixture"
    ["failure-assets-build", "--scaffold-contract", "--allowed-root", root,
        "--scaffold-fixture-root", fixture, "--fixture-root-hash", teacherDirectoryHash(fixture),
        "--failure", "${fixture}/completion-failure.json", "--expected-hash", S5_ALL_FAILURE_HASH,
        "--source-root", "${fixture}/source-root", "--protected-root", "${fixture}/protected-root",
        "--base-context-root", "${root}/base-context", "--run-id", runId,
        "--output-root", "${root}/exports"]
}

@Test
public class TeacherFailureAssetsE2ETest {
    // S5 gap matrix:
    // POS/E2E-03: canonical CLI input -> three builders -> fixture executor/knowledge adapter ->
    // combination audit -> atomic immutable export -> independent approval.
    // BND: source/protected/base/fixture roots and approval hashes remain independently bound.
    // NEG: classification disagreement and incomplete evidence fail before publishing a candidate.
    // S5-UT remains in the focused unit suites and is intentionally not duplicated here.
    @TestCase public func allAssetCliBuildIsAtomicImmutableAndIndependentlyApproved(): Unit {
        let root = "/tmp/teacher-assets-all-e2e-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            s5PrepareAll(root)
            // S5-POS / E2E-03: every production input comes from the canonical fixture root.
            @Expect(teacherReadUtf8File("${root}/fixture/completion-failure.json").contains(
                "Synthetic program returned an incorrect result. 中文🙂"), true)
            @Expect(teacherReadUtf8File("${root}/fixture/knowledge-atom.json").contains(
                "\"sourceClass\":\"official\""), true)
            @Expect(exists(Path("${root}/fixture/community-source.md")), true)
            @Expect(exists(Path("${root}/fixture/non-humaneval-source.txt")), true)
            @Expect(cangjieTeacherCliMain(s5AllBuildArgs(root)), Int64(0))
            let candidateRoot = "${root}/exports/synthetic-cli-all-assets-v2"
            let candidate = parseTeacherContextCandidateSetDirectoryV2(root, candidateRoot,
                baseContextRoot: "${root}/base-context")
            @Expect(candidate.rules.eligible, true)
            @Expect(candidate.skills.eligible, true)
            @Expect(candidate.knowledge.eligible, true)
            @Expect(candidate.rules.lineage, "humaneval_164_derived")
            @Expect(candidate.skills.lineage, "humaneval_164_derived")
            @Expect(candidate.knowledge.lineage, "humaneval_164_derived")
            @Expect(exists(Path("${candidateRoot}/audit/source-closure.json")), true)
            @Expect(exists(Path("${candidateRoot}/audit/protected-closure.json")), true)
            let immutableHash = teacherDirectoryHash(candidateRoot)
            @Expect(cangjieTeacherCliMain(s5AllBuildArgs(root)), Int64(0))
            @Expect(teacherDirectoryHash(candidateRoot), immutableHash)

            let driftProtected = "${root}/protected-drift"
            teacherCopyTree("${root}/fixture/protected-root", driftProtected)
            _ = teacherAtomicWrite("${driftProtected}/independent-drift.txt", "boundary drift\n")
            let rejectedApproval = "${root}/review/rejected-drift.json"
            @Expect(cangjieTeacherCliMain(["failure-assets-approve", "--allowed-root", root,
                "--source-export", candidateRoot, "--source-root", "${root}/fixture/source-root",
                "--protected-root", driftProtected, "--base-context-root", "${root}/base-context",
                "--candidate-set-hash", candidate.candidateSetHash, "--decision", "approve",
                "--reviewer", "synthetic-independent-reviewer", "--reason",
                "Drifted protected root must fail.", "--approved-at-utc", "2026-08-07T00:00:00Z",
                "--output", rejectedApproval]), Int64(1))
            @Expect(exists(Path(rejectedApproval)), false)

            let approvalPath = "${root}/review/all-assets-approval-v2.json"
            @Expect(cangjieTeacherCliMain(["failure-assets-approve", "--allowed-root", root,
                "--source-export", candidateRoot, "--source-root", "${root}/fixture/source-root",
                "--protected-root", "${root}/fixture/protected-root", "--base-context-root",
                "${root}/base-context", "--candidate-set-hash", candidate.candidateSetHash,
                "--decision", "approve", "--reviewer", "synthetic-independent-reviewer",
                "--reason", "Verified three-lane synthetic boundaries.", "--approved-at-utc",
                "2026-08-07T00:00:00Z", "--output", approvalPath]), Int64(0))
            @Expect(validateTeacherContextApprovalV2(
                teacherReadUtf8File(approvalPath).trimAscii(), candidate), "approve")
            // S5-BND: approval is a separate immutable act.
            @Expect(cangjieTeacherCliMain(["failure-assets-approve", "--allowed-root", root,
                "--source-export", candidateRoot, "--source-root", "${root}/fixture/source-root",
                "--protected-root", "${root}/fixture/protected-root", "--base-context-root",
                "${root}/base-context", "--candidate-set-hash", candidate.candidateSetHash,
                "--decision", "approve", "--reviewer", "synthetic-independent-reviewer",
                "--reason", "Duplicate approval must fail.", "--approved-at-utc",
                "2026-08-07T00:00:00Z", "--output", approvalPath]), Int64(1))
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

    @TestCase public func independentGenesisCliExportsAndApprovesV2Contract(): Unit {
        let root = "/tmp/teacher-assets-genesis-e2e-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            s5PrepareGenesis(root)
            @Expect(cangjieTeacherCliMain(s5GenesisArgs(root, scaffold: false)), Int64(1))
            @Expect(exists(Path("${root}/exports/synthetic-cli-genesis-v2")), false)
            @Expect(cangjieTeacherCliMain(s5GenesisArgs(root)), Int64(0))
            let candidateRoot = "${root}/exports/synthetic-cli-genesis-v2"
            let candidate = parseTeacherContextCandidateSetDirectoryV2(root, candidateRoot)
            @Expect(candidate.baseCompositeHash, "none")
            @Expect(candidate.rules.lineage, "independent")
            @Expect(candidate.skills.lineage, "independent")
            @Expect(candidate.knowledge.lineage, "independent")
            let approval = "${root}/review/genesis-approval-v2.json"
            @Expect(cangjieTeacherCliMain(["failure-assets-approve", "--allowed-root", root,
                "--source-export", candidateRoot, "--source-root", "${root}/fixture/source-root",
                "--protected-root", "${root}/fixture/protected-root", "--base-context-root", "none",
                "--candidate-set-hash", candidate.candidateSetHash, "--decision", "approve",
                "--reviewer", "synthetic-genesis-reviewer", "--reason",
                "Verified independent synthetic genesis.", "--approved-at-utc",
                "2026-08-07T00:00:00Z", "--output", approval]), Int64(0))
            @Expect(validateTeacherContextApprovalV2(
                teacherReadUtf8File(approval).trimAscii(), candidate), "approve")
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

    @TestCase public func allAssetCliFailsClosedBeforeAtomicPublish(): Unit {
        let root = "/tmp/teacher-assets-all-negative-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            s5PrepareAll(root)
            let second = "${root}/fixture/classification-b.json"
            _ = teacherAtomicWrite(second, teacherReadUtf8File(second).replace(
                "\"gapKind\":\"all_assets_gap\"", "\"gapKind\":\"rules_gap\""))
            @Expect(cangjieTeacherCliMain(s5AllBuildArgs(root)), Int64(1))
            @Expect(exists(Path("${root}/exports/synthetic-cli-all-assets-v2")), false)

            remove(Path("${root}/fixture"), recursive: true)
            teacherCopyTree(S5_ALL_FIXTURE, "${root}/fixture")
            remove(Path("${root}/fixture/fixtures/rule-negative"), recursive: true)
            @Expect(cangjieTeacherCliMain(s5AllBuildArgs(root)), Int64(1))
            @Expect(exists(Path("${root}/exports/synthetic-cli-all-assets-v2")), false)

            remove(Path("${root}/fixture"), recursive: true)
            teacherCopyTree(S5_ALL_FIXTURE, "${root}/fixture")
            _ = teacherAtomicWrite("${root}/fixture/source-root/sources/completion-failure.json",
                "drifted source evidence\n")
            @Expect(cangjieTeacherCliMain(s5AllBuildArgs(root)), Int64(1))
            @Expect(exists(Path("${root}/exports/synthetic-cli-all-assets-v2")), false)
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

    @TestCase public func scaffoldBuildApproveAndReexportUseV2ActualRoots(): Unit {
        let root = "/tmp/teacher-assets-e2e-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            s5Prepare(root)
            let buildExit = cangjieTeacherCliMain(s5BuildArgs(root))
            @Expect(buildExit, Int64(0))
            if (buildExit != 0) { return }
            let candidateRoot = "${root}/exports/synthetic-cli-delta-v2"
            @Expect(exists(Path(candidateRoot)), true)
            let candidate = parseTeacherContextCandidateSetDirectoryV2(root, candidateRoot,
                baseContextRoot: "${root}/base-context")
            @Expect(candidate.validationLevel, "scaffold_contract")
            @Expect(candidate.rules.eligible, true)
            @Expect(candidate.rules.count, Int64(2))
            @Expect(candidate.skills.eligible, false)
            @Expect(candidate.skills.files.isEmpty(), true)
            @Expect(candidate.knowledge.eligible, false)
            @Expect(candidate.knowledge.files.isEmpty(), true)
            let approvalPath = "${root}/review/approval-v2.json"
            @Expect(cangjieTeacherCliMain(["failure-assets-approve", "--allowed-root", root,
                "--source-export", candidateRoot, "--source-root", "${root}/fixture/source-root",
                "--protected-root", "${root}/fixture/protected-root", "--base-context-root",
                "${root}/base-context", "--candidate-set-hash", candidate.candidateSetHash,
                "--decision", "approve", "--reviewer", "synthetic-reviewer",
                "--reason", "Verified v2 actual roots.", "--approved-at-utc",
                "2026-08-07T00:00:00Z", "--output", approvalPath]), Int64(0))
            @Expect(teacherReadUtf8File(approvalPath).contains(
                "\"schemaVersion\":\"teacher-student-context-approval-v2\""), true)
            Directory.create(Path("${root}/reexport"), recursive: true)
            @Expect(cangjieTeacherCliMain(["failure-assets-reexport", "--scaffold-contract",
                "--allowed-root", root, "--source-export", candidateRoot,
                "--base-context-root", "${root}/base-context", "--output-root",
                "${root}/reexport"]), Int64(0))
            @Expect(teacherDirectoryHash("${root}/reexport/synthetic-cli-delta-v2"),
                teacherDirectoryHash(candidateRoot))
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

    @TestCase public func scaffoldCliFailsClosedOnMissingContractAndRootDrift(): Unit {
        let root = "/tmp/teacher-assets-e2e-negative-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            s5Prepare(root)
            @Expect(cangjieTeacherCliMain(s5BuildArgs(root, scaffold: false)), Int64(1))
            @Expect(exists(Path("${root}/exports/synthetic-cli-delta-v2")), false)
            @Expect(cangjieTeacherCliMain(s5BuildArgs(root,
                fixtureHash: "sha256:${String(Array<Rune>(64, repeat: r'0'))}")), Int64(1))
            @Expect(exists(Path("${root}/exports/synthetic-cli-delta-v2")), false)
            _ = teacherAtomicWrite("${root}/base-context/student-context-manifest.json",
                teacherReadUtf8File("${root}/base-context/student-context-manifest.json") + "\n")
            @Expect(cangjieTeacherCliMain(s5BuildArgs(root)), Int64(1))
            @Expect(exists(Path("${root}/exports/synthetic-cli-delta-v2")), false)
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }
}
