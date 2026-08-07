package cangjie_teacher

import std.fs.*
import std.posix.*
import std.time.*
import std.collection.*
import std.convert.Parsable
import stdx.encoding.json.*

public class TeacherCliOptions {
    public var command = ""
    public var root = ""
    public var manifest = ""
    public var checksum = ""
    public var starterRoot = ""
    public var testsRoot = ""
    public var codex = "codex"
    public var model = "gpt-5.6"
    public var runId = ""
    public var timeoutMillis: Int64 = 600000
    public var localOnly = false
    public var repositoryRoot = ""
    public var caseId = ""
    public var authorityGap = ""
    public var outputRoot = ""
    public var sourceExport = ""
    public var extractor = "codex"
    public var sourceManifest = ""
    public var failurePath = ""
    public var expectedHash = ""
    public var baseContextManifest = ""
    public var output = ""
    public var candidateSetHash = ""
    public var decision = ""
    public var reviewer = ""
    public var reason = ""
    public var approvedAtUtc = ""
    public var rulesContent = ""
    public var skillsContent = ""
    public var knowledgeContent = ""
    public var knowledgeVersion = ""
    public var json = false
    public var scaffoldContract = false
    public var fixtureRoot = ""
    public var baseContextHash = ""
    public init() {}
}

public func parseTeacherCliOptions(args: Array<String>): TeacherCliOptions {
    let out = TeacherCliOptions()
    let seen = HashSet<String>()
    var i: Int64 = 0
    while (i < args.size) {
        if (args[i] == "--help") { out.command = "help"; i += 1; continue }
        if (!args[i].startsWith("--") && out.command.isEmpty()) { out.command = args[i]; i += 1; continue }
        if (args[i] == "--local-only") { if (seen.contains(args[i])) { throw IllegalArgumentException("duplicate_cli_option") }; seen.add(args[i]); out.localOnly = true; i += 1; continue }
        if (args[i] == "--json") { if (seen.contains(args[i])) { throw IllegalArgumentException("duplicate_cli_option") }; seen.add(args[i]); out.json = true; i += 1; continue }
        if (args[i] == "--scaffold-contract") { if (seen.contains(args[i])) { throw IllegalArgumentException("duplicate_cli_option") }; seen.add(args[i]); out.scaffoldContract = true; i += 1; continue }
        if (i + 1 >= args.size) { throw IllegalArgumentException("missing_cli_option_value") }
        if (seen.contains(args[i])) { throw IllegalArgumentException("duplicate_cli_option") }
        seen.add(args[i])
        let value = args[i + 1]
        match (args[i]) {
            case "--root" => out.root = value
            case "--manifest" => out.manifest = value
            case "--checksum" => out.checksum = value
            case "--starter-root" => out.starterRoot = value
            case "--tests-root" => out.testsRoot = value
            case "--codex" => out.codex = value
            case "--model" => out.model = value
            case "--run-id" => out.runId = value
            case "--repo-root" => out.repositoryRoot = value
            case "--case-id" => out.caseId = value
            case "--timeout-ms" => out.timeoutMillis = try { Int64.parse(value) } catch (_: Exception) { throw IllegalArgumentException("invalid_timeout") }
            case "--authority-gap" => out.authorityGap = value
            case "--output-root" => out.outputRoot = value
            case "--source-export" => out.sourceExport = value
            case "--extractor" => out.extractor = value
            case "--source-manifest" => out.sourceManifest = value
            case "--failure" => out.failurePath = value
            case "--expected-hash" => out.expectedHash = value
            case "--base-context-manifest" => out.baseContextManifest = value
            case "--output" => out.output = value
            case "--candidate-set-hash" => out.candidateSetHash = value
            case "--decision" => out.decision = value
            case "--reviewer" => out.reviewer = value
            case "--reason" => out.reason = value
            case "--approved-at-utc" => out.approvedAtUtc = value
            case "--rules-content" => out.rulesContent = value
            case "--skills-content" => out.skillsContent = value
            case "--knowledge-content" => out.knowledgeContent = value
            case "--knowledge-version" => out.knowledgeVersion = value
            case "--fixture-root" => out.fixtureRoot = value
            case "--base-context-hash" => out.baseContextHash = value
            case _ => throw IllegalArgumentException("unknown_cli_option")
        }
        i += 2
    }
    out
}

