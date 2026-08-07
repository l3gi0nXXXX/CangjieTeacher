package cangjie_teacher_test

import std.unittest.testmacro.*
import std.fs.*
import std.time.*
import cangjie_teacher.*

private class S2AtomExecutor <: TeacherCommandExecutor {
    public var calls: Int64 = 0
    public func execute(spec: TeacherCommandSpec): TeacherProcessResult {
        calls += 1
        if (spec.cwd.contains("/negative") && spec.args[0] == "build") {
            TeacherProcessResult(1, "synthetic failure")
        } else { TeacherProcessResult(0, "ok") }
    }
}

private func s2FullFixtures(prefix: String): Array<TeacherAssetFixture> {
    [
        TeacherAssetFixture("${prefix}-unit", "unit", "non_humaneval_experiment", "Review Rune unit behavior.", "unit-passed"),
        TeacherAssetFixture("${prefix}-positive", "positive", "non_humaneval_experiment", "Review Rune positive behavior.", "positive-passed"),
        TeacherAssetFixture("${prefix}-negative", "negative", "non_humaneval_experiment", "Reject an invalid Rune boundary.", "negative-passed"),
        TeacherAssetFixture("${prefix}-boundary", "boundary", "non_humaneval_experiment", "Review 中文🙂 Rune boundary.", "boundary-passed"),
        TeacherAssetFixture("${prefix}-general-a", "generalization", "non_humaneval_experiment", "Apply Rune review to labels.", "general-a-passed"),
        TeacherAssetFixture("${prefix}-general-b", "generalization", "non_humaneval_experiment", "Apply Rune review to lists.", "general-b-passed"),
        TeacherAssetFixture("${prefix}-general-c", "generalization", "non_humaneval_experiment", "Apply Rune review to empty text.", "general-c-passed")
    ]
}

private func s2AtomBundle(hash: String, lineage: String): (String, String) {
    let source = "main() { let value: Rune = r'a'; println(value) }"
    let tests = "[{\"category\":\"positive\",\"operation\":\"contains\",\"input\":\"rune\",\"needle\":\"rune\",\"expected\":\"true\",\"source\":\"${source}\",\"dependencyProfile\":\"none\",\"expectedMode\":\"pass\"},{\"category\":\"negative\",\"operation\":\"contains\",\"input\":\"rune\",\"needle\":\"rune\",\"expected\":\"true\",\"source\":\"${source}\",\"dependencyProfile\":\"none\",\"expectedMode\":\"compile_reject\",\"expectedDiagnostic\":\"synthetic failure\"},{\"category\":\"boundary\",\"operation\":\"rune_count\",\"input\":\"😀\",\"expected\":\"1\",\"source\":\"${source}\",\"dependencyProfile\":\"none\",\"expectedMode\":\"pass\"}]"
    let bundle = "{\"atomId\":\"synthetic-rune-knowledge\",\"knowledgeFamily\":\"standard_library\",\"sourceClass\":\"official\",\"citation\":\"https://docs.cangjie-lang.cn/docs/1.0.0/lang_zh_cn/basic_programming_concepts/source_zh_cn/runes.html\",\"targetVersion\":\"cangjie-1.0.0-synthetic\",\"candidateHash\":\"${hash}\",\"knowledgeText\":\"Rune values preserve Unicode scalar boundaries.\",\"example\":\"Declare a Rune before text conversion.\",\"extractor\":{\"provider\":\"fixture\",\"model\":\"fake-scaffold-v1\",\"exitCode\":0,\"transcriptHash\":\"sha256:${String(Array<Rune>(64, repeat: r'1'))}\"},\"purificationPassed\":true,\"tests\":${tests}}"
    let reference = "{\"schemaVersion\":\"ckb-frozen-knowledge-reference-v1\",\"knowledgeCandidateHash\":\"${hash}\",\"knowledgeVersion\":\"cangjie-1.0.0-synthetic\",\"frozenCandidateManifestHash\":\"sha256:${String(Array<Rune>(64, repeat: r'2'))}\",\"knowledgeContentHash\":\"sha256:${String(Array<Rune>(64, repeat: r'3'))}\",\"assetLineage\":\"${lineage}\"}"
    (bundle, reference)
}

