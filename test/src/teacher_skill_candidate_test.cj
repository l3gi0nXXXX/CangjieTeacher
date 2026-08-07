package cangjie_teacher_test

import std.unittest.testmacro.*
import std.collection.*
import std.fs.*
import std.time.*
import cangjie_teacher.*

private let FAILURE_FIXTURE = "{\"schemaVersion\":\"ckb-completion-failure-v1\",\"runId\":\"recert-fixture-run\",\"caseId\":\"CJ-HUMANEVAL-007\",\"datasetVersion\":\"cangjie-humaneval-164-v1\",\"generationProtocol\":\"completion-only-v1\",\"completionHash\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"baseStatus\":\"failed\",\"plusStatus\":\"failed\",\"failureKind\":\"test_failure\",\"failureObservation\":\"student_completion_test_failed 中文😀\",\"assetLineage\":\"independent\",\"evidenceHash\":\"f08453591302a46c4acc04c43d9bdf456679fae27b354bbca7ebecb194c1e773\"}"
private let CLASSIFICATION_FIXTURE = "{\"schemaVersion\":\"ckb-completion-failure-classification-v1\",\"failureEvidenceHash\":\"f08453591302a46c4acc04c43d9bdf456679fae27b354bbca7ebecb194c1e773\",\"gapKind\":\"mixed_gap\",\"knowledgeEligible\":true,\"skillEligible\":true,\"classificationEvidenceHash\":\"1ff85ffec78c69504a2f98146daebb75557d340b6366e92875c4c1acd4b44a16\"}"

private func failureAssetFixture(gapKind: String, knowledge: Bool, skill: Bool, rules: Bool,
    reason: String): String {
    let evidence = "{\"schemaVersion\":\"ckb-completion-failure-classification-v2\"," +
        "\"failureEvidenceHash\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"," +
        "\"gapKind\":\"${gapKind}\",\"knowledgeEligible\":${knowledge}," +
        "\"skillEligible\":${skill},\"rulesEligible\":${rules},\"classificationReasonCode\":\"${reason}\"}"
    let runes = evidence.toRuneArray()
    String(runes[..runes.size - 1]) +
        ",\"classificationEvidenceHash\":\"${teacherStableHash(evidence)}\"}"
}

private func skillFixtures(): Array<TeacherSkillFixture> {
    [
        TeacherSkillFixture("positive-basic", "Review a typed accumulator.", "positive_passed", kind: "positive"),
        TeacherSkillFixture("negative-unsafe", "Reject an unchecked index.", "negative_rejected", kind: "negative"),
        TeacherSkillFixture("boundary-unicode", "Review 中文😀 Rune boundaries.", "boundary_passed", kind: "boundary"),
        TeacherSkillFixture("generic-rune-review", "Review a Unicode label formatter.", "generalization_passed",
            fixturePath: "tests/generalization/generic-rune-review.json"),
        TeacherSkillFixture("generic-empty-review", "Review an empty collection reducer.", "generalization_passed"),
        TeacherSkillFixture("generic-overflow-review", "Review a bounded counter.", "generalization_passed")
    ]
}

private func skillCandidate(): TeacherSkillCandidate {
    buildTeacherSkillCandidate(parseTeacherCompletionFailureInput(FAILURE_FIXTURE),
        parseTeacherFailureClassification(CLASSIFICATION_FIXTURE), "static-boundary-review", "1.0.0",
        "Static boundary review", "Before emitting code, enumerate input boundaries and verify one invariant for each.",
        "general_engineering", "One-shot statically typed implementation tasks.",
        buildTeacherSkillTestBundle(skillFixtures()), candidateOrigin: "independent_seed")
}

private func artifactCandidate(): TeacherSkillCandidate { skillCandidate() }

private let FAILURE_ASSET_FIXTURE_ROOT = "fixtures/completion_failure_assets"