private func teacherCliJsonString(object: JsonObject, name: String): String {
    match (object.get(name)) { case Some(value) => value.asString().getValue(); case None => "" }
}

private func teacherCliSafeReviewText(value: String): Bool {
    if (value.isEmpty() || value.toArray().size > 1024) { return false }
    let lower = value.toAsciiLower()
    !lower.contains("token=") && !lower.contains("authorization") && !lower.contains("/users/") &&
        !lower.contains("/private/")
}

private func teacherCliJsonEscape(value: String): String {
    value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
        .replace("\r", "\\r").replace("\t", "\\t")
}

private func runTeacherContextSeedBuild(options: TeacherCliOptions): Int64 {
    if (options.sourceManifest.isEmpty() || options.rulesContent.isEmpty() ||
        options.skillsContent.isEmpty() || options.knowledgeContent.isEmpty() ||
        options.knowledgeVersion.isEmpty() || options.outputRoot.isEmpty() ||
        options.baseContextManifest != "none" || options.runId.isEmpty()) {
        throw IllegalArgumentException("missing_required_cli_option")
    }
    let source = parseTeacherContextSourceManifest(teacherReadUtf8File(options.sourceManifest).trimAscii())
    let candidate = buildTeacherIndependentContextSeed(source, options.runId,
        teacherReadUtf8File(options.rulesContent), teacherReadUtf8File(options.skillsContent),
        teacherReadUtf8File(options.knowledgeContent), options.knowledgeVersion)
    _ = exportTeacherContextCandidateSet(candidate, options.outputRoot)
    if (options.json) { println("{\"ok\":true,\"candidateSetHash\":\"${candidate.candidateSetHash}\"}") }
    else { println("context seed built candidateSet=${candidate.candidateSetId} validation=scaffold_contract") }
    0
}

private func runTeacherFailureAssetsApprove(options: TeacherCliOptions): Int64 {
    if (options.sourceExport.isEmpty() || options.output.isEmpty() || options.candidateSetHash.isEmpty() ||
        !["approve", "reject"].contains(options.decision) || !teacherCliSafeReviewText(options.reviewer) ||
        !teacherCliSafeReviewText(options.reason) || options.approvedAtUtc.isEmpty()) {
        throw IllegalArgumentException("missing_required_cli_option")
    }
    let manifestPath = Path(options.sourceExport).join("candidate-set-manifest.json")
    let raw = teacherReadUtf8File(manifestPath.toString()).trimAscii()
    let object = try { JsonValue.fromStr(raw).asObject() } catch (_: Exception) {
        throw IllegalArgumentException("candidate_set_schema_invalid")
    }
    let actual = teacherCliJsonString(object, "candidateSetHash")
    let marker = ",\"candidateSetHash\":\""
    let parts = raw.split(marker)
    if (object.getFields().size != 20 || parts.size != 2 || !parts[1].endsWith("\"}") ||
        actual != options.candidateSetHash ||
        actual != "sha256:${teacherStableHash(parts[0] + "}")}" ||
        raw != parts[0] + marker + actual + "\"}") {
        throw IllegalArgumentException("candidate_approval_hash_mismatch")
    }
    let approval = "{\"schemaVersion\":\"teacher-student-context-approval-v1\"," +
        "\"candidateSetHash\":\"${actual}\",\"rulesHash\":\"${teacherCliJsonString(object, "rulesHash")}\"," +
        "\"skillsHash\":\"${teacherCliJsonString(object, "skillsHash")}\"," +
        "\"knowledgeCandidateHash\":\"${teacherCliJsonString(object, "knowledgeCandidateHash")}\"," +
        "\"decision\":\"${options.decision}\",\"reviewer\":\"${teacherCliJsonEscape(options.reviewer)}\"," +
        "\"reason\":\"${teacherCliJsonEscape(options.reason)}\",\"approvedAtUtc\":\"${teacherCliJsonEscape(options.approvedAtUtc)}\"}"
    if (exists(Path(options.output))) { throw IllegalArgumentException("candidate_approval_hash_mismatch") }
    _ = teacherAtomicWrite(options.output, approval + "\n")
    if (options.json) { println("{\"ok\":true,\"decision\":\"${options.decision}\"}") }
    else { println("candidate review recorded decision=${options.decision}") }
    0
}

