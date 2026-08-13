package cangjie_teacher

import std.fs.*
import std.posix.*
import std.time.*
import std.collection.*
import std.sort.*
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
    public let sourceExports = ArrayList<String>()
    public var extractor = "codex"
    public var sourceManifest = ""
    public var failurePath = ""
    public var expectedHash = ""
    public var baseContextManifest = ""
    public var baseContextRoot = ""
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
    public var fixtureRootHash = ""
    public var baseContextHash = ""
    public var allowedRoot = ""
    public var sourceRoot = ""
    public var protectedRoot = ""
    public var validationIdentity = ""
    public var completionControl = ""
    public var promptCapability = ""
    public var runtimeExecutable = ""
    public var classifierA = ""
    public var classifierB = ""
    public var generator = ""
    public var classifierAHash = ""
    public var classifierBHash = ""
    public var generatorHash = ""
    public var adapterWorkspace = ""
    public var authority = ""
    public var gapDescription = ""
    public var frozenKnowledgeReference = ""
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
        if (args[i] == "--source-export" && out.command == "candidate-combine") {
            if (args[i + 1].isEmpty()) { throw IllegalArgumentException("missing_cli_option_value") }
            out.sourceExports.add(args[i + 1]); i += 2; continue
        }
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
            case "--base-context-root" => out.baseContextRoot = value
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
            case "--scaffold-fixture-root" => out.fixtureRoot = value
            case "--fixture-root-hash" => out.fixtureRootHash = value
            case "--base-context-hash" => out.baseContextHash = value
            case "--allowed-root" => out.allowedRoot = value
            case "--source-root" => out.sourceRoot = value
            case "--protected-root" => out.protectedRoot = value
            case "--validation-identity" => out.validationIdentity = value
            case "--completion-control" => out.completionControl = value
            case "--prompt-capability" => out.promptCapability = value
            case "--provider-runtime" => out.runtimeExecutable = value
            case "--classifier-a" => out.classifierA = value
            case "--classifier-b" => out.classifierB = value
            case "--generator" => out.generator = value
            case "--classifier-a-hash" => out.classifierAHash = value
            case "--classifier-b-hash" => out.classifierBHash = value
            case "--generator-hash" => out.generatorHash = value
            case "--adapter-workspace" => out.adapterWorkspace = value
            case "--authority" => out.authority = value
            case "--gap-description" => out.gapDescription = value
            case "--frozen-knowledge-reference" => out.frozenKnowledgeReference = value
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

private func teacherCliLoadValidationIdentity(options: TeacherCliOptions): TeacherValidationIdentity {
    if (options.allowedRoot.isEmpty() || options.validationIdentity.isEmpty() ||
        options.completionControl.isEmpty() || options.promptCapability.isEmpty()) {
        throw IllegalArgumentException("missing_required_cli_option")
    }
    let identityRaw = teacherReadUtf8File(teacherResolveArtifactInput(options.allowedRoot,
        options.validationIdentity))
    let identity = parseTeacherValidationIdentity(identityRaw)
    let controlRaw = teacherReadUtf8File(teacherResolveArtifactInput(options.allowedRoot,
        options.completionControl))
    let control = parseTeacherStudentCompletionControl(controlRaw)
    let capabilityRaw = teacherReadUtf8File(teacherResolveArtifactInput(options.allowedRoot,
        options.promptCapability))
    if (identity.completionControlHash != "sha256:${teacherStableHash(controlRaw)}" ||
        identity.providerPromptCapabilityHash != "sha256:${teacherStableHash(capabilityRaw)}") {
        throw IllegalArgumentException("student_validation_identity_mismatch")
    }
    if (control.completionCommandHash != teacherStudentCompletionCommandHash(identity.modelVersion)) {
        throw IllegalArgumentException("student_validation_identity_mismatch")
    }
    identity
}

private func teacherCliCreateAdapterWorkspace(options: TeacherCliOptions,
    name: String): String {
    if (!teacherArtifactSafeComponent(name)) {
        throw IllegalArgumentException("artifact_output_invalid")
    }
    _ = teacherResolveArtifactInput(options.allowedRoot,
        options.adapterWorkspace, directory: true)
    let output = Path(options.adapterWorkspace).join(name)
    if (exists(output)) { throw IllegalArgumentException("artifact_output_invalid") }
    Directory.create(output, recursive: false)
    output.toString()
}

