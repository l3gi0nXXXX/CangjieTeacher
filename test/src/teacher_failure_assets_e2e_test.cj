package cangjie_teacher_test

import std.unittest.testmacro.*
import std.collection.*
import std.fs.*
import std.posix.*
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

private func r6WriteExecutable(path: String, content: String): Unit {
    _ = teacherAtomicWrite(path, content)
    if (chmod(path, UInt32(0o700)) != 0) {
        throw IllegalArgumentException("test_fixture_invalid")
    }
}

private func r6PrepareRealFixtures(root: String): Unit {
    Directory.create(Path("${root}/real-fixtures/fixtures"), recursive: true)
    for ((id, kind, input) in [
        ("real-unit", "unit", "Preserve one complete Rune in a bounded label."),
        ("real-positive", "positive", "Render 中文🙂 safely."),
        ("real-negative", "negative", "Reject an invalid Rune split."),
        ("real-boundary", "boundary", "Accept the exact UTF-8 boundary."),
        ("real-general", "generalization", "Apply the invariant to generic labels."),
        ("real-general-log", "generalization", "Apply the invariant to log previews."),
        ("real-general-frame", "generalization", "Apply the invariant to protocol frames.")
    ]) {
        let path = "${root}/real-fixtures/fixtures/${id}"
        Directory.create(Path(path), recursive: true)
        _ = teacherAtomicWrite("${path}/fixture.json",
            "{\"schemaVersion\":\"teacher-cli-real-fixture-v1\",\"fixtureId\":\"${id}\"," +
            "\"kind\":\"${kind}\",\"sourceClass\":\"non_humaneval_experiment\"}\n")
        _ = teacherAtomicWrite("${path}/input.txt", input + "\n")
        _ = teacherAtomicWrite("${path}/expected.txt", "passed\n")
    }
}

private func r6ProviderRuntimeScript(): String {
    "#!/bin/zsh\ntools_seen=0\nsettings_seen=0\nmodel=''\nwhile (( $# > 0 )); do\n" +
        "  case \"$1\" in\n    --tools) [[ -z \"$2\" ]] || exit 21; tools_seen=1; shift 2;;\n" +
        "    --setting-sources) [[ -z \"$2\" ]] || exit 22; settings_seen=1; shift 2;;\n" +
        "    --max-turns) [[ \"$2\" == 1 ]] || exit 23; shift 2;;\n" +
        "    --model) model=\"$2\"; shift 2;;\n" +
        "    --session-id|--mcp-config|--json-schema|--output-format) shift 2;;\n" +
        "    -p|--bare|--disable-slash-commands|--verbose|--no-session-persistence|" +
        "--strict-mcp-config|--dangerously-skip-permissions) shift;;\n" +
        "    *) exit 24;;\n  esac\ndone\n" +
        "(( tools_seen == 1 && settings_seen == 1 )) || exit 25\n" +
        "prompt=$(<&0)\n[[ \"$prompt\" == *candidateVisibleProjection* ]] || exit 26\n" +
        "[[ \"$prompt\" != *expectedEvidence* && \"$prompt\" != *'\\\"passed\\\"'* ]] || exit 27\n" +
        "print -r -- \"{\\\"type\\\":\\\"result\\\",\\\"subtype\\\":\\\"success\\\"," +
        "\\\"is_error\\\":false,\\\"modelUsage\\\":{\\\"${"$"}{model}\\\":{}}," +
        "\\\"structured_output\\\":{\\\"solution_cj\\\":\\\"passed\\\"}}\"\n"
}

private func r6FixedAdapterScript(response: String): String {
    "#!/bin/zsh\noutput=''\nwhile (( $# > 0 )); do\n  case \"$1\" in\n" +
        "    --request) request=\"$2\"; shift 2;;\n    --output) output=\"$2\"; shift 2;;\n" +
        "    *) exit 31;;\n  esac\ndone\n[[ -f \"$request\" ]] || exit 32\n" +
        "print -r -- '${response}' > \"$output\"\n"
}