private class TeacherCliScaffoldGenerator <: TeacherFailureAssetGenerator {
    let root: String
    init(root: String) { this.root = root }
    public func generate(request: TeacherFailureAssetGenerationRequest): String {
        let expected = teacherReadUtf8File("${root}/generation-request-${request.lane}.json").trimAscii()
        if (expected != renderTeacherFailureAssetGenerationRequest(request)) {
            throw IllegalArgumentException("candidate_generation_invalid")
        }
        teacherReadUtf8File("${root}/proposal-${request.lane}.json").trimAscii()
    }
}

private class TeacherCliBaseContext {
    let compositeHash: String; let skillsHash: String; let skillCount: Int64; let skillLineage: String
    let knowledgeHash: String; let knowledgeVersion: String; let knowledgeLineage: String
    init(compositeHash: String, skillsHash: String, skillCount: Int64, skillLineage: String,
        knowledgeHash: String, knowledgeVersion: String, knowledgeLineage: String) {
        this.compositeHash = compositeHash; this.skillsHash = skillsHash; this.skillCount = skillCount
        this.skillLineage = skillLineage; this.knowledgeHash = knowledgeHash
        this.knowledgeVersion = knowledgeVersion; this.knowledgeLineage = knowledgeLineage
    }
}

private func teacherCliJsonInt(object: JsonObject, name: String): Int64 {
    match (object.get(name)) { case Some(value) => value.asInt().getValue(); case None => Int64(-1) }
}

private func teacherCliJsonBool(object: JsonObject, name: String): Bool {
    match (object.get(name)) { case Some(value) => value.asBool().getValue(); case None => false }
}

private func teacherCliSha(value: String): Bool {
    if (!value.startsWith("sha256:") || value.toRuneArray().size != 71) { return false }
    for (rune in value.toRuneArray()[7..71]) {
        if (!((rune >= r'0' && rune <= r'9') || (rune >= r'a' && rune <= r'f'))) { return false }
    }
    true
}

private func teacherCliScaffoldSafe(value: String): Bool {
    if (value.isEmpty() || value.toArray().size > 262144) { return false }
    let lower = value.toAsciiLower()
    for (marker in ["cj-humaneval-", "humaneval_164_derived", "/users/", "/home/", "/private/",
        "authorization", "token=", "password=", "hidden_test", "reference solution", "expectedoutput"]) {
        if (lower.contains(marker)) { return false }
    }
    true
}

private func teacherCliLoadBaseContext(path: String, expectedHash: String): TeacherCliBaseContext {
    let rawFile = teacherReadUtf8File(path)
    if (!teacherCliSha(expectedHash) || "sha256:${teacherStableHash(rawFile)}" != expectedHash) {
        throw IllegalArgumentException("candidate_base_composite_mismatch")
    }
    try {
        let raw = rawFile.trimAscii(); let object = JsonValue.fromStr(raw).asObject()
        if (teacherCliJsonString(object, "schemaVersion") != "ckb-student-context-bundle-v1" ||
            teacherCliJsonString(object, "aggregateAssetLineage") != "independent") {
            throw IllegalArgumentException("candidate_base_composite_mismatch")
        }
        let value = TeacherCliBaseContext(teacherCliJsonString(object, "compositeHash"),
            teacherCliJsonString(object, "skillBundleHash"), teacherCliJsonInt(object, "skillCount"),
            teacherCliJsonString(object, "skillAssetLineage"),
            teacherCliJsonString(object, "knowledgeContentHash"), teacherCliJsonString(object, "knowledgeVersion"),
            teacherCliJsonString(object, "knowledgeAssetLineage"))
        if (!teacherCliSha(value.compositeHash) || !teacherCliSha(value.skillsHash) || value.skillCount < 0 ||
            !teacherCliSha(value.knowledgeHash) || value.knowledgeVersion.isEmpty() ||
            value.skillLineage != "independent" || value.knowledgeLineage != "independent") {
            throw IllegalArgumentException("candidate_base_composite_mismatch")
        }
        value
    } catch (e: IllegalArgumentException) { throw e }
    catch (_: Exception) { throw IllegalArgumentException("candidate_base_composite_mismatch") }
}