private func teacherCliCandidateIdentityMatches(candidate: TeacherContextCandidateSetV2,
    identity: TeacherValidationIdentity): Bool {
    var found = false
    for (lane in [candidate.rules, candidate.skills]) {
        if (!lane.eligible) { continue }
        for (file in lane.files) {
            if (!file.path.endsWith("/execution.json")) { continue }
            try {
                let object = JsonValue.fromStr(file.content.trimAscii()).asObject()
                if (teacherCliJsonString(object, "executorKind") !=
                    "student_completion_non_humaneval" ||
                    teacherCliJsonString(object, "providerIdentityHash") != identity.identityHash ||
                    teacherCliJsonString(object, "modelVersion") != identity.modelVersion) { return false }
                found = true
            } catch (_: Exception) { return false }
        }
    }
    found
}

private func runTeacherContextSeedBuild(options: TeacherCliOptions): Int64 {
    if (options.scaffoldContract) {
        if (options.fixtureRoot.isEmpty() || options.fixtureRootHash.isEmpty() ||
            options.allowedRoot.isEmpty() || options.sourceRoot.isEmpty() ||
            options.protectedRoot.isEmpty() || options.outputRoot.isEmpty() ||
            options.runId.isEmpty()) {
            throw IllegalArgumentException("missing_required_cli_option")
        }
        let fixtureRoot = teacherResolveArtifactInput(options.allowedRoot,
            options.fixtureRoot, directory: true)
        let fixtures = teacherCliLoadRawFixtures(options.allowedRoot,
            options.fixtureRoot, options.fixtureRootHash)
        let closure = loadTeacherContextSourceClosure(options.allowedRoot,
            options.sourceRoot, options.protectedRoot)
        if (closure.manifest.sourceKind != "independent_sources") {
            throw IllegalArgumentException("candidate_lane_lineage_invalid")
        }
        let ruleProposal = parseTeacherFailureAssetGenerationResponse(
            teacherReadUtf8File("${fixtureRoot}/proposal-rules.json").trimAscii())
        let skillProposal = parseTeacherFailureAssetGenerationResponse(
            teacherReadUtf8File("${fixtureRoot}/proposal-skill.json").trimAscii())
        let knowledgeRequest = TeacherFailureKnowledgeRequest(
            teacherReadUtf8File("${fixtureRoot}/knowledge-missing.txt").trimAscii(),
            teacherReadUtf8File("${fixtureRoot}/knowledge-authority.txt").trimAscii(),
            teacherReadUtf8File("${fixtureRoot}/knowledge-atom.json").trimAscii(),
            teacherReadUtf8File("${fixtureRoot}/knowledge-reference.json").trimAscii(),
            "${options.allowedRoot}/knowledge-workspace", closure.protectedArtifacts)
        let candidate = buildTeacherIndependentContextSeed(TeacherIndependentSeedRequestV2(
            closure, ruleProposal, skillProposal, fixtures, fixtures,
            TeacherCliFixtureExecutor(fixtureRoot), knowledgeRequest,
            ScaffoldTeacherFailureKnowledgeAdapter(TeacherCliScaffoldAtomExecutor()),
            options.runId, "scaffold-seed-rule", "synthetic-rune-boundary",
            "scaffold-seed-skill", options.allowedRoot, options.outputRoot))
        println(renderTeacherFailureAssetsBuildOutput(candidate.candidateSetId,
            candidate.candidateSetHash, options.json))
        return 0
    }
    if (!options.validationIdentity.isEmpty()) {
        if (options.fixtureRoot.isEmpty() || options.fixtureRootHash.isEmpty() ||
            options.allowedRoot.isEmpty() || options.sourceRoot.isEmpty() ||
            options.protectedRoot.isEmpty() || options.outputRoot.isEmpty() || options.runId.isEmpty() ||
            options.rulesContent.isEmpty() || options.skillsContent.isEmpty() ||
            options.frozenKnowledgeReference.isEmpty() || options.runtimeExecutable.isEmpty() ||
            options.adapterWorkspace.isEmpty()) {
            throw IllegalArgumentException("missing_required_cli_option")
        }
        let identity = teacherCliLoadValidationIdentity(options)
        let closure = loadTeacherContextSourceClosure(options.allowedRoot,
            options.sourceRoot, options.protectedRoot)
        if (closure.manifest.sourceKind != "independent_sources") {
            throw IllegalArgumentException("candidate_lane_lineage_invalid")
        }
        let fixtures = teacherCliLoadRawFixtures(options.allowedRoot, options.fixtureRoot,
            options.fixtureRootHash, scaffold: false)
        let ruleProposal = parseTeacherFailureAssetGenerationResponse(teacherReadUtf8File(
            teacherResolveArtifactInput(options.allowedRoot, options.rulesContent)).trimAscii())
        let skillProposal = parseTeacherFailureAssetGenerationResponse(teacherReadUtf8File(
            teacherResolveArtifactInput(options.allowedRoot, options.skillsContent)).trimAscii())
        let reference = teacherReadUtf8File(teacherResolveArtifactInput(options.allowedRoot,
            options.frozenKnowledgeReference)).trimAscii()
        let studentWorkspace = teacherCliCreateAdapterWorkspace(options, "student-seed-${options.runId}")
        let candidate = buildTeacherIndependentContextSeed(TeacherIndependentSeedRequestV2(
            closure, ruleProposal, skillProposal, fixtures, fixtures,
            StudentCompletionNonHumanEvalExecutor(options.runtimeExecutable,
                options.allowedRoot, studentWorkspace, options.completionControl, identity,
                timeoutMillis: options.timeoutMillis),
            TeacherFailureKnowledgeRequest("frozen-independent-knowledge", "", "", reference,
                "", closure.protectedArtifacts), FrozenTeacherFailureKnowledgeAdapter(),
            options.runId, "real-seed-rule", "independent-general-rule",
            "real-seed-skill", options.allowedRoot, options.outputRoot))
        println(renderTeacherFailureAssetsBuildOutput(candidate.candidateSetId,
            candidate.candidateSetHash, options.json, candidate.validationLevel,
            "rules,skills,knowledge"))
        return 0
    }
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
        options.allowedRoot.isEmpty() || options.sourceRoot.isEmpty() || options.protectedRoot.isEmpty() ||
        options.baseContextRoot.isEmpty() ||
        !["approve", "reject"].contains(options.decision) || !teacherCliSafeReviewText(options.reviewer) ||
        !teacherCliSafeReviewText(options.reason) || options.approvedAtUtc.isEmpty()) {
        throw IllegalArgumentException("missing_required_cli_option")
    }
    let candidate = parseTeacherContextCandidateSetDirectoryV2(options.allowedRoot,
        options.sourceExport, baseContextRoot: options.baseContextRoot)
    if (candidate.candidateSetHash != options.candidateSetHash) {
        throw IllegalArgumentException("candidate_approval_hash_mismatch")
    }
    if (candidate.validationLevel == "student_validated") {
        let identity = teacherCliLoadValidationIdentity(options)
        if (!teacherCliCandidateIdentityMatches(candidate, identity)) {
            throw IllegalArgumentException("student_validation_identity_mismatch")
        }
    }
    let approval = approveTeacherContextCandidateSetV2(options.allowedRoot, options.sourceExport,
        options.sourceRoot, options.protectedRoot, options.baseContextRoot, options.decision,
        options.reviewer, options.reason, options.approvedAtUtc)
    if (exists(Path(options.output))) { throw IllegalArgumentException("candidate_approval_hash_mismatch") }
    let outputPath = Path(options.output)
    if (!outputPath.isAbsolute() || outputPath.fileName.isEmpty() ||
        outputPath.fileName.contains("/") || outputPath.fileName.contains("\\")) {
        throw IllegalArgumentException("artifact_output_invalid")
    }
    let outputParent = teacherResolveArtifactInput(options.allowedRoot,
        outputPath.parent.toString(), directory: true)
    _ = teacherAtomicWrite(Path(outputParent).join(outputPath.fileName).toString(), approval + "\n")
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
    for (marker in ["humaneval_164_derived", "/users/", "/home/", "/private/",
        "authorization", "token=", "password=", "hidden_test", "reference solution", "expectedoutput"]) {
        if (lower.contains(marker)) { return false }
    }
    true
}