private func r6RulesOnlyClassification(): String {
    let evidence = "{\"schemaVersion\":\"teacher-failure-asset-classification-v2\"," +
        "\"failureEvidenceHash\":\"${S5_ALL_FAILURE_HASH}\",\"gapKind\":\"rules_gap\"," +
        "\"knowledgeEligible\":false,\"skillEligible\":false,\"rulesEligible\":true," +
        "\"classificationReasonCode\":\"missing_global_invariant\"}"
    renderTeacherFailureAssetClassifierResponse(TeacherFailureAssetClassification(
        "teacher-failure-asset-classification-v2", S5_ALL_FAILURE_HASH, "rules_gap",
        false, false, true, "missing_global_invariant", teacherStableHash(evidence)))
}

private func r6WriteFailureProposalsWithoutProtectedText(root: String): Unit {
    for ((path, lane, title, content, trigger, scope, priority) in [
        ("proposal-rules.json", "rules", "Preserve complete text units",
            "Bounded labels must end on complete Rune boundaries.",
            "When rendering a bounded label", "Cangjie text rendering", Int64(100)),
        ("proposal-skill.json", "skill", "Review bounded text output",
            "Inspect Rune boundaries before publishing a bounded label.",
            "When reviewing bounded output", "Cangjie output review", Int64(90))
    ]) {
        let evidence = "{\"schemaVersion\":\"teacher-failure-asset-generation-response-v1\"," +
            "\"lane\":\"${lane}\",\"title\":\"${title}\",\"content\":\"${content}\"," +
            "\"trigger\":\"${trigger}\",\"scope\":\"${scope}\",\"priority\":${priority}}"
        let response = TeacherFailureAssetGenerationResponse(lane, title, content, trigger, scope,
            priority, "sha256:${teacherStableHash(evidence)}")
        _ = teacherAtomicWrite("${root}/fixture/${path}",
            renderTeacherFailureAssetGenerationResponse(response) + "\n")
    }
}

private func r6PrepareOpaqueProtectedRoot(root: String): Unit {
    remove(Path("${root}/fixture/protected-root"), recursive: true)
    Directory.create(Path("${root}/fixture/protected-root"), recursive: true)
    _ = teacherAtomicWrite("${root}/fixture/protected-root/opaque-sentinel.txt",
        "amber lattice sentinel 46027\n")
}

private func r6GeneratorScript(root: String): String {
    let knowledge = teacherReadUtf8File("${root}/fixture/proposal-knowledge.json").trimAscii()
    let skill = teacherReadUtf8File("${root}/fixture/proposal-skill.json").trimAscii()
    let rules = teacherReadUtf8File("${root}/fixture/proposal-rules.json").trimAscii()
    "#!/bin/zsh\nrequest=''\noutput=''\nwhile (( $# > 0 )); do\n  case \"$1\" in\n" +
        "    --request) request=\"$2\"; shift 2;;\n    --output) output=\"$2\"; shift 2;;\n" +
        "    *) exit 41;;\n  esac\ndone\n" +
        "lane=$(/usr/bin/sed -E 's/.*\"lane\":\"([^\"]+)\".*/\\1/' \"$request\")\n" +
        "case \"$lane\" in\n  knowledge) print -r -- '${knowledge}' > \"$output\";;\n" +
        "  skill) print -r -- '${skill}' > \"$output\";;\n" +
        "  rules) print -r -- '${rules}' > \"$output\";;\n  *) exit 42;;\nesac\n"
}

private func r6PrepareRuntimeContracts(root: String): Unit {
    Directory.create(Path("${root}/adapter-workspace"), recursive: true)
    r6WriteExecutable("${root}/runtime", r6ProviderRuntimeScript())
    let control = renderTeacherStudentCompletionControl(TeacherStudentCompletionControl(
        "D-ckb-mcp-http", "completion-only-v1", 1,
        "sha256:${teacherStableHash(teacherStudentCompletionOutputSchema())}",
        "sha256:${teacherStableHash("sampling-capability")}", 32768, 0, 600,
        "sha256:${teacherStableHash("runtime-config")}",
        teacherStudentCompletionCommandHash("gpt-5.6-sol")))
    _ = teacherAtomicWrite("${root}/completion-control.json", control)
    let capability = "{\"schemaVersion\":\"deterministic-provider-prompt-capability-v1\"}\n"
    _ = teacherAtomicWrite("${root}/prompt-capability.json", capability)
    let identity = sealTeacherValidationIdentity("codex", "gpt-5.6-sol", "claude-code-2.1.0",
        teacherValidationExecutableHash(canonicalize(Path("${root}/runtime")).toString()),
        "sha256:${teacherStableHash(control)}", "sha256:${teacherStableHash(capability)}")
    _ = teacherAtomicWrite("${root}/validation-identity.json", renderTeacherValidationIdentity(identity))
}

