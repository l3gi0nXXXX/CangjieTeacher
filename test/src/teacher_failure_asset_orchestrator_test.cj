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

private func s2Base(root: String): TeacherContextBaseStateV2 {
    loadTeacherContextBaseStateV2(root, "${root}/base-context")
}

private func s2ResealTrailingHash(raw: String, marker: String): (String, String) {
    let clean = raw.trimAscii(); let runes = clean.toRuneArray()
    let suffixSize = (marker + "sha256:" + String(Array<Rune>(64, repeat: r'0')) + "\"}").toRuneArray().size
    if (runes.size <= suffixSize) { throw IllegalArgumentException("test_fixture_invalid") }
    let prefix = String(runes[..runes.size - suffixSize])
    let hash = "sha256:${teacherStableHash(prefix + "}")}"
    (prefix + marker + hash + "\"}\n", hash)
}

private func s2ReplaceRequired(raw: String, original: String, replacement: String): String {
    if (!raw.contains(original)) { throw IllegalArgumentException("test_fixture_invalid") }
    raw.replace(original, replacement)
}

private func s2CanonicalHash(fields: Array<String>): String {
    let evidence = teacherJoin(fields.map({field: String => "${field.toArray().size}:${field}"}), "")
    "sha256:${teacherStableHash(evidence)}"
}

private func s2SealBaseRoot(root: String, caseName: String,
    rulesBundle: String, rulesVisible: String, rulesCount: Int64, rulesLineage: String,
    skillsBundle: String, skillsVisible: String, skillsCount: Int64, skillsLineage: String,
    aggregateLineage: String): String {
    let target = "${root}/${caseName}"
    teacherCopyTree("fixtures/failure_assets_e2e/base-context", target)
    let normalizedRules = if (rulesBundle.contains("\"contentBytes\":94")) {
        rulesBundle.replace("\"contentBytes\":94", "\"contentBytes\":${rulesVisible.toArray().size}")
    } else { rulesBundle }
    let normalizedSkills = if (skillsBundle.contains("\"contentBytes\":286")) {
        skillsBundle.replace("\"contentBytes\":286", "\"contentBytes\":${skillsVisible.toArray().size}")
    } else { skillsBundle }
    let sealedRules = s2ResealTrailingHash(normalizedRules, ",\"canonicalHash\":\"")
    let sealedSkills = s2ResealTrailingHash(normalizedSkills, ",\"canonicalHash\":\"")
    let rulesHash = "sha256:${teacherStableHash(rulesVisible)}"
    let skillsHash = "sha256:${teacherStableHash(skillsVisible)}"
    let knowledgeHash = "sha256:39c400fb1e29b16784f5305012430e3cdcc35e7d4b2c6aceb37b4e6892d29ece"
    let sourceHash = "sha256:3333333333333333333333333333333333333333333333333333333333333333"
    let protectedHash = "sha256:4444444444444444444444444444444444444444444444444444444444444444"
    let combinationValues = [rulesHash, skillsHash, knowledgeHash, sourceHash, protectedHash]
    let combinationEvidence = teacherJoin(combinationValues.map(
        {value: String => "${value.toArray().size}:${value}"}), "")
    let combinationHash = "sha256:${teacherStableHash(combinationEvidence)}"
    let audit = "{\"schemaVersion\":\"ckb-student-context-combination-audit-v1\"," +
        "\"sourceClosureHash\":\"${sourceHash}\",\"protectedClosureHash\":\"${protectedHash}\"," +
        "\"combinationAuditHash\":\"${combinationHash}\",\"passed\":true}\n"
    var manifest = teacherReadUtf8File("${target}/student-context-manifest.json")
    manifest = s2ReplaceRequired(manifest,
        "\"rulesHash\":\"sha256:f973c7709689b1a6a9490e07ad84c8349b2388f575560dc3bed646f9cf878185\"",
        "\"rulesHash\":\"${rulesHash}\"")
    manifest = s2ReplaceRequired(manifest,
        "\"rulesBundleHash\":\"sha256:ace4b0ba120c254d6046570fc0f7be047a40367c982649997f95e7811243a1f0\"",
        "\"rulesBundleHash\":\"${sealedRules[1]}\"")
    manifest = s2ReplaceRequired(manifest, "\"rulesCount\":1", "\"rulesCount\":${rulesCount}")
    manifest = s2ReplaceRequired(manifest, "\"rulesContentBytes\":94",
        "\"rulesContentBytes\":${rulesVisible.toArray().size}")
    manifest = s2ReplaceRequired(manifest, "\"rulesAssetLineage\":\"independent\"",
        "\"rulesAssetLineage\":\"${rulesLineage}\"")
    manifest = s2ReplaceRequired(manifest,
        "\"skillBundleHash\":\"sha256:a8ced175f42dec610b290ce0df958d2e2169b1e6d4cdabb8d8ab2266395067f1\"",
        "\"skillBundleHash\":\"${sealedSkills[1]}\"")
    manifest = s2ReplaceRequired(manifest,
        "\"skillProjectionHash\":\"sha256:fc678ff9d5360559bb4455838eafaf91544a9ad42e747e6b8c453ebe7c335f14\"",
        "\"skillProjectionHash\":\"${skillsHash}\"")
    manifest = s2ReplaceRequired(manifest, "\"skillContentBytes\":286",
        "\"skillContentBytes\":${skillsVisible.toArray().size}")
    manifest = s2ReplaceRequired(manifest, "\"skillCount\":1", "\"skillCount\":${skillsCount}")
    manifest = s2ReplaceRequired(manifest, "\"skillAssetLineage\":\"independent\"",
        "\"skillAssetLineage\":\"${skillsLineage}\"")
    manifest = s2ReplaceRequired(manifest, "\"aggregateAssetLineage\":\"independent\"",
        "\"aggregateAssetLineage\":\"${aggregateLineage}\"")
    manifest = s2ReplaceRequired(manifest,
        "\"combinationAuditHash\":\"sha256:73661941f207eff70f655dfca65602ede84213e59c1c575584125b6a3377ff47\"",
        "\"combinationAuditHash\":\"${combinationHash}\"")
    let sealedManifest = s2ResealTrailingHash(manifest, ",\"compositeHash\":\"")[0]
    _ = teacherAtomicWrite("${target}/student-agents-rules.json", sealedRules[0])
    _ = teacherAtomicWrite("${target}/AGENTS.md", rulesVisible)
    _ = teacherAtomicWrite("${target}/student-skills.json", sealedSkills[0])
    _ = teacherAtomicWrite("${target}/student-skills.prompt.md", skillsVisible)
    _ = teacherAtomicWrite("${target}/combination-audit.json", audit)
    _ = teacherAtomicWrite("${target}/student-context-manifest.json", sealedManifest)
    target
}

