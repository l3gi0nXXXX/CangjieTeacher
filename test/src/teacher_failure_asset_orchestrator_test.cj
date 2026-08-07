package cangjie_teacher_test

import std.unittest.testmacro.*
import std.collection.*
import std.fs.*
import std.sort.*
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

private class S2RuleEvidenceExecutor <: TeacherAssetFixtureExecutor {
    private let label: String
    public init(label: String) { this.label = label }
    public func executorKind(): String { "fake_contract" }
    public func providerIdentityHash(): String {
        "sha256:${teacherStableHash("rule-evidence-${label}")}"
    }
    public func modelVersion(): String { "fake-rule-evidence-v1" }
    public func execute(fixture: TeacherAssetFixture): (Int64, String, String) {
        (0, fixture.expectedEvidence, "${label}-${fixture.fixtureId}\r\n")
    }
}

private class S2CanonicalTranscriptFixtureExecutor <: TeacherAssetFixtureExecutor {
    public func executorKind(): String { "fake_contract" }
    public func providerIdentityHash(): String {
        "sha256:${teacherStableHash("canonical-transcript-fixture")}"
    }
    public func modelVersion(): String { "fake-canonical-transcript-v1" }
    public func execute(fixture: TeacherAssetFixture): (Int64, String, String) {
        (0, fixture.expectedEvidence, "${fixture.fixtureId}  \r\n")
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

private func s2CollectArtifactFiles(current: Path, relative: String,
    out: ArrayList<TeacherArtifactFile>): Unit {
    for (entry in Directory.readFrom(current)) {
        let child = if (relative.isEmpty()) { entry.name } else { "${relative}/${entry.name}" }
        if (entry.isDirectory()) { s2CollectArtifactFiles(entry.path, child, out) }
        else { out.add(TeacherArtifactFile(child, teacherReadUtf8File(entry.path.toString()))) }
    }
}

private func s2ArtifactFiles(root: String, lane: String): Array<TeacherArtifactFile> {
    let out = ArrayList<TeacherArtifactFile>()
    s2CollectArtifactFiles(Path("${root}/${lane}"), "", out)
    out.toArray()
}

private func s2ResealGoldenCandidateOuter(root: String, skillCandidateHash: String,
    rulesProjectionHash!: String = "sha256:0ce1be55d3152a921d3c5c5a18653476bd5b99806777e24748af3994a0f037ac",
    rulesCount!: Int64 = 1): Unit {
    let rules = s2ArtifactFiles(root, "rules")
    let skills = s2ArtifactFiles(root, "skills")
    let knowledge = s2ArtifactFiles(root, "knowledge")
    let audit = s2ArtifactFiles(root, "audit")
    let rulesTreeHash = teacherContextLaneTreeHashV2(rules)
    let skillsTreeHash = teacherContextLaneTreeHashV2(skills)
    var skillProjection = ""; var operationBound = false
    for (file in skills) {
        if (file.path.endsWith("/SKILL.md")) { skillProjection += file.content }
        if (file.path.endsWith("/operation.json") &&
            file.content.contains("\"newHash\":\"${skillCandidateHash}\"")) { operationBound = true }
    }
    if (skillProjection.isEmpty() || !operationBound) {
        throw IllegalArgumentException("test_fixture_invalid")
    }
    let skillsProjectionHash = "sha256:${teacherStableHash(skillProjection)}"
    let inventoryHash = teacherContextAssetInventoryHashV2(rules, skills, knowledge, audit: audit)
    let combinationHash = s2CanonicalHash([
        rulesProjectionHash,
        skillsProjectionHash,
        "sha256:39c400fb1e29b16784f5305012430e3cdcc35e7d4b2c6aceb37b4e6892d29ece",
        "sha256:e319c582529ba1fdb48aa374974461af57a01b970b337e58304064987067d4b8",
        "sha256:d30f0da5fb1ac0d6f92588b3fcf71f5d89236721897caa7de8042880836659b9"
    ])
    let manifestPath = "${root}/candidate-set-manifest.json"
    var manifest = teacherReadUtf8File(manifestPath)
    manifest = s2ReplaceRequired(manifest,
        "\"rulesHash\":\"sha256:0ce1be55d3152a921d3c5c5a18653476bd5b99806777e24748af3994a0f037ac\"",
        "\"rulesHash\":\"${rulesProjectionHash}\"")
    manifest = s2ReplaceRequired(manifest,
        "\"rulesTreeHash\":\"sha256:7d96e7e4b1690136b4b1eca0c706ded2284090eef9903bf3a5b826dfa4c473d3\"",
        "\"rulesTreeHash\":\"${rulesTreeHash}\"")
    manifest = s2ReplaceRequired(manifest, "\"rulesCount\":1", "\"rulesCount\":${rulesCount}")
    manifest = s2ReplaceRequired(manifest,
        "\"skillsHash\":\"sha256:e4774bac98335a2912fb43c34cafdb00cb06bcabde767a523d5a46e184a0f9f0\"",
        "\"skillsHash\":\"${skillsProjectionHash}\"")
    manifest = s2ReplaceRequired(manifest,
        "\"skillsTreeHash\":\"sha256:96fcc10d477fb62ab7e733dc6359d5417672a434b358d45940e2a78978588f05\"",
        "\"skillsTreeHash\":\"${skillsTreeHash}\"")
    manifest = s2ReplaceRequired(manifest,
        "\"assetInventoryHash\":\"sha256:316e17b5af69196717ae9590948db3a0287fae6b465266b4df539a2394339ade\"",
        "\"assetInventoryHash\":\"${inventoryHash}\"")
    manifest = s2ReplaceRequired(manifest,
        "\"combinationAuditHash\":\"sha256:938968cf3e9277f220ec4578aa9b4e6862128b5ebfe10eeeef3e404bd24e0757\"",
        "\"combinationAuditHash\":\"${combinationHash}\"")
    _ = teacherAtomicWrite(manifestPath,
        s2ResealTrailingHash(manifest, ",\"candidateSetHash\":\"")[0])
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

    @TestCase public func parserKeepsTwoRuleEvidenceIndependentWithShuffledExecutions(): Unit {
        let fixtureRoot = "fixtures/student_context_candidate_v2/candidate-set-v2"
        let root = "/tmp/teacher-two-rule-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            Directory.create(Path(root), recursive: true)
            let executed = executeTeacherAssetFixtureBundle(s2FullFixtures("second-rule"),
                S2RuleEvidenceExecutor("second"))
            let shuffled = [executed[6], executed[1], executed[0], executed[5], executed[2],
                executed[3], executed[4]]
            let second = buildTeacherIndependentRuleCandidate("second-rule", "second-rule-concept",
                "Second isolated rule", "Keep second-rule evidence isolated.", "When reviewing text.",
                "Cangjie text rendering", 90,
                "sha256:2e7c33c74b6ddb9f7a50b45d1c90545b9c1d4aa00d1ef2b9b69c9bc130449b60",
                TeacherRuleTestBundle(shuffled))
            let operation = TeacherContextAssetOperation("rules", second.ruleId, "add", "",
                second.canonicalHash)
            let secondFiles = teacherRuleCandidateArtifactFiles(second, operation)
            let generalizationAHash = executed[4].transcriptHash
            @Expect(renderTeacherRuleCandidateManifest(second).contains(
                "\"generalizationEvidenceHash\":\"${generalizationAHash}\""), true)

            let existingId = "prefer-rune-safe-text-boundaries"
            let existingHash = "sha256:f4e44a92ea2dfa3728ff0b54a660476b205fa53961c6847f3a28901728995fe7"
            let headerSize = "# Student Rules\n".toRuneArray().size
            let existingRaw = teacherReadUtf8File("${fixtureRoot}/rules/${existingId}/AGENTS.md")
            let existingContent = String(existingRaw.toRuneArray()[headerSize..])
            let secondRaw = renderTeacherAgentsMarkdown([second])
            let secondContent = String(secondRaw.toRuneArray()[headerSize..])
            let rulesProjection = teacherContextAssetProjection("rules", [
                TeacherContextBaseAssetIdentity(existingId, existingHash,
                    content: existingContent, priority: 100),
                TeacherContextBaseAssetIdentity(second.ruleId, second.canonicalHash,
                    content: secondContent, priority: second.priority)
            ])
            let rulesProjectionHash = "sha256:${teacherStableHash(rulesProjection)}"

            let positiveRoot = "${root}/positive"
            teacherCopyTree(fixtureRoot, positiveRoot)
            for (file in secondFiles) {
                _ = teacherAtomicWrite("${positiveRoot}/rules/${file.path}", file.content)
            }
            s2ResealGoldenCandidateOuter(positiveRoot,
                "sha256:b51c608314f131470038059a7407e575cd4e0bf1b6aa513c830d729e8b65c45a",
                rulesProjectionHash: rulesProjectionHash, rulesCount: 2)
            @Expect(parseTeacherContextCandidateSetDirectoryV2(root, positiveRoot).rules.count,
                Int64(2))

            let missingRoot = "${root}/missing-second-negative"
            teacherCopyTree(fixtureRoot, missingRoot)
            for (file in secondFiles) {
                if (!file.path.startsWith("second-rule/tests/second-rule-negative/")) {
                    _ = teacherAtomicWrite("${missingRoot}/rules/${file.path}", file.content)
                }
            }
            s2ResealGoldenCandidateOuter(missingRoot,
                "sha256:b51c608314f131470038059a7407e575cd4e0bf1b6aa513c830d729e8b65c45a",
                rulesProjectionHash: rulesProjectionHash, rulesCount: 2)
            var missingDiagnostic = ""
            try { _ = parseTeacherContextCandidateSetDirectoryV2(root, missingRoot) }
            catch (e: Exception) { missingDiagnostic = e.message }
            @Expect(missingDiagnostic, "candidate_test_evidence_invalid")
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
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
            "sha256:6f1a247361d2f07b663bb45143960ff964540e00cf88beaef05b410554a7c92f")
        @Expect(candidate.assetInventoryHash,
            "sha256:316e17b5af69196717ae9590948db3a0287fae6b465266b4df539a2394339ade")
        @Expect(candidate.rules.treeHash,
            "sha256:7d96e7e4b1690136b4b1eca0c706ded2284090eef9903bf3a5b826dfa4c473d3")
        @Expect(candidate.skills.treeHash,
            "sha256:96fcc10d477fb62ab7e733dc6359d5417672a434b358d45940e2a78978588f05")
        @Expect(candidate.skills.hash,
            "sha256:e4774bac98335a2912fb43c34cafdb00cb06bcabde767a523d5a46e184a0f9f0")
        let goldenSkill = teacherReadUtf8File(
            "${candidateRoot}/skills/rune-safe-review/SKILL.md")
        let goldenSkillHash = "sha256:${teacherStableHash(goldenSkill)}"
        @Expect(candidate.skills.hash, goldenSkillHash)
        @Expect(teacherReadUtf8File(
            "${candidateRoot}/skills/rune-safe-review/SKILL.md").contains("中文🙂"), true)
        @Expect(candidate.knowledge.treeHash,
            "sha256:2a307aa2890878a1cb99f84af3cc95e992adcc882040c1773b598d5cda08d09a")
        @Expect(renderTeacherContextCandidateSetManifestV2(candidate),
            teacherReadUtf8File("${candidateRoot}/candidate-set-manifest.json").trimAscii())
        let approval = teacherReadUtf8File("${fixtureRoot}/approval-v2.json").trimAscii()
        @Expect(validateTeacherContextApprovalV2(approval, candidate), "approve")
        @Expect(teacherStableHash(teacherReadUtf8File("${fixtureRoot}/SHA256SUMS")),
            "c6454da21eca3afad1814ce329afc39f566ba75506194b9a41d2c5309b9e9324")
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

            let noFrontmatter = "${root}/skill-no-frontmatter"
            teacherCopyTree(candidateRoot, noFrontmatter)
            let noFrontmatterSkill = "# Rune-safe review\n\n" +
                "Review UTF-8 boundaries before rendering bounded text. 中文🙂\n"
            let noFrontmatterManifestPath =
                "${noFrontmatter}/skills/rune-safe-review/candidate-manifest.json"
            let noFrontmatterManifest = s2ReplaceRequired(
                teacherReadUtf8File(noFrontmatterManifestPath),
                "\"skillContentHash\":\"sha256:e4774bac98335a2912fb43c34cafdb00cb06bcabde767a523d5a46e184a0f9f0\"",
                "\"skillContentHash\":\"sha256:${teacherStableHash(noFrontmatterSkill)}\"")
            _ = teacherAtomicWrite(noFrontmatterManifestPath,
                s2ResealTrailingHash(noFrontmatterManifest, ",\"artifactHash\":\"")[0])
            _ = teacherAtomicWrite("${noFrontmatter}/skills/rune-safe-review/SKILL.md",
                noFrontmatterSkill)
            s2ResealGoldenCandidateOuter(noFrontmatter,
                "sha256:b51c608314f131470038059a7407e575cd4e0bf1b6aa513c830d729e8b65c45a")
            var noFrontmatterDiagnostic = ""
            try { _ = parseTeacherContextCandidateSetDirectoryV2(root, noFrontmatter) }
            catch (e: Exception) { noFrontmatterDiagnostic = e.message }
            @Expect(noFrontmatterDiagnostic, "candidate_lane_hash_mismatch")

            let skillHashAsCandidate = "${root}/skill-hash-as-candidate"
            teacherCopyTree(candidateRoot, skillHashAsCandidate)
            let skillManifestPath = "${skillHashAsCandidate}/skills/rune-safe-review/candidate-manifest.json"
            let skillManifest = teacherReadUtf8File(skillManifestPath)
            let skillContent = teacherReadUtf8File(
                "${skillHashAsCandidate}/skills/rune-safe-review/SKILL.md")
            let skillContentHash = "sha256:${teacherStableHash(skillContent)}"
            let invalidSkillManifest = s2ResealTrailingHash(s2ReplaceRequired(skillManifest,
                "\"candidateContentHash\":\"sha256:b51c608314f131470038059a7407e575cd4e0bf1b6aa513c830d729e8b65c45a\"",
                "\"candidateContentHash\":\"${skillContentHash}\""), ",\"artifactHash\":\"")[0]
            _ = teacherAtomicWrite(skillManifestPath, invalidSkillManifest)
            let skillHashOperationPath =
                "${skillHashAsCandidate}/skills/rune-safe-review/operation.json"
            _ = teacherAtomicWrite(skillHashOperationPath, s2ReplaceRequired(
                teacherReadUtf8File(skillHashOperationPath),
                "sha256:b51c608314f131470038059a7407e575cd4e0bf1b6aa513c830d729e8b65c45a",
                skillContentHash))
            s2ResealGoldenCandidateOuter(skillHashAsCandidate, skillContentHash)
            var skillHashAsCandidateDiagnostic = ""
            try { _ = parseTeacherContextCandidateSetDirectoryV2(root, skillHashAsCandidate) }
            catch (e: Exception) { skillHashAsCandidateDiagnostic = e.message }
            @Expect(skillHashAsCandidateDiagnostic, "candidate_lane_hash_mismatch")

            let runeLengthHash = "${root}/skill-rune-length-hash"
            teacherCopyTree(candidateRoot, runeLengthHash)
            let hashFields = ["rune-safe-review", "1.0.0", "Rune-safe review",
                "Review UTF-8 boundaries before rendering bounded text. 中文🙂",
                "general_engineering", "Cangjie text rendering", "independent",
                "sha256:c4c4a67ec087a46e1121a076012f52bec8f44e8ab7417c35ed286b290ef414d1"]
            let byteHash = s2CanonicalHash(hashFields)
            let runeEvidence = teacherJoin(hashFields.map({field: String =>
                "${field.toRuneArray().size}:${field}"}), "")
            let runeHash = "sha256:${teacherStableHash(runeEvidence)}"
            @Expect(teacherReadUtf8File(
                "${runeLengthHash}/skills/rune-safe-review/operation.json").contains(
                    "\"newHash\":\"${byteHash}\""), true)
            @Expect(teacherReadUtf8File(
                "${runeLengthHash}/skills/rune-safe-review/candidate-manifest.json").contains(
                    "\"candidateContentHash\":\"${byteHash}\""), true)
            @Expect(runeHash == byteHash, false)
            let runeSkillPath = "${runeLengthHash}/skills/rune-safe-review/SKILL.md"
            let runeSkill = s2ReplaceRequired(teacherReadUtf8File(runeSkillPath),
                "sha256:b51c608314f131470038059a7407e575cd4e0bf1b6aa513c830d729e8b65c45a", runeHash)
            _ = teacherAtomicWrite(runeSkillPath, runeSkill)
            let runeManifestPath = "${runeLengthHash}/skills/rune-safe-review/candidate-manifest.json"
            var runeManifest = s2ReplaceRequired(teacherReadUtf8File(runeManifestPath),
                "\"candidateContentHash\":\"sha256:b51c608314f131470038059a7407e575cd4e0bf1b6aa513c830d729e8b65c45a\"",
                "\"candidateContentHash\":\"${runeHash}\"")
            runeManifest = s2ReplaceRequired(runeManifest,
                "\"skillContentHash\":\"sha256:e4774bac98335a2912fb43c34cafdb00cb06bcabde767a523d5a46e184a0f9f0\"",
                "\"skillContentHash\":\"sha256:${teacherStableHash(runeSkill)}\"")
            _ = teacherAtomicWrite(runeManifestPath,
                s2ResealTrailingHash(runeManifest, ",\"artifactHash\":\"")[0])
            let runeOperationPath = "${runeLengthHash}/skills/rune-safe-review/operation.json"
            _ = teacherAtomicWrite(runeOperationPath, s2ReplaceRequired(
                teacherReadUtf8File(runeOperationPath),
                "sha256:b51c608314f131470038059a7407e575cd4e0bf1b6aa513c830d729e8b65c45a",
                runeHash))
            s2ResealGoldenCandidateOuter(runeLengthHash, runeHash)
            var runeLengthDiagnostic = ""
            try { _ = parseTeacherContextCandidateSetDirectoryV2(root, runeLengthHash) }
            catch (e: Exception) { runeLengthDiagnostic = e.message }
            @Expect(runeLengthDiagnostic, "candidate_lane_hash_mismatch")

            let bundleTamper = "${root}/skill-bundle-tamper"
            teacherCopyTree(candidateRoot, bundleTamper)
            let bundlePath = "${bundleTamper}/skills/rune-safe-review/test-bundle.json"
            let changedBundle = s2ResealTrailingHash(s2ReplaceRequired(
                teacherReadUtf8File(bundlePath), "\"positiveCount\":1", "\"positiveCount\":2"),
                ",\"evidenceHash\":\"")
            _ = teacherAtomicWrite(bundlePath, changedBundle[0])
            let changedCandidateHash = s2CanonicalHash(["rune-safe-review", "1.0.0",
                "Rune-safe review", "Review UTF-8 boundaries before rendering bounded text. 中文🙂",
                "general_engineering", "Cangjie text rendering", "independent", changedBundle[1]])
            let changedSkillPath = "${bundleTamper}/skills/rune-safe-review/SKILL.md"
            let changedSkill = s2ReplaceRequired(teacherReadUtf8File(changedSkillPath),
                "sha256:b51c608314f131470038059a7407e575cd4e0bf1b6aa513c830d729e8b65c45a",
                changedCandidateHash)
            _ = teacherAtomicWrite(changedSkillPath, changedSkill)
            let changedManifestPath =
                "${bundleTamper}/skills/rune-safe-review/candidate-manifest.json"
            var changedManifest = teacherReadUtf8File(changedManifestPath)
            changedManifest = s2ReplaceRequired(changedManifest,
                "\"testBundleHash\":\"sha256:d5b754b0cc435fed3401598a6749199523abd2bda1d099439944d8d9d7a3a5de\"",
                "\"testBundleHash\":\"sha256:${teacherStableHash(changedBundle[0].trimAscii())}\"")
            changedManifest = s2ReplaceRequired(changedManifest,
                "\"testEvidenceHash\":\"sha256:c4c4a67ec087a46e1121a076012f52bec8f44e8ab7417c35ed286b290ef414d1\"",
                "\"testEvidenceHash\":\"${changedBundle[1]}\"")
            changedManifest = s2ReplaceRequired(changedManifest,
                "\"candidateContentHash\":\"sha256:b51c608314f131470038059a7407e575cd4e0bf1b6aa513c830d729e8b65c45a\"",
                "\"candidateContentHash\":\"${changedCandidateHash}\"")
            changedManifest = s2ReplaceRequired(changedManifest,
                "\"skillContentHash\":\"sha256:e4774bac98335a2912fb43c34cafdb00cb06bcabde767a523d5a46e184a0f9f0\"",
                "\"skillContentHash\":\"sha256:${teacherStableHash(changedSkill)}\"")
            _ = teacherAtomicWrite(changedManifestPath,
                s2ResealTrailingHash(changedManifest, ",\"artifactHash\":\"")[0])
            let changedOperationPath = "${bundleTamper}/skills/rune-safe-review/operation.json"
            _ = teacherAtomicWrite(changedOperationPath, s2ReplaceRequired(
                teacherReadUtf8File(changedOperationPath),
                "sha256:b51c608314f131470038059a7407e575cd4e0bf1b6aa513c830d729e8b65c45a",
                changedCandidateHash))
            s2ResealGoldenCandidateOuter(bundleTamper, changedCandidateHash)
            var bundleDiagnostic = ""
            try { _ = parseTeacherContextCandidateSetDirectoryV2(root, bundleTamper) }
            catch (e: Exception) { bundleDiagnostic = e.message }
            @Expect(bundleDiagnostic, "candidate_lane_hash_mismatch")

            let flatMissing = "${root}/skill-flat-missing"
            teacherCopyTree(candidateRoot, flatMissing)
            remove(Path("${flatMissing}/skills/rune-safe-review/tests/positive-contract.txt"))
            s2ResealGoldenCandidateOuter(flatMissing,
                "sha256:b51c608314f131470038059a7407e575cd4e0bf1b6aa513c830d729e8b65c45a")
            var flatMissingDiagnostic = ""
            try { _ = parseTeacherContextCandidateSetDirectoryV2(root, flatMissing) }
            catch (e: Exception) { flatMissingDiagnostic = e.message }
            @Expect(flatMissingDiagnostic, "candidate_set_schema_invalid")

            let flatExtra = "${root}/skill-flat-extra"
            teacherCopyTree(candidateRoot, flatExtra)
            _ = teacherAtomicWrite("${flatExtra}/skills/rune-safe-review/tests/extra-contract.txt",
                "{\"schemaVersion\":\"cangjie-teacher-skill-fixture-v1\",\"task\":\"extra\",\"resultEvidence\":\"extra\"}\n")
            s2ResealGoldenCandidateOuter(flatExtra,
                "sha256:b51c608314f131470038059a7407e575cd4e0bf1b6aa513c830d729e8b65c45a")
            var flatExtraDiagnostic = ""
            try { _ = parseTeacherContextCandidateSetDirectoryV2(root, flatExtra) }
            catch (e: Exception) { flatExtraDiagnostic = e.message }
            @Expect(flatExtraDiagnostic, "candidate_set_schema_invalid")

            let flatDrift = "${root}/skill-flat-drift"
            teacherCopyTree(candidateRoot, flatDrift)
            _ = teacherAtomicWrite("${flatDrift}/skills/rune-safe-review/tests/positive-contract.txt",
                "{\"schemaVersion\":\"cangjie-teacher-skill-fixture-v1\",\"task\":\"drift\",\"resultEvidence\":\"positive-ok\"}\n")
            s2ResealGoldenCandidateOuter(flatDrift,
                "sha256:b51c608314f131470038059a7407e575cd4e0bf1b6aa513c830d729e8b65c45a")
            var flatDriftDiagnostic = ""
            try { _ = parseTeacherContextCandidateSetDirectoryV2(root, flatDrift) }
            catch (e: Exception) { flatDriftDiagnostic = e.message }
            @Expect(flatDriftDiagnostic, "candidate_test_evidence_invalid")

            let extraSkillFile = "${root}/skill-extra-file"
            teacherCopyTree(candidateRoot, extraSkillFile)
            _ = teacherAtomicWrite("${extraSkillFile}/skills/rune-safe-review/raw-secret.txt",
                "must not be accepted\n")
            s2ResealGoldenCandidateOuter(extraSkillFile,
                "sha256:b51c608314f131470038059a7407e575cd4e0bf1b6aa513c830d729e8b65c45a")
            var extraSkillFileDiagnostic = ""
            try { _ = parseTeacherContextCandidateSetDirectoryV2(root, extraSkillFile) }
            catch (e: Exception) { extraSkillFileDiagnostic = e.message }
            @Expect(extraSkillFileDiagnostic, "candidate_set_schema_invalid")

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
                    S2CanonicalTranscriptFixtureExecutor(),
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
                        if (skillEligible) {
                            let suffix = kind.replace("_", "-")
                            let skillId = "skill-${suffix}"
                            let fixtureId = "skill-${suffix}-positive"
                            @Expect(teacherReadUtf8File("${root}/exports/${candidate.candidateSetId}/" +
                                "skills/${skillId}/executions/${fixtureId}/transcript.txt"),
                                "${fixtureId}  \n")
                        }
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