public func renderTeacherFailureAssetsBuildOutput(candidateSetId: String,
    candidateSetHash: String, json: Bool): String {
    if (json) { return "{\"ok\":true,\"candidateSetHash\":\"${candidateSetHash}\"}" }
    "failure assets built candidateSet=${candidateSetId} validation=scaffold_contract changedLane=rules"
}

public func renderTeacherFailureAssetsBuildOutput(candidateSetId: String,
    candidateSetHash: String, json: Bool, validationLevel: String,
    changedLane: String): String {
    if (json) { return "{\"ok\":true,\"candidateSetHash\":\"${candidateSetHash}\"}" }
    "failure assets built candidateSet=${candidateSetId} validation=${validationLevel} changedLane=${changedLane}"
}

private class TeacherCliFixtureExecutor <: TeacherAssetFixtureExecutor {
    let root: String
    private let identity = sealTeacherValidationIdentity("scaffold", "fake-scaffold-v2", "scaffold",
        "sha256:${teacherStableHash("scaffold-fixture-runtime-v2")}",
        "sha256:${teacherStableHash("scaffold-fixture-control-v2")}",
        "sha256:${teacherStableHash("scaffold-fixture-prompt-v2")}")
    init(root: String) { this.root = root }
    public func executorKind(): String { "fake_contract" }
    public func providerIdentityHash(): String { "sha256:${teacherStableHash("scaffold-fixture-provider-v2")}" }
    public func modelVersion(): String { "fake-scaffold-v2" }
    public func validationIdentity(): TeacherValidationIdentity { identity }
    public func execute(target: TeacherAssetValidationTarget,
        fixture: TeacherAssetFixture): (Int64, String, String) {
        let fixtureRoot = "${root}/fixtures/${fixture.fixtureId}"
        let exitCode = try { Int64.parse(teacherReadUtf8File("${fixtureRoot}/exit-code.txt").trimAscii()) }
        catch (_: Exception) { throw IllegalArgumentException("candidate_test_evidence_invalid") }
        (exitCode, teacherReadUtf8File("${fixtureRoot}/actual.txt").trimAscii(),
            teacherReadUtf8File("${fixtureRoot}/transcript.txt").trimAscii())
    }
}

