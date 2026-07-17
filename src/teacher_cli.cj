package cangjie_teacher

import std.fs.*
import std.posix.*
import std.time.*
import std.collection.*
import std.convert.Parsable

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
            case _ => throw IllegalArgumentException("unknown_cli_option")
        }
        i += 2
    }
    out
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
    let completedPath = "${options.root}/runs/${options.runId}/completed.manifest"
    let completed = loadCompletedTeacherRuns(completedPath)
    let process = CodexTeacherProcess(options.codex, options.model, timeoutMillis: options.timeoutMillis)
    let verifier = CjpmTeacherVerifier(options.testsRoot, timeoutMillis: options.timeoutMillis)
    let runOptions = TeacherRunOptions(options.runId, options.root, options.model, process, verifier, SystemTeacherClock(),
        repairUntilVerified: true, persistAttemptProgress: true)
    let out = ArrayList<TeacherRunManifest>()
    for (caseValue in manifest.cases) {
        if (!options.caseId.isEmpty() && caseValue.caseId != options.caseId) { continue }
        var reusable: ?TeacherRunManifest = None
        for (old in completed) {
            if (old.caseId == caseValue.caseId && old.status == "complete" && old.datasetVersion == caseValue.datasetVersion && old.promptHash == caseValue.promptHash) { reusable = Some(old) }
        }
        match (reusable) {
            case Some(old) => out.add(old)
            case None =>
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
                }
                _ = persistTeacherRunArtifacts(options.root, run, teacherSanitizeEvidence(execution.generationEvidence),
                    teacherSanitizeEvidence(execution.verifierEvidence))
                _ = persistCompletedTeacherRuns(completedPath, out.toArray())
        }
    }
    out.toArray()
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
        println(teacherCliUsage())
        2
    } catch (e: Exception) {
        println("teacher failed diagnostic=${e.message}")
        1
    }
}

private func teacherCliUsage(): String {
    "usage: cangjie_teacher manifest-check --manifest <path> --checksum <sha256> | hash-directory --starter-root <path> | run --root <private-root> --manifest <path> --checksum <sha256> --starter-root <path> --tests-root <path> --run-id <id> --repo-root <path> --local-only [--case-id <id>] [--codex <path>] [--model <id>] [--timeout-ms <ms>] | candidate-build --root <private-root> --manifest <path> --checksum <sha256> --authority-gap <path> --run-id <id> --output-root <path> [--extractor <path>] [--model <id>] [--timeout-ms <ms>] | candidate-reexport --root <private-root> --manifest <path> --checksum <sha256> --authority-gap <path> --run-id <id> --source-export <path> --output-root <path> [--timeout-ms <ms>]"
}