private func teacherCliFixtureExecutionCanonical(object: JsonObject): String {
    "{\"schemaVersion\":\"${teacherCliJsonString(object, "schemaVersion")}\"," +
        "\"fixtureId\":\"${teacherCliJsonString(object, "fixtureId")}\",\"kind\":\"${teacherCliJsonString(object, "kind")}\"," +
        "\"sourceClass\":\"${teacherCliJsonString(object, "sourceClass")}\",\"fixtureHash\":\"${teacherCliJsonString(object, "fixtureHash")}\"," +
        "\"executorKind\":\"${teacherCliJsonString(object, "executorKind")}\",\"providerIdentityHash\":\"${teacherCliJsonString(object, "providerIdentityHash")}\"," +
        "\"modelVersion\":\"${teacherCliJsonString(object, "modelVersion")}\",\"expectedEvidenceHash\":\"${teacherCliJsonString(object, "expectedEvidenceHash")}\"," +
        "\"actualEvidenceHash\":\"${teacherCliJsonString(object, "actualEvidenceHash")}\",\"transcriptHash\":\"${teacherCliJsonString(object, "transcriptHash")}\"," +
        "\"exitCode\":${teacherCliJsonInt(object, "exitCode")},\"passed\":${teacherCliJsonBool(object, "passed")}}"
}

public func renderTeacherFailureAssetsBuildOutput(candidateSetId: String,
    candidateSetHash: String, json: Bool): String {
    if (json) { return "{\"ok\":true,\"candidateSetHash\":\"${candidateSetHash}\"}" }
    "failure assets built candidateSet=${candidateSetId} validation=scaffold_contract changedLane=rules"
}

private func teacherCliLoadScaffoldFixtureExecutions(path: String): TeacherRuleTestBundle {
    let executions = ArrayList<TeacherAssetFixtureExecution>(); let kinds = HashSet<String>()
    for (line in teacherReadUtf8File(path).split("\n")) {
        if (line.isEmpty()) { continue }
        try {
            let object = JsonValue.fromStr(line).asObject(); let kind = teacherCliJsonString(object, "kind")
            let expected = teacherCliJsonString(object, "expectedEvidenceHash")
            if (object.getFields().size != 13 || line != teacherCliFixtureExecutionCanonical(object) ||
                teacherCliJsonString(object, "schemaVersion") != "teacher-candidate-fixture-execution-v1" ||
                !["positive", "negative", "boundary", "generalization"].contains(kind) || kinds.contains(kind) ||
                teacherCliJsonString(object, "sourceClass") != "non_humaneval_experiment" ||
                teacherCliJsonString(object, "executorKind") != "fake_contract" ||
                teacherCliJsonString(object, "modelVersion") != "fake-scaffold-v1" ||
                teacherCliJsonInt(object, "exitCode") != 0 || !teacherCliJsonBool(object, "passed") ||
                expected != teacherCliJsonString(object, "actualEvidenceHash") ||
                !teacherCliSha(teacherCliJsonString(object, "fixtureHash")) || !teacherCliSha(expected) ||
                !teacherCliSha(teacherCliJsonString(object, "providerIdentityHash")) ||
                !teacherCliSha(teacherCliJsonString(object, "transcriptHash"))) {
                throw IllegalArgumentException("candidate_test_evidence_invalid")
            }
            kinds.add(kind)
            let fixture = TeacherAssetFixture(teacherCliJsonString(object, "fixtureId"), kind,
                "non_humaneval_experiment", "scaffold fixture", "scaffold evidence")
            executions.add(TeacherAssetFixtureExecution(fixture, teacherCliJsonString(object, "fixtureHash"),
                "fake_contract", teacherCliJsonString(object, "providerIdentityHash"), "fake-scaffold-v1",
                "", teacherCliJsonString(object, "transcriptHash"), 0, true))
        } catch (e: IllegalArgumentException) { throw e }
        catch (_: Exception) { throw IllegalArgumentException("candidate_test_evidence_invalid") }
    }
    if (executions.size != 4) { throw IllegalArgumentException("candidate_test_evidence_invalid") }
    TeacherRuleTestBundle(executions.toArray())
}