private func teacherCliLoadRawFixtures(allowedRoot: String, fixtureRoot: String,
    expectedRootHash: String, scaffold!: Bool = true): Array<TeacherAssetFixture> {
    let root = teacherResolveArtifactInput(allowedRoot, fixtureRoot, directory: true)
    let canonicalAllowed = teacherCanonicalArtifactRoot(allowedRoot)
    if (!teacherCliSha(expectedRootHash) || teacherDirectoryHash(root) != expectedRootHash) {
        throw IllegalArgumentException("candidate_test_evidence_invalid")
    }
    let fixturesRoot = Path(teacherResolveArtifactInput(canonicalAllowed,
        "${root}/fixtures", directory: true))
    let out = ArrayList<TeacherAssetFixture>(); let ids = HashSet<String>()
    let entryNames = ArrayList<String>()
    for (entry in Directory.readFrom(fixturesRoot)) {
        if (entry.isSymbolicLink() || !entry.isDirectory() || !teacherArtifactSafeComponent(entry.name)) {
            throw IllegalArgumentException("candidate_test_evidence_invalid")
        }
        entryNames.add(entry.name)
    }
    let sortedEntryNames = entryNames.toArray(); sort(sortedEntryNames)
    for (entryName in sortedEntryNames) {
        let entryPath = fixturesRoot.join(entryName); let entryInfo = FileInfo(entryPath)
        if (entryInfo.isSymbolicLink() || !entryInfo.isDirectory()) {
            throw IllegalArgumentException("candidate_test_evidence_invalid")
        }
        let expected = if (scaffold) {
            HashSet<String>(["fixture.json", "input.txt", "expected.txt", "actual.txt",
                "transcript.txt", "exit-code.txt"])
        } else { HashSet<String>(["fixture.json", "input.txt", "expected.txt"]) }
        for (file in Directory.readFrom(entryPath)) {
            if (file.isSymbolicLink() || !file.isRegular() || !expected.contains(file.name)) {
                throw IllegalArgumentException("candidate_test_evidence_invalid")
            }
            expected.remove(file.name)
        }
        if (!expected.isEmpty()) { throw IllegalArgumentException("candidate_test_evidence_invalid") }
        try {
            let raw = teacherReadUtf8File(entryPath.join("fixture.json").toString()).trimAscii()
            let object = JsonValue.fromStr(raw).asObject()
            let id = teacherCliJsonString(object, "fixtureId")
            let kind = teacherCliJsonString(object, "kind")
            let sourceClass = teacherCliJsonString(object, "sourceClass")
            let schema = if (scaffold) { "teacher-cli-scaffold-fixture-v2" }
                else { "teacher-cli-real-fixture-v1" }
            let canonical = "{\"schemaVersion\":\"${schema}\"," +
                "\"fixtureId\":\"${id}\",\"kind\":\"${kind}\",\"sourceClass\":\"${sourceClass}\"}"
            if (object.getFields().size != 4 || raw != canonical || id != entryName || ids.contains(id) ||
                sourceClass != "non_humaneval_experiment") {
                throw IllegalArgumentException("candidate_test_evidence_invalid")
            }
            ids.add(id)
            out.add(TeacherAssetFixture(id, kind, sourceClass,
                teacherReadUtf8File(entryPath.join("input.txt").toString()).trimAscii(),
                teacherReadUtf8File(entryPath.join("expected.txt").toString()).trimAscii()))
        } catch (e: IllegalArgumentException) { throw e }
        catch (_: Exception) { throw IllegalArgumentException("candidate_test_evidence_invalid") }
    }
    if (out.isEmpty()) { throw IllegalArgumentException("candidate_test_evidence_invalid") }
    out.toArray()
}