private func failureAssetFixtureLines(name: String): Array<String> {
    let out = ArrayList<String>()
    for (line in teacherReadUtf8File("${FAILURE_ASSET_FIXTURE_ROOT}/${name}").split("\n")) {
        if (!line.isEmpty()) { out.add(line) }
    }
    out.toArray()
}

private func failureAssetHexNibble(value: Rune): UInt8 {
    match (value) {
        case r'0' => UInt8(0); case r'1' => UInt8(1); case r'2' => UInt8(2); case r'3' => UInt8(3)
        case r'4' => UInt8(4); case r'5' => UInt8(5); case r'6' => UInt8(6); case r'7' => UInt8(7)
        case r'8' => UInt8(8); case r'9' => UInt8(9); case r'a' => UInt8(10); case r'b' => UInt8(11)
        case r'c' => UInt8(12); case r'd' => UInt8(13); case r'e' => UInt8(14); case r'f' => UInt8(15)
        case _ => throw IllegalArgumentException("fixture_hex_invalid")
    }
}

private func failureAssetHexBytes(raw: String): Array<UInt8> {
    let hex = raw.trimAscii().toRuneArray()
    if (hex.size == 0 || hex.size % 2 != 0) { throw IllegalArgumentException("fixture_hex_invalid") }
    let out = ArrayList<UInt8>()
    for (i in 0..hex.size: 2) {
        out.add(failureAssetHexNibble(hex[i]) * UInt8(16) + failureAssetHexNibble(hex[i + 1]))
    }
    out.toArray()
}

@Test
public class TeacherSkillCandidateTest {
    // S0-UT-01: v2 parses and seals to its exact canonical bytes.
    @TestCase public func failureAssetV2CanonicalBytesMatchAcrossRepositories(): Unit {
        let fixture = teacherReadUtf8File("${FAILURE_ASSET_FIXTURE_ROOT}/classification-v2-valid.jsonl")
        @Expect(teacherStableHash(fixture), "5fa4aa906f5a147d220372cbb67533565ac7222419bf6f7c462cc476c0a31768")
        let lines = failureAssetFixtureLines("classification-v2-valid.jsonl")
        @Expect(lines.size, 11)
        for (raw in lines) {
            let parsed = parseTeacherFailureAssetClassification(raw)
            @Expect(renderTeacherFailureAssetClassification(parsed), raw)
            @Expect(parsed.schemaVersion, "ckb-completion-failure-classification-v2")
        }
    }

    // S0-BND-01: the v1 Unicode fixture remains readable and every v2 reason boundary round-trips.
    @TestCase public func failureAssetV2BoundariesAreUtf8Safe(): Unit {
        let utf8 = teacherReadUtf8File("${FAILURE_ASSET_FIXTURE_ROOT}/completion-failure-v1-utf8.json").trimAscii()
        @Expect(parseTeacherCompletionFailureInput(utf8).failureObservation,
            "student_completion_test_failed 中文😀")
        let legacy = failureAssetFixtureLines("classification-v1-compatibility.jsonl")
        @Expect(legacy.size, 1)
        let parsedLegacy = parseTeacherFailureClassification(legacy[0])
        @Expect(parsedLegacy.knowledgeEligible, true)
        @Expect(parsedLegacy.skillEligible, true)
        let invalidBytes = failureAssetHexBytes(
            teacherReadUtf8File("${FAILURE_ASSET_FIXTURE_ROOT}/classification-invalid-utf8.hex"))
        var invalidEncoding = "not_rejected"
        try { _ = String.fromUtf8(invalidBytes) } catch (_: Exception) { invalidEncoding = "invalid_response_encoding" }
        @Expect(invalidEncoding, "invalid_response_encoding")
    }

    // S0-POS-01: the three booleans map to the exact eight output kinds.
    @TestCase public func failureAssetOutputKindsAreExact(): Unit {
        let expected = ["none", "knowledge", "skill", "rules", "knowledge_skill", "knowledge_rules",
            "skill_rules", "all", "none", "none", "none"]
        let lines = failureAssetFixtureLines("classification-v2-valid.jsonl")
        @Expect(lines.size, expected.size)
        for (i in 0..lines.size) {
            @Expect(classifyTeacherAssetOutputKind(parseTeacherFailureAssetClassification(lines[i])), expected[i])
        }
    }