private func runTeacherScaffoldFailureAssetsBuild(options: TeacherCliOptions): Int64 {
    if (!options.scaffoldContract || options.fixtureRoot.isEmpty() || options.failurePath.isEmpty() ||
        options.expectedHash.isEmpty() || options.sourceManifest.isEmpty() ||
        options.baseContextManifest.isEmpty() || options.baseContextHash.isEmpty() ||
        options.outputRoot.isEmpty() || options.runId.isEmpty()) {
        throw IllegalArgumentException("missing_required_cli_option")
    }
    let failureRaw = teacherReadUtf8File(options.failurePath)
    if (!teacherCliScaffoldSafe(failureRaw) || teacherStableHash(failureRaw) != options.expectedHash) {
        throw IllegalArgumentException("candidate_generation_invalid")
    }
    let fixtureMaterial = teacherJoin([
        teacherReadUtf8File("${options.fixtureRoot}/classification-a.json"),
        teacherReadUtf8File("${options.fixtureRoot}/classification-b.json"),
        teacherReadUtf8File("${options.fixtureRoot}/gap-description.txt"),
        teacherReadUtf8File("${options.fixtureRoot}/generation-request-rules.json"),
        teacherReadUtf8File("${options.fixtureRoot}/proposal-rules.json"),
        teacherReadUtf8File("${options.fixtureRoot}/fixture-executions.jsonl")], "\n")
    if (!teacherCliScaffoldSafe(fixtureMaterial)) { throw IllegalArgumentException("candidate_generation_invalid") }
    let source = parseTeacherContextSourceManifest(teacherReadUtf8File(options.sourceManifest).trimAscii())
    if (source.sourceKind != "completion_failures" || source.sourceHashes.size != 1 ||
        source.sourceHashes[0] != "sha256:${options.expectedHash}") {
        throw IllegalArgumentException("candidate_lane_lineage_invalid")
    }
    let firstRaw = teacherReadUtf8File("${options.fixtureRoot}/classification-a.json").trimAscii()
    let secondRaw = teacherReadUtf8File("${options.fixtureRoot}/classification-b.json").trimAscii()
    let first = parseTeacherFailureAssetClassifierResponse(firstRaw)
    let second = parseTeacherFailureAssetClassifierResponse(secondRaw)
    if (first.failureEvidenceHash != options.expectedHash || second.failureEvidenceHash != options.expectedHash ||
        first.gapKind != "rules_gap") { throw IllegalArgumentException("classification_requires_review") }
    let syntheticFailure = TeacherCompletionFailureInput("scaffold-contract", "synthetic-non-humaneval",
        "synthetic-non-humaneval-v1", "completion-only-v1", options.expectedHash,
        "failed", "failed", "test_failure", "synthetic scaffold failure", "independent", options.expectedHash)
    let built = buildTeacherFailureAssets(syntheticFailure, first, second,
        teacherReadUtf8File("${options.fixtureRoot}/gap-description.txt").trimAscii(),
        TeacherCliScaffoldGenerator(options.fixtureRoot))
    if (built.proposals.size != 1 || built.proposals[0].lane != "rules") {
        throw IllegalArgumentException("candidate_generation_invalid")
    }
    let base = teacherCliLoadBaseContext(options.baseContextManifest, options.baseContextHash)
    let baseRoot = Path(options.baseContextManifest).parent
    let baseSkills = teacherReadUtf8File(baseRoot.join("student-skills.prompt.md").toString())
    let baseKnowledge = teacherReadUtf8File(baseRoot.join("knowledge-reference.json").toString())
    let tests = teacherCliLoadScaffoldFixtureExecutions("${options.fixtureRoot}/fixture-executions.jsonl")
    let proposal = built.proposals[0]
    let ruleId = "scaffold-rule-${built.classification.classificationEvidenceHash}"
    let rule = buildTeacherRuleCandidate(built.classification, ruleId, "synthetic-rune-boundary",
        proposal.title, proposal.content, proposal.trigger, proposal.scope, proposal.priority,
        "completion_failure", options.expectedHash, tests)
    let rulesMarkdown = renderTeacherAgentsMarkdown([rule])
    let ruleManifest = renderTeacherRuleCandidateManifest(rule)
    let classificationHash = "sha256:${teacherStableHash(firstRaw + "\n" + secondRaw + "\n")}"
    let candidate = buildTeacherScaffoldRuleDelta(source, options.runId, base.compositeHash,
        base.skillsHash, base.skillCount, base.skillLineage, base.knowledgeHash,
        base.knowledgeVersion, base.knowledgeLineage, rulesMarkdown, ruleManifest,
        baseSkills, baseKnowledge, classificationHash)
    _ = exportTeacherContextCandidateSet(candidate, options.outputRoot)
    println(renderTeacherFailureAssetsBuildOutput(candidate.candidateSetId,
        candidate.candidateSetHash, options.json))
    0
}