private class TeacherCliScaffoldAtomExecutor <: TeacherCommandExecutor {
    public func execute(spec: TeacherCommandSpec): TeacherProcessResult {
        if (spec.cwd.contains("/negative") && !spec.args.isEmpty() && spec.args[0] == "build") {
            TeacherProcessResult(1, "synthetic compile rejection")
        } else { TeacherProcessResult(0, "synthetic atom check passed") }
    }
}

private func runTeacherScaffoldFailureAssetsBuild(options: TeacherCliOptions): Int64 {
    if (!options.scaffoldContract) { throw IllegalArgumentException("classification_requires_review") }
    if (options.command == "failure-assets-reexport") {
        if (options.allowedRoot.isEmpty() || options.baseContextRoot.isEmpty() ||
            options.sourceExport.isEmpty() || options.outputRoot.isEmpty()) {
            throw IllegalArgumentException("missing_required_cli_option")
        }
        let candidate = parseTeacherContextCandidateSetDirectoryV2(options.allowedRoot,
            options.sourceExport, baseContextRoot: options.baseContextRoot)
        _ = exportTeacherContextCandidateSetV2(candidate, options.allowedRoot, options.outputRoot,
            baseContextRoot: options.baseContextRoot)
        println(renderTeacherFailureAssetsBuildOutput(candidate.candidateSetId,
            candidate.candidateSetHash, options.json)); return 0
    }
    if (options.fixtureRoot.isEmpty() || options.fixtureRootHash.isEmpty() ||
        options.failurePath.isEmpty() || options.expectedHash.isEmpty() ||
        options.allowedRoot.isEmpty() || options.sourceRoot.isEmpty() || options.protectedRoot.isEmpty() ||
        options.baseContextRoot.isEmpty() || options.outputRoot.isEmpty() || options.runId.isEmpty()) {
        throw IllegalArgumentException("missing_required_cli_option")
    }
    let failurePath = teacherResolveArtifactInput(options.allowedRoot, options.failurePath)
    let failureRaw = teacherReadUtf8File(failurePath).trimAscii()
    if (!teacherCliScaffoldSafe(failureRaw)) { throw IllegalArgumentException("candidate_generation_invalid") }
    let failure = parseTeacherCompletionFailureInput(failureRaw)
    if (failure.evidenceHash != options.expectedHash || renderTeacherCompletionFailureInput(failure) != failureRaw) {
        throw IllegalArgumentException("candidate_generation_invalid")
    }
    if (failure.datasetVersion != "synthetic-non-humaneval-v1" || failure.assetLineage != "independent") {
        throw IllegalArgumentException("candidate_generation_invalid")
    }
    let fixtureRoot = teacherResolveArtifactInput(options.allowedRoot, options.fixtureRoot, directory: true)
    let firstRaw = teacherReadUtf8File("${fixtureRoot}/classification-a.json").trimAscii()
    let secondRaw = teacherReadUtf8File("${fixtureRoot}/classification-b.json").trimAscii()
    let first = parseTeacherFailureAssetClassifierResponse(firstRaw)
    let second = parseTeacherFailureAssetClassifierResponse(secondRaw)
    if (first.failureEvidenceHash != options.expectedHash || second.failureEvidenceHash != options.expectedHash ||
        firstRaw != secondRaw || !["rules_gap", "all_assets_gap"].contains(first.gapKind)) {
        throw IllegalArgumentException("classification_requires_review")
    }
    let fixtures = teacherCliLoadRawFixtures(options.allowedRoot, options.fixtureRoot,
        options.fixtureRootHash)
    if (first.gapKind == "all_assets_gap") {
        let official = teacherReadUtf8File("${fixtureRoot}/official-source.md").trimAscii()
        let community = teacherReadUtf8File("${fixtureRoot}/community-source.md").trimAscii()
        let experiment = teacherReadUtf8File("${fixtureRoot}/non-humaneval-source.txt").trimAscii()
        if (!teacherCliScaffoldSafe(official + community + experiment) ||
            !official.contains("String") || !official.contains("Rune") ||
            !community.contains("中文🙂") || !experiment.contains("non-HumanEval")) {
            throw IllegalArgumentException("candidate_generation_invalid")
        }
    }
    let closure = loadTeacherContextSourceClosure(options.allowedRoot, options.sourceRoot,
        options.protectedRoot)
    let base = loadTeacherContextBaseStateV2(options.allowedRoot, options.baseContextRoot)
    if (first.gapKind == "all_assets_gap" && (base.rulesLineage != "independent" ||
        base.skillsLineage != "independent" || base.knowledgeLineage != "independent")) {
        throw IllegalArgumentException("candidate_base_composite_mismatch")
    }
    let baseKnowledge = teacherReadUtf8File("${base.baseRoot}/knowledge-reference.json").trimAscii()
    let knowledgeRequest = if (first.knowledgeEligible) {
        TeacherFailureKnowledgeRequest(
            teacherReadUtf8File("${fixtureRoot}/knowledge-missing.txt").trimAscii(),
            teacherReadUtf8File("${fixtureRoot}/knowledge-authority.txt").trimAscii(),
            teacherReadUtf8File("${fixtureRoot}/knowledge-atom.json").trimAscii(),
            teacherReadUtf8File("${fixtureRoot}/knowledge-reference.json").trimAscii(),
            "${options.allowedRoot}/knowledge-workspace", closure.protectedArtifacts)
    } else {
        TeacherFailureKnowledgeRequest("unused", "unused", "{}", baseKnowledge,
            "${base.baseRoot}/unused", closure.protectedArtifacts)
    }
    let request = TeacherFailureAssetBuildRequestV2(failure, first, second,
        teacherReadUtf8File("${fixtureRoot}/gap-description.txt").trimAscii(),
        TeacherCliScaffoldGenerator(fixtureRoot), fixtures, fixtures,
        TeacherCliFixtureExecutor(fixtureRoot), knowledgeRequest,
        ScaffoldTeacherFailureKnowledgeAdapter(TeacherCliScaffoldAtomExecutor()), closure, base,
        options.runId, "scaffold-rule-${first.classificationEvidenceHash}",
        "synthetic-rune-boundary", "scaffold-skill-${first.classificationEvidenceHash}",
        "add", "", "add", "",
        options.allowedRoot, options.outputRoot)
    let built = buildTeacherFailureAssets(request)
    let candidate = match (built.candidateSetV2) {
        case Some(value) => value
        case None => throw IllegalArgumentException("candidate_generation_invalid")
    }
    println(renderTeacherFailureAssetsBuildOutput(candidate.candidateSetId, candidate.candidateSetHash,
        options.json))
    0
}