@Test
public class TeacherFailureAssetOrchestratorTest {
    @TestCase public func ruleProjectionSortsNumericPriorityBoundaries(): Unit {
        let hash = "sha256:${String(Array<Rune>(64, repeat: r'a'))}"
        let projection = teacherContextAssetProjection("rules", [
            TeacherContextBaseAssetIdentity("rule-zero", hash, content: "zero\n", priority: 0),
            TeacherContextBaseAssetIdentity("rule-one-b", hash, content: "one-b\n", priority: 1),
            TeacherContextBaseAssetIdentity("rule-max", hash, content: "max\n", priority: 1000),
            TeacherContextBaseAssetIdentity("rule-one-a", hash, content: "one-a\n", priority: 1)
        ])
        @Expect(projection, "# Student Rules\nmax\none-a\none-b\nzero\n")
    }

    @TestCase public func baseContextKeepsValidatedInputPathSeparateFromCanonicalReadPath(): Unit {
        let root = "/tmp/teacher-base-path-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            Directory.create(Path(root), recursive: true)
            let inputRoot = "${root}/base-context"
            teacherCopyTree("fixtures/failure_assets_e2e/base-context", inputRoot)
            let base = loadTeacherContextBaseStateV2(root, inputRoot)
            @Expect(base.baseInputRoot, inputRoot)
            @Expect(base.baseRoot, canonicalize(Path(inputRoot)).toString())
            @Expect(base.baseInputRoot.startsWith("/tmp/"), true)
            @Expect(base.baseRoot.startsWith("/private/tmp/"), true)
            @Expect(teacherResolveArtifactInput(root, base.baseInputRoot, directory: true),
                base.baseRoot)
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

    @TestCase public func baseContextReducesMixedLineageAndRejectsResealedSemanticMismatch(): Unit {
        let root = "/tmp/teacher-base-lineage-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            Directory.create(Path(root), recursive: true)
            let fixture = "fixtures/failure_assets_e2e/base-context"
            let baseRules = teacherReadUtf8File("${fixture}/student-agents-rules.json")
            let baseRulesVisible = teacherReadUtf8File("${fixture}/AGENTS.md")
            let baseSkills = teacherReadUtf8File("${fixture}/student-skills.json")
            let baseSkillsVisible = teacherReadUtf8File("${fixture}/student-skills.prompt.md")
            let derivedContent = "\n## Derived rule\n\nKeep derived rule context.\n\nTrigger: review\nScope: global\n"
            let derivedCanonical = s2CanonicalHash(["derived-rule", "derived-rule-concept",
                "Derived rule", "Keep derived rule context.", "review", "global", "50",
                "completion_failure", "sha256:5555555555555555555555555555555555555555555555555555555555555555",
                "rules", "humaneval_164_derived",
                "sha256:6666666666666666666666666666666666666666666666666666666666666666",
                "sha256:7777777777777777777777777777777777777777777777777777777777777777",
                "sha256:8888888888888888888888888888888888888888888888888888888888888888",
                "sha256:9999999999999999999999999999999999999999999999999999999999999999"])
            let derivedRow = "{\"schemaVersion\":\"teacher-rule-candidate-v1\"," +
                "\"ruleId\":\"derived-rule\",\"conceptId\":\"derived-rule-concept\"," +
                "\"title\":\"Derived rule\",\"body\":\"Keep derived rule context.\"," +
                "\"trigger\":\"review\",\"scope\":\"global\",\"priority\":50," +
                "\"sourceEvidenceKind\":\"completion_failure\"," +
                "\"sourceEvidenceHash\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\"," +
                "\"assetRole\":\"rules\",\"assetLineage\":\"humaneval_164_derived\"," +
                "\"positiveEvidenceHash\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\"," +
                "\"negativeEvidenceHash\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\"," +
                "\"boundaryEvidenceHash\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\"," +
                "\"generalizationEvidenceHash\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\"," +
                "\"contentHash\":\"sha256:${teacherStableHash(derivedContent)}\"," +
                "\"canonicalHash\":\"${derivedCanonical}\"," +
                "\"content\":\"\\n## Derived rule\\n\\nKeep derived rule context.\\n\\nTrigger: review\\nScope: global\\n\"}"
            let mixedVisible = baseRulesVisible + derivedContent
            var mixedRules = s2ReplaceRequired(baseRules, "\"ruleCount\":1", "\"ruleCount\":2")
            mixedRules = s2ReplaceRequired(mixedRules, "\"contentBytes\":94",
                "\"contentBytes\":${mixedVisible.toArray().size}")
            mixedRules = s2ReplaceRequired(mixedRules, "\"rules\":[", "\"rules\":[${derivedRow},")
            let mixedPath = s2SealBaseRoot(root, "mixed-valid", mixedRules, mixedVisible, 2,
                "humaneval_164_derived", baseSkills, baseSkillsVisible, 1, "independent",
                "humaneval_164_derived")
            let mixed = loadTeacherContextBaseStateV2(root, mixedPath)
            @Expect(mixed.rulesCount, Int64(2))
            @Expect(mixed.rulesLineage, "humaneval_164_derived")

            let falsePath = "${root}/mixed-falsely-independent"
            teacherCopyTree(mixedPath, falsePath)
            var falseManifest = teacherReadUtf8File("${falsePath}/student-context-manifest.json")
            falseManifest = s2ReplaceRequired(falseManifest,
                "\"rulesAssetLineage\":\"humaneval_164_derived\"",
                "\"rulesAssetLineage\":\"independent\"")
            falseManifest = s2ReplaceRequired(falseManifest,
                "\"aggregateAssetLineage\":\"humaneval_164_derived\"",
                "\"aggregateAssetLineage\":\"independent\"")
            _ = teacherAtomicWrite("${falsePath}/student-context-manifest.json",
                s2ResealTrailingHash(falseManifest, ",\"compositeHash\":\"")[0])
            var falseDiagnostic = ""
            try { _ = loadTeacherContextBaseStateV2(root, falsePath) }
            catch (e: Exception) { falseDiagnostic = e.message }
            @Expect(falseDiagnostic, "candidate_base_composite_mismatch")

            let mismatchedRuleCanonical = s2CanonicalHash(["existing-rule", "existing-rule-concept",
                "Existing rule", "Keep existing rule context.", "review", "global", "100",
                "completion_failure", "sha256:1111111111111111111111111111111111111111111111111111111111111111",
                "rules", "independent",
                "sha256:6666666666666666666666666666666666666666666666666666666666666666",
                "sha256:7777777777777777777777777777777777777777777777777777777777777777",
                "sha256:8888888888888888888888888888888888888888888888888888888888888888",
                "sha256:9999999999999999999999999999999999999999999999999999999999999999"])
            var mismatchedRules = s2ReplaceRequired(baseRules,
                "\"sourceEvidenceKind\":\"independent_manifest\"",
                "\"sourceEvidenceKind\":\"completion_failure\"")
            mismatchedRules = s2ReplaceRequired(mismatchedRules,
                "sha256:d9f6c81e7341a5e33fe9896e0bb7531fb1cb6b890fc9f824f336332d42e57f5d",
                mismatchedRuleCanonical)
            let mismatchedRulePath = s2SealBaseRoot(root, "rule-pair-mismatch", mismatchedRules,
                baseRulesVisible, 1, "independent", baseSkills, baseSkillsVisible, 1, "independent",
                "independent")
            var ruleDiagnostic = ""
            try { _ = loadTeacherContextBaseStateV2(root, mismatchedRulePath) }
            catch (e: Exception) { ruleDiagnostic = e.message }
            @Expect(ruleDiagnostic, "candidate_base_composite_mismatch")

            let mismatchedSkillCanonical = s2CanonicalHash(["existing-skill", "1.0.0",
                "Rune-safe review", "Review UTF-8 boundaries before rendering bounded text.",
                "teacher_derived", "text rendering", "independent",
                "sha256:2222222222222222222222222222222222222222222222222222222222222222"])
            var mismatchedSkillsVisible = baseSkillsVisible.replace("general_engineering", "teacher_derived")
                .replace("sha256:d6d98d37bbd4fb0afd3a9e70695fa8deddd6032110d1e1dafc67f3810b08d268",
                    mismatchedSkillCanonical)
            let mismatchedSkillHash = "sha256:${teacherStableHash(mismatchedSkillsVisible)}"
            var mismatchedSkills = baseSkills.replace("general_engineering", "teacher_derived")
                .replace("sha256:d6d98d37bbd4fb0afd3a9e70695fa8deddd6032110d1e1dafc67f3810b08d268",
                    mismatchedSkillCanonical)
                .replace("sha256:fc678ff9d5360559bb4455838eafaf91544a9ad42e747e6b8c453ebe7c335f14",
                    mismatchedSkillHash)
            let mismatchedSkillPath = s2SealBaseRoot(root, "skill-pair-mismatch", baseRules,
                baseRulesVisible, 1, "independent", mismatchedSkills, mismatchedSkillsVisible, 1,
                "independent", "independent")
            var skillDiagnostic = ""
            try { _ = loadTeacherContextBaseStateV2(root, mismatchedSkillPath) }
            catch (e: Exception) { skillDiagnostic = e.message }
            @Expect(skillDiagnostic, "candidate_base_composite_mismatch")

            let zeroHash = "sha256:${String(Array<Rune>(64, repeat: r'0'))}"
            let emptyRulesVisible = "# Student Rules\n"
            let emptyRules = "{\"schemaVersion\":\"ckb-student-rules-bundle-v1\"," +
                "\"rulesVersion\":\"synthetic-rules-v1\",\"ruleCount\":0," +
                "\"contentBytes\":${emptyRulesVisible.toArray().size},\"rules\":[]," +
                "\"canonicalHash\":\"${zeroHash}\"}\n"
            let emptyRulesPath = s2SealBaseRoot(root, "empty-rules", emptyRules,
                emptyRulesVisible, 0, "independent", baseSkills, baseSkillsVisible, 1,
                "independent", "independent")
            var emptyRulesDiagnostic = ""
            try { _ = loadTeacherContextBaseStateV2(root, emptyRulesPath) }
            catch (e: Exception) { emptyRulesDiagnostic = e.message }
            @Expect(emptyRulesDiagnostic, "candidate_base_composite_mismatch")

            let emptySkills = "{\"schemaVersion\":\"ckb-student-skill-bundle-v1\"," +
                "\"bundleVersion\":\"synthetic-skills-v1\",\"skillCount\":0," +
                "\"contentBytes\":0,\"skills\":[],\"canonicalHash\":\"${zeroHash}\"}\n"
            let emptySkillsPath = s2SealBaseRoot(root, "empty-skills", baseRules,
                baseRulesVisible, 1, "independent", emptySkills, "", 0,
                "independent", "independent")
            var emptySkillsDiagnostic = ""
            try { _ = loadTeacherContextBaseStateV2(root, emptySkillsPath) }
            catch (e: Exception) { emptySkillsDiagnostic = e.message }
            @Expect(emptySkillsDiagnostic, "candidate_base_composite_mismatch")
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

    @TestCase public func candidateSetV2GoldenTreeBindsInventoryAndApproval(): Unit {
        let fixtureRoot = "fixtures/student_context_candidate_v2"
        let candidateRoot = "${fixtureRoot}/candidate-set-v2"
        let testRoot = canonicalize(Path(".")).toString()
        let candidatePath = canonicalize(Path(candidateRoot)).toString()
        let candidate = parseTeacherContextCandidateSetDirectoryV2(testRoot, candidatePath)
        @Expect(candidate.candidateSetHash,
            "sha256:4a0c7941f9d455731e96b72138ed379ad8ccdf48e5ffbf9c478f1f145446729a")
        @Expect(candidate.assetInventoryHash,
            "sha256:58e57be659ac51a074a63c88ac446984a8c374e80ac5ef0e2c73693a7d6bd28a")
        @Expect(candidate.rules.treeHash,
            "sha256:7d96e7e4b1690136b4b1eca0c706ded2284090eef9903bf3a5b826dfa4c473d3")
        @Expect(candidate.skills.treeHash,
            "sha256:7c52e017a5ce394f8237beefccdae23c5f49a90b75e0e0fa8dfc88deef615e47")
        @Expect(candidate.knowledge.treeHash,
            "sha256:2a307aa2890878a1cb99f84af3cc95e992adcc882040c1773b598d5cda08d09a")
        @Expect(renderTeacherContextCandidateSetManifestV2(candidate),
            teacherReadUtf8File("${candidateRoot}/candidate-set-manifest.json").trimAscii())
        let approval = teacherReadUtf8File("${fixtureRoot}/approval-v2.json").trimAscii()
        @Expect(validateTeacherContextApprovalV2(approval, candidate), "approve")
        @Expect(teacherStableHash(teacherReadUtf8File("${fixtureRoot}/SHA256SUMS")),
            "18a576336e2c9d116053d7b9081da9bbfab6f61cc9ade62978e9318ab112dd2a")
        for (line in teacherReadUtf8File("${fixtureRoot}/SHA256SUMS").trimAscii().split("\n")) {
            let fields = line.split("  ")
            @Expect(fields.size, Int64(2))
            @Expect(teacherStableHash(teacherReadUtf8File("${fixtureRoot}/${fields[1]}")), fields[0])
        }

        let root = "/tmp/teacher-context-v2-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            Directory.create(Path("${root}/exports"), recursive: true)
            teacherCopyTree("fixtures/failure_assets_e2e/base-context", "${root}/base-context")
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
            let legacySource = "${root}/legacy-source-v1"
            teacherCopyTree(candidateRoot, legacySource)
            _ = teacherAtomicWrite("${legacySource}/audit/source-closure.json",
                "{\"schemaVersion\":\"teacher-context-source-closure-v1\",\"sourceEvidenceManifestHash\":\"sha256:${String(Array<Rune>(64, repeat: r'1'))}\",\"sourceHashes\":[\"sha256:${String(Array<Rune>(64, repeat: r'2'))}\"],\"sourceClosureHash\":\"sha256:${String(Array<Rune>(64, repeat: r'3'))}\"}\n")
            var legacySourceDiagnostic = ""
            try { _ = parseTeacherContextCandidateSetDirectoryV2(root, legacySource) }
            catch (e: Exception) { legacySourceDiagnostic = e.message }
            @Expect(legacySourceDiagnostic, "candidate_set_schema_invalid")

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
            teacherCopyTree("fixtures/failure_assets_e2e/base-context", "${root}/base-context")
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
            let auditBase = s2Base(root)
            @Expect(auditTeacherAssetCombinationLeakage(auditBase.rulesVisible,
                auditBase.skillsVisible, "", closure.protectedArtifacts).passed, true)
            @Expect(auditTeacherAssetCombinationLeakage(
                auditBase.rulesVisible + failure.failureObservation,
                auditBase.skillsVisible, "", closure.protectedArtifacts).passed, false)
            @Expect(auditTeacherAssetCombinationLeakage(auditBase.rulesVisible,
                auditBase.skillsVisible + failure.failureObservation, "",
                closure.protectedArtifacts).passed, false)
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
                    ScaffoldTeacherFailureKnowledgeAdapter(atomExecutor), closure, s2Base(root),
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
                        if (rulesEligible) { @Expect(candidate.rules.count, Int64(2)) }
                        if (skillEligible) { @Expect(candidate.skills.count, Int64(2)) }
                        @Expect(parseTeacherContextCandidateSetDirectoryV2(root,
                            "${root}/exports/${candidate.candidateSetId}",
                            baseContextRoot: "${root}/base-context").candidateSetHash,
                            candidate.candidateSetHash)
                        let approval = approveTeacherContextCandidateSetV2(root,
                            "${root}/exports/${candidate.candidateSetId}", "${root}/failure-source",
                            "${root}/failure-protected", "${root}/base-context",
                            "approve", "fixture-reviewer",
                            "Verified actual closure roots.", "2026-08-07T00:00:00Z")
                        @Expect(validateTeacherContextApprovalV2(approval, candidate), "approve")
                        if (kind == "knowledge_gap") {
                            let driftRoot = "${root}/failure-protected-drift"
                            teacherCopyTree("${root}/failure-protected", driftRoot)
                            _ = teacherAtomicWrite("${driftRoot}/failure-observation.txt", "drifted")
                            var driftDiagnostic = ""
                            try { _ = approveTeacherContextCandidateSetV2(root,
                                "${root}/exports/${candidate.candidateSetId}", "${root}/failure-source",
                                driftRoot, "${root}/base-context",
                                "approve", "fixture-reviewer", "invalid drift",
                                "2026-08-07T00:00:00Z") }
                            catch (e: Exception) { driftDiagnostic = e.message }
                            @Expect(driftDiagnostic, "candidate_approval_hash_mismatch")
                            let renamedSource = "${root}/failure-source-renamed"
                            teacherCopyTree("${root}/failure-source", renamedSource)
                            rename(Path("${renamedSource}/sources/completion-failure.json"),
                                to: Path("${renamedSource}/sources/renamed-failure.json"))
                            var renameDiagnostic = ""
                            try { _ = approveTeacherContextCandidateSetV2(root,
                                "${root}/exports/${candidate.candidateSetId}", renamedSource,
                                "${root}/failure-protected", "${root}/base-context", "approve",
                                "fixture-reviewer", "invalid rename", "2026-08-07T00:00:00Z") }
                            catch (e: Exception) { renameDiagnostic = e.message }
                            @Expect(renameDiagnostic, "candidate_approval_hash_mismatch")
                        }
                    case None => @Expect(expectedLanes, Int64(0))
                }
                if (knowledgeEligible) { @Expect(atomExecutor.calls > 0, true) }
            }

            let actualBase = s2Base(root)
            let crossProtectedBasePath = s2SealBaseRoot(root, "cross-protected-base",
                teacherReadUtf8File("fixtures/failure_assets_e2e/base-context/student-agents-rules.json"),
                teacherReadUtf8File("fixtures/failure_assets_e2e/base-context/AGENTS.md"),
                1, "independent",
                teacherReadUtf8File("fixtures/failure_assets_e2e/base-context/student-skills.json"),
                teacherReadUtf8File("fixtures/failure_assets_e2e/base-context/student-skills.prompt.md"),
                1, "independent", "independent")
            let crossProtectedBase = loadTeacherContextBaseStateV2(root, crossProtectedBasePath)
            let ruleLeakClassification = s2InternalClassification(
                "rules_gap", false, false, true, "missing_global_invariant")
            let ruleLeakFixtures = s2FullFixtures("cross-protected-rule")
            let ruleLeakExecutions = executeTeacherAssetFixtureBundle(ruleLeakFixtures,
                FakeTeacherAssetFixtureExecutor())
            let ruleLeakProposal = parseTeacherFailureAssetGenerationResponse(S2Generator().generate(
                TeacherFailureAssetGenerationRequest(failure.evidenceHash,
                    ruleLeakClassification.classificationEvidenceHash, "rules",
                    "Reusable Unicode boundary gap 中文🙂")))
            let ruleLeakCandidate = buildTeacherRuleCandidate(ruleLeakClassification,
                "cross-protected-rule", "cross-protected-rule-concept", ruleLeakProposal.title,
                ruleLeakProposal.content, ruleLeakProposal.trigger, ruleLeakProposal.scope,
                ruleLeakProposal.priority, "completion_failure", failure.evidenceHash,
                TeacherRuleTestBundle(ruleLeakExecutions))
            let ruleLeakOperation = buildTeacherContextAssetOperation("rules",
                ruleLeakCandidate.ruleId, "add", "", ruleLeakCandidate.canonicalHash,
                crossProtectedBase.rulesAssets)
            let ruleSingle = renderTeacherAgentsMarkdown([ruleLeakCandidate])
            let ruleFragment = String(ruleSingle.toRuneArray()[
                "# Student Rules\n".toRuneArray().size..])
            let protectedRulesProjection = teacherContextAssetProjection("rules",
                applyTeacherContextAssetOperation(crossProtectedBase.rulesAssets, ruleLeakOperation,
                    ruleFragment, priority: ruleLeakCandidate.priority))
            let ruleBridge = "scope global ## reusable"
            @Expect(auditTeacherAssetCombinationLeakage(crossProtectedBase.rulesVisible,
                "", "", [ruleBridge]).passed, true)
            @Expect(auditTeacherAssetCombinationLeakage(ruleFragment,
                "", "", [ruleBridge]).passed, true)
            @Expect(auditTeacherAssetCombinationLeakage(protectedRulesProjection,
                "", "", [ruleBridge]).passed, false)
            Directory.create(Path("${root}/cross-rule-protected"), recursive: true)
            _ = teacherAtomicWrite("${root}/cross-rule-protected/final-rules.txt",
                ruleBridge)
            let ruleLeakClosure = loadTeacherContextSourceClosure(root, "${root}/failure-source",
                "${root}/cross-rule-protected")
            let ruleLeakId = "candidate-cross-protected-rules"
            var ruleLeakDiagnostic = ""
            try {
                _ = buildTeacherFailureAssets(TeacherFailureAssetBuildRequestV2(failure,
                    ruleLeakClassification, ruleLeakClassification,
                    "Reusable Unicode boundary gap 中文🙂", S2Generator(), ruleLeakFixtures,
                    s2FullFixtures("unused-cross-rule-skill"), FakeTeacherAssetFixtureExecutor(),
                    TeacherFailureKnowledgeRequest("g-rune", "compiler missing 'Rune'", atom[0], atom[1],
                        "${root}/atom-cross-rule", ruleLeakClosure.protectedArtifacts),
                    ScaffoldTeacherFailureKnowledgeAdapter(S2AtomExecutor()), ruleLeakClosure,
                    crossProtectedBase, ruleLeakId, ruleLeakCandidate.ruleId,
                    ruleLeakCandidate.conceptId, "unused-cross-rule-skill", "add", "", "add", "",
                    root, "${root}/exports"))
            } catch (e: Exception) { ruleLeakDiagnostic = e.message }
            @Expect(ruleLeakDiagnostic, "protected_asset_combination")
            @Expect(exists(Path("${root}/exports/${ruleLeakId}")), false)

            let skillLeakClassification = s2InternalClassification(
                "procedure_gap", false, true, false, "missing_reusable_procedure")
            let skillLeakFixtures = s2FullFixtures("cross-protected-skill")
            let skillLeakExecutions = executeTeacherAssetFixtureBundle(skillLeakFixtures,
                FakeTeacherAssetFixtureExecutor())
            let skillLeakProposal = parseTeacherFailureAssetGenerationResponse(S2Generator().generate(
                TeacherFailureAssetGenerationRequest(failure.evidenceHash,
                    skillLeakClassification.classificationEvidenceHash, "skill",
                    "Reusable Unicode boundary gap 中文🙂")))
            let skillLeakCandidate = buildTeacherSkillCandidateFromFailureAsset(failure,
                skillLeakClassification, skillLeakProposal, skillLeakExecutions,
                "x7q9x7q9")
            let skillLeakOperation = buildTeacherContextAssetOperation("skills",
                skillLeakCandidate.skillId, "add", "", skillLeakCandidate.contentHash,
                crossProtectedBase.skillsAssets)
            let protectedSkillsProjection = teacherContextAssetProjection("skills",
                applyTeacherContextAssetOperation(crossProtectedBase.skillsAssets, skillLeakOperation,
                    renderCandidateSkillExport(skillLeakCandidate)))
            let skillDelta = renderCandidateSkillExport(skillLeakCandidate)
            let skillBridge = "text --- name"
            @Expect(auditTeacherAssetCombinationLeakage("", crossProtectedBase.skillsVisible,
                "", [skillBridge]).passed, true)
            @Expect(auditTeacherAssetCombinationLeakage("", skillDelta,
                "", [skillBridge]).passed, true)
            @Expect(auditTeacherAssetCombinationLeakage("", protectedSkillsProjection,
                "", [skillBridge]).passed, false)
            Directory.create(Path("${root}/cross-skill-protected"), recursive: true)
            _ = teacherAtomicWrite("${root}/cross-skill-protected/final-skills.txt",
                skillBridge)
            let skillLeakClosure = loadTeacherContextSourceClosure(root, "${root}/failure-source",
                "${root}/cross-skill-protected")
            let skillLeakId = "candidate-cross-protected-skills"
            var skillLeakDiagnostic = ""
            try {
                _ = buildTeacherFailureAssets(TeacherFailureAssetBuildRequestV2(failure,
                    skillLeakClassification, skillLeakClassification,
                    "Reusable Unicode boundary gap 中文🙂", S2Generator(),
                    s2FullFixtures("unused-cross-skill-rule"), skillLeakFixtures,
                    FakeTeacherAssetFixtureExecutor(),
                    TeacherFailureKnowledgeRequest("g-rune", "compiler missing 'Rune'", atom[0], atom[1],
                        "${root}/atom-cross-skill", skillLeakClosure.protectedArtifacts),
                    ScaffoldTeacherFailureKnowledgeAdapter(S2AtomExecutor()), skillLeakClosure,
                    crossProtectedBase, skillLeakId, "unused-cross-skill-rule", "unused-cross-skill-concept",
                    skillLeakCandidate.skillId, "add", "", "add", "", root, "${root}/exports"))
            } catch (e: Exception) { skillLeakDiagnostic = e.message }
            @Expect(skillLeakDiagnostic, "protected_asset_combination")
            @Expect(exists(Path("${root}/exports/${skillLeakId}")), false)

            var collisionDiagnostic = ""
            try { _ = buildTeacherContextAssetOperation("rules", "existing-rule", "add", "",
                "sha256:${String(Array<Rune>(64, repeat: r'a'))}", actualBase.rulesAssets) }
            catch (e: Exception) { collisionDiagnostic = e.message }
            @Expect(collisionDiagnostic, "candidate_operation_invalid")
            var staleReplaceDiagnostic = ""
            try { _ = buildTeacherContextAssetOperation("skills", "existing-skill", "replace",
                "sha256:${String(Array<Rune>(64, repeat: r'b'))}",
                "sha256:${String(Array<Rune>(64, repeat: r'c'))}", actualBase.skillsAssets) }
            catch (e: Exception) { staleReplaceDiagnostic = e.message }
            @Expect(staleReplaceDiagnostic, "candidate_replace_hash_mismatch")

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