private func s2Base(): TeacherContextBaseStateV2 {
    TeacherContextBaseStateV2(
        "sha256:e902e83f85f6f951168790f3ee0e54a757358f7614d72b6fea85fd57d95831b6",
        "sha256:08565a321868d1fede4e622ed0570a6347bfec0243acc7fe0f18b3bcbcf36c40", 1,
        "independent", "# Existing Rules\n", [],
        "sha256:dff0848ff59ab53766538ff3237c85f4ca2b90d4b93a80237c93e3e9f4bf2124", 1,
        "independent", "# Existing Skill\n", [],
        "sha256:39c400fb1e29b16784f5305012430e3cdcc35e7d4b2c6aceb37b4e6892d29ece",
        "cangjie-1.0.0-synthetic", "independent", "Existing Rune knowledge.")
}

@Test
public class TeacherFailureAssetOrchestratorTest {
    @TestCase public func candidateSetV2GoldenTreeBindsInventoryAndApproval(): Unit {
        let fixtureRoot = "fixtures/student_context_candidate_v2"
        let candidateRoot = "${fixtureRoot}/candidate-set-v2"
        let testRoot = canonicalize(Path(".")).toString()
        let candidatePath = canonicalize(Path(candidateRoot)).toString()
        let candidate = parseTeacherContextCandidateSetDirectoryV2(testRoot, candidatePath)
        @Expect(candidate.candidateSetHash,
            "sha256:54cb448ba0ec3a151a3279851af96b7df6cfb22dc93261f43b8d085752634956")
        @Expect(candidate.assetInventoryHash,
            "sha256:81d1b6b3ce9dd3d685f836a2a6bc8378b020c1d2ed6dc14ea1c091d1eddcc01e")
        @Expect(candidate.rules.treeHash,
            "sha256:da1c5be60780c0bd2bb4620ae21ee178e9a3a5b62a338a69b870587e796f24bf")
        @Expect(candidate.skills.treeHash,
            "sha256:7c52e017a5ce394f8237beefccdae23c5f49a90b75e0e0fa8dfc88deef615e47")
        @Expect(candidate.knowledge.treeHash,
            "sha256:2a307aa2890878a1cb99f84af3cc95e992adcc882040c1773b598d5cda08d09a")
        @Expect(renderTeacherContextCandidateSetManifestV2(candidate),
            teacherReadUtf8File("${candidateRoot}/candidate-set-manifest.json").trimAscii())
        let approval = teacherReadUtf8File("${fixtureRoot}/approval-v2.json").trimAscii()
        @Expect(validateTeacherContextApprovalV2(approval, candidate), "approve")
        @Expect(teacherStableHash(teacherReadUtf8File("${fixtureRoot}/SHA256SUMS")),
            "9c559387f5b87d782246f08279fd136a6e64d2ca817ddbf0c638a23420fffae4")
        for (line in teacherReadUtf8File("${fixtureRoot}/SHA256SUMS").trimAscii().split("\n")) {
            let fields = line.split("  ")
            @Expect(fields.size, Int64(2))
            @Expect(teacherStableHash(teacherReadUtf8File("${fixtureRoot}/${fields[1]}")), fields[0])
        }

        let root = "/tmp/teacher-context-v2-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            Directory.create(Path("${root}/exports"), recursive: true)
            @Expect(exportTeacherContextCandidateSetV2(candidate, root, "${root}/exports"),
                renderTeacherContextCandidateSetManifestV2(candidate))
            let exported = "${root}/exports/${candidate.candidateSetId}"
            @Expect(parseTeacherContextCandidateSetDirectoryV2(root, exported).candidateSetHash,
                candidate.candidateSetHash)
            @Expect(exportTeacherContextCandidateSetV2(candidate, root, "${root}/exports"),
                renderTeacherContextCandidateSetManifestV2(candidate))

            let tampered = "${root}/tampered"
            teacherCopyTree(candidateRoot, tampered)
            _ = teacherAtomicWrite("${tampered}/skills/rune-safe-review/SKILL.md", "tampered\n")
            var tamperDiagnostic = ""
            try { _ = parseTeacherContextCandidateSetDirectoryV2(root, tampered) }
            catch (e: Exception) { tamperDiagnostic = e.message }
            @Expect(tamperDiagnostic, "candidate_lane_hash_mismatch")

            let symlinked = "${root}/symlinked"
            teacherCopyTree(candidateRoot, symlinked)
            remove(Path("${symlinked}/knowledge/knowledge-candidate-reference.json"))
            SymbolicLink.create(Path("${symlinked}/knowledge/knowledge-candidate-reference.json"),
                to: Path("${candidateRoot}/knowledge/knowledge-candidate-reference.json"))
            var symlinkDiagnostic = ""
            try { _ = parseTeacherContextCandidateSetDirectoryV2(root, symlinked) }
            catch (e: Exception) { symlinkDiagnostic = e.message }
            @Expect(symlinkDiagnostic, "candidate_set_schema_invalid")

            let alias = "${root}/candidate-alias"
            SymbolicLink.create(Path(alias), to: Path(candidatePath))
            var aliasDiagnostic = ""
            try { _ = parseTeacherContextCandidateSetDirectoryV2(root, alias) }
            catch (e: Exception) { aliasDiagnostic = e.message }
            @Expect(aliasDiagnostic, "artifact_input_invalid")

            let legacy = "${root}/legacy-v1"
            teacherCopyTree(candidateRoot, legacy)
            let legacyManifest = teacherReadUtf8File("${legacy}/candidate-set-manifest.json")
                .replace("teacher-student-context-candidate-set-v2",
                    "teacher-student-context-candidate-set-v1")
            _ = teacherAtomicWrite("${legacy}/candidate-set-manifest.json", legacyManifest)
            var legacyDiagnostic = ""
            try { _ = parseTeacherContextCandidateSetDirectoryV2(root, legacy) }
            catch (e: Exception) { legacyDiagnostic = e.message }
            @Expect(legacyDiagnostic, "candidate_set_schema_invalid")

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
        let failureSource = buildTeacherContextSourceManifest("completion_failures",
            ["sha256:${failure.evidenceHash}"])
        let atomHash = "sha256:${String(Array<Rune>(64, repeat: r'4'))}"
        let atom = s2AtomBundle(atomHash, "humaneval_164_derived")
        let root = "/tmp/teacher-context-s2-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            Directory.create(Path("${root}/exports"), recursive: true)
            Directory.create(Path("${root}/failure-source/sources"), recursive: true)
            Directory.create(Path("${root}/failure-protected"), recursive: true)
            _ = teacherAtomicWrite("${root}/failure-source/source-manifest.json",
                renderTeacherContextSourceManifest(failureSource) + "\n")
            _ = teacherAtomicWrite("${root}/failure-source/sources/completion-failure.json",
                renderTeacherCompletionFailureInput(failure) + "\n")
            _ = teacherAtomicWrite("${root}/failure-protected/completion-failure.json",
                renderTeacherCompletionFailureInput(failure) + "\n")
            _ = teacherAtomicWrite("${root}/failure-protected/failure-observation.txt",
                failure.failureObservation)
            let closure = loadTeacherContextSourceClosure(root, "${root}/failure-source",
                "${root}/failure-protected")
            for ((kind, knowledgeEligible, skillEligible, rulesEligible, reason, expectedLanes) in [
                ("knowledge_gap", true, false, false, "missing_versioned_fact", Int64(1)),
                ("procedure_gap", false, true, false, "missing_reusable_procedure", Int64(1)),
                ("rules_gap", false, false, true, "missing_global_invariant", Int64(1)),
                ("all_assets_gap", true, true, true, "multiple_reusable_gaps", Int64(3)),
                ("none", false, false, false, "no_reusable_gap", Int64(0))
            ]) {
                let internal = s2InternalClassification(kind, knowledgeEligible, skillEligible,
                    rulesEligible, reason)
                let atomExecutor = S2AtomExecutor()
                let request = TeacherFailureAssetBuildRequestV2(failure, internal, internal,
                    "Reusable Unicode boundary gap 中文🙂", S2Generator(),
                    s2FullFixtures("rule-${kind.replace("_", "-")}"),
                    s2FullFixtures("skill-${kind.replace("_", "-")}"),
                    FakeTeacherAssetFixtureExecutor(),
                    TeacherFailureKnowledgeRequest("g-rune", "compiler missing 'Rune'", atom[0], atom[1],
                        "${root}/atom-${kind.replace("_", "-")}", closure.protectedArtifacts),
                    ScaffoldTeacherFailureKnowledgeAdapter(atomExecutor), closure, s2Base(),
                    "candidate-${kind.replace("_", "-")}", "rule-${kind.replace("_", "-")}",
                    "concept-${kind.replace("_", "-")}", "skill-${kind.replace("_", "-")}",
                    "add", "", "add", "", root, "${root}/exports")
                let built = buildTeacherFailureAssets(request)
                @Expect(built.proposals.size, expectedLanes)
                match (built.candidateSetV2) {
                    case Some(candidate) =>
                        @Expect(expectedLanes > 0, true)
                        @Expect(candidate.rules.eligible, rulesEligible)
                        @Expect(candidate.skills.eligible, skillEligible)
                        @Expect(candidate.knowledge.eligible, knowledgeEligible)
                        @Expect(parseTeacherContextCandidateSetDirectoryV2(root,
                            "${root}/exports/${candidate.candidateSetId}").candidateSetHash,
                            candidate.candidateSetHash)
                        let approval = approveTeacherContextCandidateSetV2(root,
                            "${root}/exports/${candidate.candidateSetId}", "${root}/failure-source",
                            "${root}/failure-protected", "approve", "fixture-reviewer",
                            "Verified actual closure roots.", "2026-08-07T00:00:00Z")
                        @Expect(validateTeacherContextApprovalV2(approval, candidate), "approve")
                        if (kind == "knowledge_gap") {
                            let driftRoot = "${root}/failure-protected-drift"
                            teacherCopyTree("${root}/failure-protected", driftRoot)
                            _ = teacherAtomicWrite("${driftRoot}/failure-observation.txt", "drifted")
                            var driftDiagnostic = ""
                            try { _ = approveTeacherContextCandidateSetV2(root,
                                "${root}/exports/${candidate.candidateSetId}", "${root}/failure-source",
                                driftRoot, "approve", "fixture-reviewer", "invalid drift",
                                "2026-08-07T00:00:00Z") }
                            catch (e: Exception) { driftDiagnostic = e.message }
                            @Expect(driftDiagnostic, "candidate_approval_hash_mismatch")
                        }
                    case None => @Expect(expectedLanes, Int64(0))
                }
                if (knowledgeEligible) { @Expect(atomExecutor.calls > 0, true) }
            }

            let sources = [
                TeacherContextSourceArtifact("official-rune", "official", "Official Rune boundary documentation."),
                TeacherContextSourceArtifact("community-rune", "community", "Community Rune review procedure."),
                TeacherContextSourceArtifact("fixture-rune", "non_humaneval_experiment", "Synthetic Rune fixture evidence.")
            ]
            let source = buildTeacherContextSourceManifest("independent_sources",
                sources.map({value: TeacherContextSourceArtifact => "sha256:${teacherStableHash(value.raw)}"}))
            Directory.create(Path("${root}/independent-source/sources"), recursive: true)
            Directory.create(Path("${root}/independent-protected"), recursive: true)
            _ = teacherAtomicWrite("${root}/independent-source/source-manifest.json",
                renderTeacherContextSourceManifest(source) + "\n")
            for (value in sources) {
                _ = teacherAtomicWrite("${root}/independent-source/sources/${value.sourceId}.txt", value.raw)
                _ = teacherAtomicWrite("${root}/independent-protected/${value.sourceId}.txt", value.raw)
            }
            let independentClosure = loadTeacherContextSourceClosure(root,
                "${root}/independent-source", "${root}/independent-protected")
            let independentAtom = s2AtomBundle(atomHash, "independent")
            let ruleProposal = parseTeacherFailureAssetGenerationResponse(S2Generator().generate(
                TeacherFailureAssetGenerationRequest(String(Array<Rune>(64, repeat: r'a')),
                    String(Array<Rune>(64, repeat: r'b')), "rules", "independent Rune gap")))
            let skillProposal = parseTeacherFailureAssetGenerationResponse(S2Generator().generate(
                TeacherFailureAssetGenerationRequest(String(Array<Rune>(64, repeat: r'a')),
                    String(Array<Rune>(64, repeat: r'b')), "skill", "independent Rune gap")))
            let seed = buildTeacherIndependentContextSeed(TeacherIndependentSeedRequestV2(
                independentClosure, ruleProposal, skillProposal, s2FullFixtures("seed-rule"),
                s2FullFixtures("seed-skill"), FakeTeacherAssetFixtureExecutor(),
                TeacherFailureKnowledgeRequest("g-rune", "compiler missing 'Rune'", independentAtom[0],
                    independentAtom[1], "${root}/atom-seed", []),
                ScaffoldTeacherFailureKnowledgeAdapter(S2AtomExecutor()), "synthetic-seed-v2",
                "seed-rule", "seed-rule-concept", "seed-skill", root, "${root}/exports"))
            @Expect(seed.rules.lineage, "independent")
            @Expect(seed.skills.lineage, "independent")
            @Expect(seed.knowledge.lineage, "independent")
            @Expect(seed.classificationManifestHash, "")
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }

        let internal = s2InternalClassification("all_assets_gap", true, true, true, "multiple_reusable_gaps")
        var leakRejected = ""
        let source = buildTeacherContextSourceManifest("independent_sources", [
            "sha256:${teacherStableHash("official Cangjie Rune docs")}",
            "sha256:${teacherStableHash("non-HumanEval Unicode fixtures")}" ])
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