    // S0-NEG-01: field, schema, eligibility, reason, hash and canonical-byte drift all fail closed.
    @TestCase public func failureAssetV2RejectsContractDrift(): Unit {
        let diagnostics = ["classification_schema_fields_invalid", "classification_schema_fields_invalid",
            "classification_schema_fields_invalid", "classification_schema_fields_invalid",
            "classification_evidence_hash_mismatch", "classification_eligibility_invalid",
            "classification_eligibility_invalid"]
        let drift = failureAssetFixtureLines("classification-v2-contract-drift.jsonl")
        @Expect(drift.size, diagnostics.size)
        for (i in 0..drift.size) {
            var actual = "not_rejected"
            try { _ = parseTeacherFailureAssetClassification(drift[i]) } catch (e: Exception) { actual = e.message }
            @Expect(actual, diagnostics[i])
        }
        var malformed = "not_rejected"
        try { _ = parseTeacherFailureAssetClassification("{malformed-json") }
        catch (e: Exception) { malformed = e.message }
        @Expect(malformed, "malformed_json")
    }

    // P2-UT-01 / P6-UT-01 / L2: exact bytes and hashes are shared with CKB's frozen fixture.
    @TestCase public func frozenFailureFixtureAndSkillExportAreDeterministic(): Unit {
        let input = parseTeacherCompletionFailureInput(FAILURE_FIXTURE)
        let classification = parseTeacherFailureClassification(CLASSIFICATION_FIXTURE)
        @Expect(input.evidenceHash, "f08453591302a46c4acc04c43d9bdf456679fae27b354bbca7ebecb194c1e773")
        @Expect(classification.classificationEvidenceHash, "1ff85ffec78c69504a2f98146daebb75557d340b6366e92875c4c1acd4b44a16")
        @Expect(renderTeacherCompletionFailureInput(input), FAILURE_FIXTURE)
        @Expect(renderTeacherFailureClassification(classification), CLASSIFICATION_FIXTURE)
        @Expect(classifyTeacherOutputKind(input, classification), "mixed")
        let first = renderCandidateSkillExport(skillCandidate())
        let second = renderCandidateSkillExport(skillCandidate())
        @Expect(first, second)
        @Expect(first.contains("name: static-boundary-review"), true)
        @Expect(skillCandidate().tests.fixtures.size, 6)
    }

    // P2-POS-01 / P6-POS-01: one Skill proves generalization on three unrelated non-benchmark tasks.
    @TestCase public func threeIndependentFixturesProvideGeneralizationEvidence(): Unit {
        let candidate = skillCandidate()
        @Expect(validateSkillGeneralizationEvidence(candidate), true)
        @Expect(candidate.tests.fixtures[3].sourceClass, "non_humaneval_experiment")
        @Expect(candidate.tests.fixtures[4].sourceClass, "non_humaneval_experiment")
        @Expect(candidate.tests.fixtures[5].sourceClass, "non_humaneval_experiment")
    }