public func loadTeacherDatasetManifestFile(path: String, checksum: String): TeacherDatasetManifest {
    let text = teacherReadUtf8File(path)
    let lines = ArrayList<String>()
    for (line in text.split("\n")) { if (!line.trimAscii().isEmpty()) { lines.add(line) } }
    importTeacherDatasetManifest(lines.toArray(), checksum)
}

private class SystemTeacherClock <: TeacherClock {
    public func nowMillis(): Int64 { DateTime.now().toUnixTimeStamp().toMilliseconds() }
}

public func runTeacherBatchFromCli(options: TeacherCliOptions): Array<TeacherRunManifest> {
    if (options.root.isEmpty() || options.manifest.isEmpty() || options.checksum.isEmpty() ||
        options.starterRoot.isEmpty() || options.testsRoot.isEmpty() || options.runId.isEmpty()) {
        throw IllegalArgumentException("missing_required_cli_option")
    }
    if (options.model != "gpt-5.6-sol") { throw IllegalArgumentException("teacher_model_identity_invalid") }
    let privacyDiagnostic = prepareTeacherArtifactRoot(options.repositoryRoot, options.root, options.localOnly)
    if (!privacyDiagnostic.isEmpty()) { throw IllegalArgumentException(privacyDiagnostic) }
    let manifest = loadTeacherDatasetManifestFile(options.manifest, options.checksum)
    let lock = acquireTeacherRunLock(options.root, options.runId)
    try {
        let completedPath = "${options.root}/runs/${options.runId}/completed.manifest"
        let completed = validateCompletedTeacherRunSnapshot(
            mergeCompletedTeacherRuns([], loadCompletedTeacherRuns(completedPath)),
            manifest, options.runId, options.model)
        let process = CodexTeacherProcess(options.codex, options.model, timeoutMillis: options.timeoutMillis)
        let verifier = CjpmTeacherVerifier(options.testsRoot, timeoutMillis: options.timeoutMillis)
        let runOptions = TeacherRunOptions(options.runId, options.root, options.model, process, verifier,
            SystemTeacherClock(), repairUntilVerified: true, persistAttemptProgress: true)
        let out = ArrayList<TeacherRunManifest>()
        for (caseValue in manifest.cases) {
            if (!options.caseId.isEmpty() && caseValue.caseId != options.caseId) { continue }
            var reusable: ?TeacherRunManifest = None
            for (old in completed) {
                if (teacherCompletedRunReusable(old, caseValue, runOptions)) { reusable = Some(old) }
            }
            match (reusable) {
                case Some(old) => out.add(old)
                case None =>
                    probeTeacherTransportLease(TeacherPaths(options.root).transportLease(
                        options.runId, caseValue.caseId))
                    if (!hasTeacherAttemptEvidence(options.root, options.runId, caseValue.caseId)) {
                        _ = createTeacherCaseWorkspace(options.root, options.runId, caseValue, options.starterRoot)
                    }
                    let execution = executeTeacherCase(caseValue, runOptions)
                    let run = finalizeTeacherRun(execution.run, true)
                    out.add(run)
                    if (run.status == "complete") {
                        teacherCopyTree(TeacherPaths(options.root).workspace(options.runId, caseValue.caseId),
                            TeacherPaths(options.root).solution(caseValue.caseId))
                        _ = persistTeacherSolutionBinding(options.root, run)
                        _ = persistTeacherCompletedAttemptBinding(options.root, run, caseValue)
                    }
                    _ = persistTeacherRunArtifacts(options.root, run,
                        teacherSanitizeEvidence(execution.generationEvidence),
                        teacherSanitizeEvidence(execution.verifierEvidence))
                    let snapshot = validateCompletedTeacherRunSnapshot(
                        mergeCompletedTeacherRuns(completed, out.toArray()),
                        manifest, options.runId, options.model)
                    _ = persistCompletedTeacherRuns(completedPath, snapshot)
            }
        }
        out.toArray()
    } finally {
        releaseTeacherRunLock(lock)
    }
}