private func r6RealIdentityArgs(root: String): Array<String> {
    let runtime = canonicalize(Path("${root}/runtime")).toString()
    ["--validation-identity", "${root}/validation-identity.json",
        "--completion-control", "${root}/completion-control.json",
        "--prompt-capability", "${root}/prompt-capability.json",
        "--provider-runtime", runtime,
        "--adapter-workspace", "${root}/adapter-workspace"]
}

private func r6Append(target: ArrayList<String>, values: Array<String>): Unit {
    for (value in values) { target.add(value) }
}

private func r6RealSeedArgs(root: String): Array<String> {
    let out = ArrayList<String>()
    r6Append(out, ["context-seed-build", "--allowed-root", root,
        "--fixture-root", "${root}/real-fixtures",
        "--fixture-root-hash", teacherDirectoryHash("${root}/real-fixtures"),
        "--source-root", "${root}/fixture/source-root", "--protected-root",
        "${root}/fixture/protected-root", "--rules-content", "${root}/fixture/proposal-rules.json",
        "--skills-content", "${root}/fixture/proposal-skill.json",
        "--frozen-knowledge-reference", "${root}/fixture/knowledge-reference.json",
        "--run-id", "real-seed-r6", "--output-root", "${root}/exports"])
    r6Append(out, r6RealIdentityArgs(root)); out.toArray()
}

private func r6RealFailureArgs(root: String): Array<String> {
    let classifierA = canonicalize(Path("${root}/classifier-a")).toString()
    let classifierB = canonicalize(Path("${root}/classifier-b")).toString()
    let generator = canonicalize(Path("${root}/generator")).toString()
    let out = ArrayList<String>()
    r6Append(out, ["failure-assets-build", "--allowed-root", root,
        "--fixture-root", "${root}/real-fixtures",
        "--fixture-root-hash", teacherDirectoryHash("${root}/real-fixtures"),
        "--failure", "${root}/fixture/completion-failure.json", "--expected-hash", S5_ALL_FAILURE_HASH,
        "--source-root", "${root}/fixture/source-root", "--protected-root",
        "${root}/fixture/protected-root", "--base-context-root", "${root}/base-context",
        "--classifier-a", classifierA, "--classifier-a-hash", teacherValidationExecutableHash(classifierA),
        "--classifier-b", classifierB, "--classifier-b-hash", teacherValidationExecutableHash(classifierB),
        "--generator", generator, "--generator-hash", teacherValidationExecutableHash(generator),
        "--authority", "${root}/fixture/knowledge-authority.txt", "--gap-description",
        "${root}/fixture/gap-description.txt", "--knowledge-content",
        "${root}/fixture/knowledge-missing.txt", "--frozen-knowledge-reference",
        "${root}/fixture/knowledge-reference.json", "--run-id", "real-failure-r6",
        "--output-root", "${root}/exports"])
    r6Append(out, r6RealIdentityArgs(root)); out.toArray()
}