private func teacherCliChangedLanes(value: TeacherFailureAssetClassification): String {
    let out = ArrayList<String>()
    if (value.rulesEligible) { out.add("rules") }
    if (value.skillEligible) { out.add("skills") }
    if (value.knowledgeEligible) { out.add("knowledge") }
    teacherJoin(out.toArray(), ",")
}

private func runTeacherRealFailureAssetsBuild(options: TeacherCliOptions): Int64 {
    if (options.fixtureRoot.isEmpty() || options.fixtureRootHash.isEmpty() ||
        options.failurePath.isEmpty() || options.expectedHash.isEmpty() ||
        options.allowedRoot.isEmpty() || options.sourceRoot.isEmpty() ||
        options.protectedRoot.isEmpty() || options.baseContextRoot.isEmpty() ||
        options.outputRoot.isEmpty() || options.runId.isEmpty() || options.runtimeExecutable.isEmpty() ||
        options.classifierA.isEmpty() || options.classifierB.isEmpty() || options.generator.isEmpty() ||
        options.classifierAHash.isEmpty() || options.classifierBHash.isEmpty() ||
        options.generatorHash.isEmpty() || options.adapterWorkspace.isEmpty() ||
        options.authority.isEmpty() || options.gapDescription.isEmpty()) {
        throw IllegalArgumentException("missing_required_cli_option")
    }
    let identity = teacherCliLoadValidationIdentity(options)
    let failureRaw = teacherReadUtf8File(teacherResolveArtifactInput(options.allowedRoot,
        options.failurePath)).trimAscii()
    let failure = parseTeacherCompletionFailureInput(failureRaw)
    if (failure.evidenceHash != options.expectedHash ||
        renderTeacherCompletionFailureInput(failure) != failureRaw) {
        throw IllegalArgumentException("candidate_generation_invalid")
    }
    let authority = teacherReadUtf8File(teacherResolveArtifactInput(options.allowedRoot,
        options.authority)).trimAscii()
    let classifierRequest = TeacherFailureAssetClassifierRequest(failure.evidenceHash,
        failure.failureObservation, "${failure.failureKind}:${failure.baseStatus}:${failure.plusStatus}",
        authority)
    _ = renderTeacherFailureAssetClassifierRequest(classifierRequest)
    let classifierAWorkspace = teacherCliCreateAdapterWorkspace(options,
        "classifier-a-${options.runId}")
    let classifierBWorkspace = teacherCliCreateAdapterWorkspace(options,
        "classifier-b-${options.runId}")
    let first = parseTeacherFailureAssetClassifierResponse(
        StrictProcessTeacherFailureAssetClassifier(options.classifierA, options.classifierAHash,
            options.allowedRoot, classifierAWorkspace, timeoutMillis: options.timeoutMillis)
            .classify(classifierRequest))
    let second = parseTeacherFailureAssetClassifierResponse(
        StrictProcessTeacherFailureAssetClassifier(options.classifierB, options.classifierBHash,
            options.allowedRoot, classifierBWorkspace, timeoutMillis: options.timeoutMillis)
            .classify(classifierRequest))
    let reconciled = reconcileTeacherFailureAssetClassifications(first, second)
    let closure = loadTeacherContextSourceClosure(options.allowedRoot,
        options.sourceRoot, options.protectedRoot)
    if (closure.manifest.sourceKind != "completion_failures") {
        throw IllegalArgumentException("failure_classification_binding_mismatch")
    }
    let base = loadTeacherContextBaseStateV2(options.allowedRoot, options.baseContextRoot)
    let fixtures = teacherCliLoadRawFixtures(options.allowedRoot, options.fixtureRoot,
        options.fixtureRootHash, scaffold: false)
    let generatorWorkspace = teacherCliCreateAdapterWorkspace(options,
        "generator-${options.runId}")
    let generator = StrictProcessTeacherFailureAssetGenerator(options.generator,
        options.generatorHash, options.allowedRoot, generatorWorkspace,
        timeoutMillis: options.timeoutMillis)
    let gap = teacherReadUtf8File(teacherResolveArtifactInput(options.allowedRoot,
        options.gapDescription)).trimAscii()
    let frozenReference = if (reconciled.knowledgeEligible) {
        if (options.frozenKnowledgeReference.isEmpty()) {
            throw IllegalArgumentException("missing_required_cli_option")
        }
        teacherReadUtf8File(teacherResolveArtifactInput(options.allowedRoot,
            options.frozenKnowledgeReference)).trimAscii()
    } else { "{}" }
    let studentWorkspace = teacherCliCreateAdapterWorkspace(options,
        "student-failure-${options.runId}")
    let request = TeacherFailureAssetBuildRequestV2(failure, first, second, gap,
        generator, fixtures, fixtures,
        StudentCompletionNonHumanEvalExecutor(options.runtimeExecutable,
            options.allowedRoot, studentWorkspace, options.completionControl, identity,
            timeoutMillis: options.timeoutMillis),
        TeacherFailureKnowledgeRequest("unused", "", "", frozenReference, "",
            closure.protectedArtifacts), FrozenTeacherFailureKnowledgeAdapter(), closure, base,
        options.runId, "real-rule-${first.classificationEvidenceHash}",
        "failure-derived-general-rule", "real-skill-${first.classificationEvidenceHash}",
        "add", "", "add", "", options.allowedRoot, options.outputRoot)
    let built = buildTeacherFailureAssets(request)
    let candidate = match (built.candidateSetV2) {
        case Some(value) => value
        case None => throw IllegalArgumentException("candidate_generation_invalid")
    }
    println(renderTeacherFailureAssetsBuildOutput(candidate.candidateSetId,
        candidate.candidateSetHash, options.json, candidate.validationLevel,
        teacherCliChangedLanes(built.classification)))
    0
}