public func validateTeacherExecutionPrivacy(repositoryRoot: String, artifactRoot: String, localOnly: Bool): Bool {
    if (!localOnly || repositoryRoot.trimEnd('/').isEmpty() || artifactRoot.trimEnd('/').isEmpty()) { return false }
    let repositoryPath = Path(repositoryRoot.trimEnd('/'))
    let artifactPath = Path(artifactRoot.trimEnd('/'))
    if (!repositoryPath.isAbsolute() || !artifactPath.isAbsolute() || !exists(repositoryPath) || !exists(artifactPath)) { return false }
    if (teacherPathIsSymbolicLink(repositoryPath) || teacherPathIsSymbolicLink(artifactPath)) { return false }
    if (!FileInfo(repositoryPath).isDirectory() || !FileInfo(artifactPath).isDirectory()) { return false }
    let repo = try { canonicalize(repositoryPath).toString().trimEnd('/') } catch (_: Exception) { return false }
    let artifacts = try { canonicalize(artifactPath).toString().trimEnd('/') } catch (_: Exception) { return false }
    artifacts != repo && !artifacts.startsWith(repo + "/")
}

// Creates only the final artifact-root component after its existing parent is
// canonicalized outside the repository, then rechecks the created directory.
public func prepareTeacherArtifactRoot(repositoryRoot: String, artifactRoot: String, localOnly: Bool): String {
    if (!localOnly) { return "teacher_local_only_required" }
    let repositoryValue = repositoryRoot.trimEnd('/')
    let artifactValue = artifactRoot.trimEnd('/')
    if (repositoryValue.isEmpty()) { return "teacher_repository_root_invalid" }
    if (artifactValue.isEmpty()) { return "teacher_artifact_root_invalid" }
    let repositoryPath = Path(repositoryValue)
    let artifactPath = Path(artifactValue)
    if (!repositoryPath.isAbsolute() || !exists(repositoryPath) || teacherPathIsSymbolicLink(repositoryPath)) {
        return "teacher_repository_root_invalid"
    }
    try {
        if (!FileInfo(repositoryPath).isDirectory()) { return "teacher_repository_root_invalid" }
    } catch (_: Exception) { return "teacher_repository_root_invalid" }
    if (!artifactPath.isAbsolute()) { return "teacher_artifact_root_invalid" }

    let repo = try { canonicalize(repositoryPath).toString().trimEnd('/') } catch (_: Exception) {
        return "teacher_repository_root_invalid"
    }
    if (exists(artifactPath)) {
        if (teacherPathIsSymbolicLink(artifactPath)) { return "teacher_artifact_root_symlink_forbidden" }
        try {
            if (!FileInfo(artifactPath).isDirectory()) { return "teacher_artifact_root_not_directory" }
        } catch (_: Exception) { return "teacher_artifact_root_not_directory" }
    } else {
        let parent = artifactPath.parent
        if (!exists(parent)) { return "teacher_artifact_parent_missing" }
        try {
            if (!FileInfo(parent).isDirectory()) { return "teacher_artifact_parent_invalid" }
        } catch (_: Exception) { return "teacher_artifact_parent_invalid" }
        let canonicalParent = try { canonicalize(parent) } catch (_: Exception) {
            return "teacher_artifact_parent_invalid"
        }
        let candidate = canonicalParent.join(artifactPath.fileName).toString().trimEnd('/')
        if (candidate == repo || candidate.startsWith(repo + "/")) { return "teacher_artifact_root_not_private" }
        try { Directory.create(artifactPath, recursive: false) } catch (_: Exception) {
            return "teacher_artifact_root_create_failed"
        }
    }

    if (!validateTeacherExecutionPrivacy(repositoryValue, artifactValue, true)) {
        if (teacherPathIsSymbolicLink(artifactPath)) { return "teacher_artifact_root_symlink_forbidden" }
        return "teacher_artifact_root_not_private"
    }
    if (chmod(artifactValue, UInt32(0o700)) != 0) { return "teacher_artifact_root_permissions_failed" }
    ""
}