private func r6ApprovalArgs(root: String, candidateRoot: String,
    candidateHash: String, baseRoot: String, output: String): Array<String> {
    let out = ArrayList<String>()
    r6Append(out, ["failure-assets-approve", "--allowed-root", root,
        "--source-export", candidateRoot, "--source-root", "${root}/fixture/source-root",
        "--protected-root", "${root}/fixture/protected-root", "--base-context-root", baseRoot,
        "--candidate-set-hash", candidateHash, "--decision", "approve", "--reviewer",
        "independent-r6-reviewer", "--reason", "Verified frozen identity and real lane evidence.",
        "--approved-at-utc", "2026-08-10T00:00:00Z", "--output", output])
    r6Append(out, r6RealIdentityArgs(root)); out.toArray()
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

    // E2E-05A: independent real seed uses direct provider completion and frozen knowledge only.
    @TestCase public func realIndependentSeedIsStudentValidatedAndIdentityApproved(): Unit {
        let root = "/tmp/teacher-real-seed-r6-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            s5PrepareGenesis(root); r6PrepareRealFixtures(root); r6PrepareRuntimeContracts(root)
            @Expect(cangjieTeacherCliMain(r6RealSeedArgs(root)), Int64(0))
            let candidateRoot = "${root}/exports/real-seed-r6"
            let candidate = parseTeacherContextCandidateSetDirectoryV2(root, candidateRoot)
            @Expect(candidate.validationLevel, "student_validated")
            @Expect(candidate.rules.eligible && candidate.skills.eligible && candidate.knowledge.eligible, true)
            @Expect(candidate.rules.lineage, "independent")
            @Expect(candidate.skills.lineage, "independent")
            @Expect(candidate.knowledge.lineage, "independent")
            let human = renderTeacherFailureAssetsBuildOutput(candidate.candidateSetId,
                candidate.candidateSetHash, false, candidate.validationLevel,
                "rules,skills,knowledge")
            @Expect(human.contains("validation=student_validated"), true)
            @Expect(human.contains("\"ok\"") || human.contains("\"result\"") ||
                human.contains("\"sessions\""), false)
            @Expect(cangjieTeacherCliMain(r6ApprovalArgs(root, candidateRoot,
                candidate.candidateSetHash, "none", "${root}/review/real-seed-r6.json")), Int64(0))
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

    // E2E-06: real failure build binds two classifiers, three generated lanes and direct runtime.
    @TestCase public func realFailureBuildIsThreeLaneStudentValidatedAndDisagreementFailsClosed(): Unit {
        let root = "/tmp/teacher-real-failure-r6-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        let negative = "${root}-negative"
        try {
            s5PrepareAll(root); r6PrepareRealFixtures(root); r6PrepareRuntimeContracts(root)
            r6WriteFailureProposalsWithoutProtectedText(root)
            r6PrepareOpaqueProtectedRoot(root)
            let classification = teacherReadUtf8File("${root}/fixture/classification-a.json").trimAscii()
            r6WriteExecutable("${root}/classifier-a", r6FixedAdapterScript(classification))
            r6WriteExecutable("${root}/classifier-b", r6FixedAdapterScript(classification))
            r6WriteExecutable("${root}/generator", r6GeneratorScript(root))
            @Expect(cangjieTeacherCliMain(r6RealFailureArgs(root)), Int64(0))
            let candidateRoot = "${root}/exports/real-failure-r6"
            let candidate = parseTeacherContextCandidateSetDirectoryV2(root, candidateRoot,
                baseContextRoot: "${root}/base-context")
            @Expect(candidate.validationLevel, "student_validated")
            @Expect(candidate.rules.eligible && candidate.skills.eligible && candidate.knowledge.eligible, true)
            @Expect(cangjieTeacherCliMain(r6ApprovalArgs(root, candidateRoot,
                candidate.candidateSetHash, "${root}/base-context",
                "${root}/review/real-failure-r6.json")), Int64(0))

            s5PrepareAll(negative); r6PrepareRealFixtures(negative); r6PrepareRuntimeContracts(negative)
            r6WriteFailureProposalsWithoutProtectedText(negative)
            r6PrepareOpaqueProtectedRoot(negative)
            let first = teacherReadUtf8File("${negative}/fixture/classification-a.json").trimAscii()
            let second = r6RulesOnlyClassification()
            r6WriteExecutable("${negative}/classifier-a", r6FixedAdapterScript(first))
            r6WriteExecutable("${negative}/classifier-b", r6FixedAdapterScript(second))
            r6WriteExecutable("${negative}/generator", r6GeneratorScript(negative))
            @Expect(cangjieTeacherCliMain(r6RealFailureArgs(negative)), Int64(1))
            @Expect(exists(Path("${negative}/exports/real-failure-r6")), false)
        } finally {
            try { remove(Path(root), recursive: true) } catch (_: Exception) {}
            try { remove(Path(negative), recursive: true) } catch (_: Exception) {}
        }
    }
}