    // P2-BND-01 / P2-NEG-01 / P6-BND-01: strict JSON, Unicode, size, eligibility and hash fail closed.
    @TestCase public func failureSchemaRejectsEveryContractDrift(): Unit {
        for (raw in [
            FAILURE_FIXTURE.replace("\"runId\":", "\"unknown\":\"x\",\"runId\":"),
            FAILURE_FIXTURE.replace("\"runId\":", "\"runId\":\"duplicate\",\"runId\":"),
            FAILURE_FIXTURE.replace("test_failure", "other_failure"),
            FAILURE_FIXTURE.replace("student_completion_test_failed 中文😀", "Authorization token=secret /Users/private"),
            FAILURE_FIXTURE.replace("student_completion_test_failed 中文😀", String(Array<Rune>(513, repeat: r'界'))),
            FAILURE_FIXTURE.replace("f08453591302a46c4acc04c43d9bdf456679fae27b354bbca7ebecb194c1e773", String(Array<Rune>(64, repeat: r'0'))),
            " ${FAILURE_FIXTURE}",
            "{malformed-json"
        ]) {
            var rejected = false
            try { _ = parseTeacherCompletionFailureInput(raw) } catch (_: Exception) { rejected = true }
            @Expect(rejected, true)
        }
        var classificationRejected = false
        try { _ = parseTeacherFailureClassification(CLASSIFICATION_FIXTURE.replace("\"skillEligible\":true", "\"skillEligible\":false")) }
        catch (_: Exception) { classificationRejected = true }
        @Expect(classificationRejected, true)
        var insufficient = false
        try { _ = buildTeacherSkillTestBundle(skillFixtures()[..2]) } catch (_: Exception) { insufficient = true }
        @Expect(insufficient, true)

        let path = "/tmp/teacher-skill-invalid-utf8-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            File.writeTo(Path(path), [UInt8(0xff), UInt8(0xfe)])
            var invalidEncoding = false
            try { _ = parseTeacherCompletionFailureInput(teacherReadUtf8File(path)) }
            catch (e: Exception) { invalidEncoding = e.message == "invalid_response_encoding" }
            @Expect(invalidEncoding, true)
        } finally { try { remove(Path(path)) } catch (_: Exception) {} }
    }

    // P6-NEG-01: P5-derived candidates can never inherit an independent input lineage.
    @TestCase public func p6CandidateAlwaysUsesDerivedLineage(): Unit {
        let input = parseTeacherCompletionFailureInput(FAILURE_FIXTURE)
        let classification = parseTeacherFailureClassification(CLASSIFICATION_FIXTURE)
        let candidate = buildTeacherSkillCandidate(input, classification, "derived-review", "1.0.0",
            "Derived review", "Check a reusable static invariant.", "teacher_derived",
            "Generic one-shot code generation.", buildTeacherSkillTestBundle(skillFixtures()),
            candidateOrigin: "p6_failure_derived")
        @Expect(input.assetLineage, "independent")
        @Expect(candidate.lineage, "humaneval_164_derived")
    }

    // P2/P6 artifact contract preview; the finalized test also compares the checked-in shared fixture.
    @TestCase public func candidateDirectoryExportIsDeterministicAndImmutable(): Unit {
        let root = "/tmp/teacher-skill-artifact-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        let fixtureRoot = "fixtures/teacher_skill_candidate/static-boundary-review"
        try { if (exists(Path(root))) { remove(Path(root), recursive: true) } } catch (_: Exception) {}
        try {
            let candidate = artifactCandidate()
            let first = exportTeacherSkillCandidateDirectory(candidate, root)
            let exported = "${root}/${candidate.skillId}"
            let firstHash = teacherDirectoryHash(exported)
            let second = exportTeacherSkillCandidateDirectory(candidate, root)
            @Expect(first, second)
            @Expect(teacherDirectoryHash(exported), firstHash)
            @Expect(teacherDirectoryHash(exported), teacherDirectoryHash(fixtureRoot))
            @Expect(teacherReadUtf8File("${exported}/candidate-manifest.json").trimAscii(), first)
            let manifest = teacherReadUtf8File("${exported}/candidate-manifest.json")
            let bundle = teacherReadUtf8File("${exported}/test-bundle.json")
            @Expect(bundle.contains("\"generalizationCount\":3"), true)
            @Expect(bundle.contains("\"testsTreeHash\":\"sha256:865dfd575b715f4c7d272732f1a50a2aae8b5cb98902ee60db4b6ae225b314bf\""), true)
            @Expect(bundle.contains("\"evidenceHash\":\"sha256:7d7e6b68af9137b502f8e122777a51fbe54960d313f8afba36b029e9b96ed5c1\""), true)
            @Expect(manifest.contains("\"testEvidenceHash\":\"sha256:7d7e6b68af9137b502f8e122777a51fbe54960d313f8afba36b029e9b96ed5c1\""), true)
            @Expect(manifest.contains("\"candidateContentHash\":\"sha256:7a7fa5b2c6d23fcf7eea67eef0fd9de26fe61f7c6f4e6e707e33e2fbb4dbaed0\""), true)
            @Expect(manifest.contains("\"artifactHash\":\"sha256:f16d7384e707d6848c319522aff1cea14ed90cb46db97f1fccc1ffdee8bcc204\""), true)
            @Expect(teacherStableHash(renderTeacherSkillTestBundle(candidate)), "b23c9adb1aa4d50440f90229593f8067aefd3cc500b71b646407b7a7570af801")
            @Expect(teacherStableHash("positive_passed"), "3566b5d7a7e823cc316d2d0ccf5954379e41003923dcb4bbb89f646253bd382a")
            @Expect(teacherStableHash("negative_rejected"), "d627381310f1436df50ec707fa89c3daf0090053fa872178e3b763657b895752")
            @Expect(teacherStableHash("boundary_passed"), "63a456c889c8f371c99e9b2c3dd016595e601f945cd0e2294e2177d5611e16d9")
            @Expect(teacherStableHash("generalization_passed"), "2617ef907ebb279f115e6db214b0c59f2905177744a8a22f9885298d9a02c37a")
            for ((path, hash) in [
                ("SKILL.md", "a336604425fd37b5100fb2ea74ca67d2226093121b94e240b124d40d6d639eb5"),
                ("candidate-manifest.json", "63eb919dfa120517082434d051c4f64378614db6050d24f09ccef3108f819d1a"),
                ("test-bundle.json", "9e2bba43b6b673ed2ec2029a7cd2ab1fdddfcba04d081a6ea4ff60939583b90b"),
                ("tests/boundary-unicode.txt", "0989f52ab4661c764eff46055c828bca6afd3f95bcef0b1989418b10609ecf71"),
                ("tests/generalization/generic-rune-review.json", "fb56b133c1c631186f1216e3cc74774a7b540ce255bb6ad3656e0c8f97900d50"),
                ("tests/generic-empty-review.txt", "676e8f7e0a65c9ecbad48a9edcb82ed854f3a039657b22416f7f1a6afb78e7f5"),
                ("tests/generic-overflow-review.txt", "0ea8d1537845a78bd155b9c973a12467174d4e702ada94c6316b9ba3ee7c77c6"),
                ("tests/negative-unsafe.txt", "70e097c1e120eb4d9def8f6b6f09af32e07d526df7843ee0f5ffde373516eb9f"),
                ("tests/positive-basic.txt", "222a1330d9adb21efc65792f068f82872144190341531444e91492c2369d1e27")
            ]) { @Expect(teacherStableHash(teacherReadUtf8File("${fixtureRoot}/${path}")), hash) }
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

    @TestCase public func candidateDirectoryRejectsTamperingUnsafePathsAndSymlinks(): Unit {
        var traversalRejected = false
        try { _ = buildTeacherSkillTestBundle([
            TeacherSkillFixture("p", "p", "passed", kind: "positive"),
            TeacherSkillFixture("n", "n", "passed", kind: "negative"),
            TeacherSkillFixture("b", "b", "passed", kind: "boundary"),
            TeacherSkillFixture("g1", "g1", "passed"), TeacherSkillFixture("g2", "g2", "passed"),
            TeacherSkillFixture("g3", "g3", "passed", fixturePath: "tests/../escape")])
        } catch (_: Exception) { traversalRejected = true }
        @Expect(traversalRejected, true)

        let candidate = artifactCandidate()
        let mismatch = TeacherSkillCandidate(candidate.skillId, candidate.version, candidate.title,
            candidate.procedure, candidate.sourceCategory, candidate.applicability,
            "humaneval_164_derived", candidate.contentHash, candidate.tests)
        var lineageRejected = false
        try { _ = renderTeacherSkillCandidateManifest(mismatch) } catch (_: Exception) { lineageRejected = true }
        @Expect(lineageRejected, true)

        let secretFixtures = skillFixtures()
        secretFixtures[0] = TeacherSkillFixture("positive-basic", "Review.", "token=secret", kind: "positive")
        var secretRejected = false
        try { _ = buildTeacherSkillCandidate(parseTeacherCompletionFailureInput(FAILURE_FIXTURE),
            parseTeacherFailureClassification(CLASSIFICATION_FIXTURE), "secret-review", "1.0.0", "Review",
            "Review safely.", "general_engineering", "Generic.", buildTeacherSkillTestBundle(secretFixtures),
            candidateOrigin: "independent_seed") } catch (_: Exception) { secretRejected = true }
        @Expect(secretRejected, true)

        let root = "/tmp/teacher-skill-negative-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            _ = exportTeacherSkillCandidateDirectory(candidate, root)
            let target = "${root}/${candidate.skillId}"
            File.writeTo(Path("${target}/candidate-manifest.json"), "{malformed".toArray())
            var malformedRejected = false
            try { _ = exportTeacherSkillCandidateDirectory(candidate, root) } catch (_: Exception) { malformedRejected = true }
            @Expect(malformedRejected, true)

            for (polluted in [
                renderTeacherSkillCandidateManifest(candidate).replace("{", "{\"unknown\":true,"),
                renderTeacherSkillCandidateManifest(candidate).replace("\"id\":", "\"id\":\"duplicate\",\"id\":")
            ]) {
                remove(Path(target), recursive: true)
                _ = exportTeacherSkillCandidateDirectory(candidate, root)
                File.writeTo(Path("${target}/candidate-manifest.json"), (polluted + "\n").toArray())
                var schemaRejected = false
                try { _ = exportTeacherSkillCandidateDirectory(candidate, root) } catch (_: Exception) { schemaRejected = true }
                @Expect(schemaRejected, true)
            }
            for (pollutedBundle in [
                renderTeacherSkillTestBundle(candidate).replace("{", "{\"unknown\":true,"),
                renderTeacherSkillTestBundle(candidate).replace("\"candidateId\":", "\"candidateId\":\"duplicate\",\"candidateId\":")
            ]) {
                remove(Path(target), recursive: true)
                _ = exportTeacherSkillCandidateDirectory(candidate, root)
                File.writeTo(Path("${target}/test-bundle.json"), (pollutedBundle + "\n").toArray())
                var bundleRejected = false
                try { _ = exportTeacherSkillCandidateDirectory(candidate, root) } catch (_: Exception) { bundleRejected = true }
                @Expect(bundleRejected, true)
            }

            remove(Path(target), recursive: true)
            _ = exportTeacherSkillCandidateDirectory(candidate, root)
            let nested = "${target}/tests/generalization/generic-rune-review.json"
            File.writeTo(Path(nested), [UInt8(0xff), UInt8(0xfe)])
            var encodingRejected = false
            try { _ = exportTeacherSkillCandidateDirectory(candidate, root) } catch (_: Exception) { encodingRejected = true }
            @Expect(encodingRejected, true)

            remove(Path(target), recursive: true)
            _ = exportTeacherSkillCandidateDirectory(candidate, root)
            File.writeTo(Path(nested), "{\"schemaVersion\":\"cangjie-teacher-skill-fixture-v1\",\"task\":\"Review a Unicode label formatter.\",\"resultEvidence\":\"tampered\"}\n".toArray())
            var resultRejected = false
            try { _ = exportTeacherSkillCandidateDirectory(candidate, root) } catch (_: Exception) { resultRejected = true }
            @Expect(resultRejected, true)

            remove(Path(nested))
            SymbolicLink.create(Path(nested), to: Path("${target}/SKILL.md"))
            var symlinkRejected = false
            try { _ = exportTeacherSkillCandidateDirectory(candidate, root) } catch (_: Exception) { symlinkRejected = true }
            @Expect(symlinkRejected, true)
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }
}