private func teacherPathIsSymbolicLink(path: Path): Bool {
    try { FileInfo(path).isSymbolicLink() } catch (_: Exception) { false }
}

public func cangjieTeacherCliMain(args: Array<String>): Int64 {
    try {
        let options = parseTeacherCliOptions(args)
        if (options.command == "help" || options.command == "--help" || options.command.isEmpty()) {
            println(teacherCliUsage())
            return 0
        }
        if (options.command == "manifest-check") {
            let manifest = loadTeacherDatasetManifestFile(options.manifest, options.checksum)
            println("manifest valid=true cases=${manifest.cases.size} datasetVersion=${manifest.datasetVersion}")
            return 0
        }
        if (options.command == "hash-directory") {
            if (options.starterRoot.isEmpty()) { throw IllegalArgumentException("missing_required_cli_option") }
            println(teacherDirectoryHash(options.starterRoot))
            return 0
        }
        if (options.command == "run") {
            let runs = runTeacherBatchFromCli(options)
            var complete: Int64 = 0
            for (run in runs) { if (run.status == "complete") { complete += 1 } }
            println("teacher runId=${options.runId} total=${runs.size} complete=${complete}")
            return if (complete == runs.size) { 0 } else { 1 }
        }
        if (options.command == "candidate-build") {
            return runTeacherCandidateBuild(options)
        }
        if (options.command == "candidate-reexport") {
            return runTeacherCandidateReexport(options)
        }
        if (options.command == "context-seed-build") { return runTeacherContextSeedBuild(options) }
        if (options.command == "failure-assets-approve") { return runTeacherFailureAssetsApprove(options) }
        if (options.command == "failure-assets-build" || options.command == "failure-assets-reexport") {
            return runTeacherScaffoldFailureAssetsBuild(options)
        }
        println(teacherCliUsage())
        2
    } catch (e: Exception) {
        println("teacher failed diagnostic=${e.message}")
        1
    }
}

private func teacherCliUsage(): String {
    "usage: cangjie_teacher <manifest-check|hash-directory|run|candidate-build|candidate-reexport|context-seed-build|failure-assets-build|failure-assets-reexport|failure-assets-approve> [options]"
}
