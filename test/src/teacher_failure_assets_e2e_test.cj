package cangjie_teacher_test

import std.unittest.testmacro.*
import std.collection.*
import std.fs.*
import std.time.*
import cangjie_teacher.*

private let S5_FIXTURE = "fixtures/failure_assets_e2e/scaffold-delta"
private let S5_BASE = "fixtures/failure_assets_e2e/base-context"
private let S5_FAILURE_HASH = "77271cefb38180b274bc6e41f8a5e9feddc035db05c30947dffbd544d2cd4319"

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

@Test
public class TeacherFailureAssetsE2ETest {
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