private func runTeacherFailureAssetsCommand(options: TeacherCliOptions): Int64 {
    if (options.scaffoldContract) { return runTeacherScaffoldFailureAssetsBuild(options) }
    if (options.command == "failure-assets-reexport") {
        if (options.allowedRoot.isEmpty() || options.baseContextRoot.isEmpty() ||
            options.sourceExport.isEmpty() || options.outputRoot.isEmpty()) {
            throw IllegalArgumentException("missing_required_cli_option")
        }
        let candidate = parseTeacherContextCandidateSetDirectoryV2(options.allowedRoot,
            options.sourceExport, baseContextRoot: options.baseContextRoot)
        _ = exportTeacherContextCandidateSetV2(candidate, options.allowedRoot,
            options.outputRoot, baseContextRoot: options.baseContextRoot)
        println(renderTeacherFailureAssetsBuildOutput(candidate.candidateSetId,
            candidate.candidateSetHash, options.json, candidate.validationLevel, "sealed"))
        return 0
    }
    runTeacherRealFailureAssetsBuild(options)
}

private func runTeacherCandidateCombine(options: TeacherCliOptions): Int64 {
    if (options.sourceExports.size < 2 || options.allowedRoot.isEmpty() ||
        options.sourceRoot.isEmpty() || options.protectedRoot.isEmpty() ||
        options.baseContextRoot.isEmpty() || options.outputRoot.isEmpty() ||
        options.runId.isEmpty() || options.fixtureRoot.isEmpty() ||
        options.fixtureRootHash.isEmpty() || options.runtimeExecutable.isEmpty() ||
        options.adapterWorkspace.isEmpty()) {
        throw IllegalArgumentException("missing_required_cli_option")
    }
    let identity = teacherCliLoadValidationIdentity(options)
    let fixtures = teacherCliLoadRawFixtures(options.allowedRoot, options.fixtureRoot,
        options.fixtureRootHash, scaffold: false)
    let closure = loadTeacherContextSourceClosure(options.allowedRoot,
        options.sourceRoot, options.protectedRoot)
    let workspace = teacherCliCreateAdapterWorkspace(options, "student-combine-${options.runId}")
    let candidate = combineTeacherContextCandidateSetsV2(TeacherContextCandidateCombineRequestV2(
        options.allowedRoot, options.sourceExports.toArray(), options.baseContextRoot, closure,
        fixtures, StudentCompletionNonHumanEvalExecutor(options.runtimeExecutable,
            options.allowedRoot, workspace, options.completionControl, identity,
            timeoutMillis: options.timeoutMillis), options.runId, options.outputRoot))
    println(renderTeacherFailureAssetsBuildOutput(candidate.candidateSetId,
        candidate.candidateSetHash, options.json, candidate.validationLevel, "rules"))
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
        if (options.command == "candidate-combine") { return runTeacherCandidateCombine(options) }
        if (options.command == "failure-assets-approve") { return runTeacherFailureAssetsApprove(options) }
        if (options.command == "failure-assets-build" || options.command == "failure-assets-reexport") {
            return runTeacherFailureAssetsCommand(options)
        }
        println(teacherCliUsage())
        2
    } catch (e: Exception) {
        println("teacher failed diagnostic=${e.message}")
        1
    }
}

private func teacherCliUsage(): String {
    "usage: cangjie_teacher <manifest-check|hash-directory|run|candidate-build|candidate-reexport|context-seed-build|candidate-combine|failure-assets-build|failure-assets-reexport|failure-assets-approve> [options]"
}
