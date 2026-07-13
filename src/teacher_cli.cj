package cangjie_teacher

import std.fs.*
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
    public init() {}
}

public func parseTeacherCliOptions(args: Array<String>): TeacherCliOptions {
    let out = TeacherCliOptions()
    var i: Int64 = 0
    while (i < args.size) {
        if (args[i] == "--help") { out.command = "help"; i += 1; continue }
        if (!args[i].startsWith("--") && out.command.isEmpty()) { out.command = args[i]; i += 1; continue }
        if (args[i] == "--local-only") { out.localOnly = true; i += 1; continue }
        if (i + 1 >= args.size) { throw IllegalArgumentException("missing_cli_option_value") }
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
            case "--timeout-ms" => out.timeoutMillis = try { Int64.parse(value) } catch (_: Exception) { throw IllegalArgumentException("invalid_timeout") }
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
    if (!validateTeacherExecutionPrivacy(options.repositoryRoot, options.root, options.localOnly)) {
        throw IllegalArgumentException("teacher_remote_not_private")
    }
    let manifest = loadTeacherDatasetManifestFile(options.manifest, options.checksum)
    let completedPath = "${options.root}/runs/${options.runId}/completed.manifest"
    let completed = loadCompletedTeacherRuns(completedPath)
    let process = CodexTeacherProcess(options.codex, options.model, timeoutMillis: options.timeoutMillis)
    let verifier = CjpmTeacherVerifier(options.testsRoot, timeoutMillis: options.timeoutMillis)
    let runOptions = TeacherRunOptions(options.runId, options.root, options.model, process, verifier, SystemTeacherClock())
    let out = ArrayList<TeacherRunManifest>()
    for (caseValue in manifest.cases) {
        var reusable: ?TeacherRunManifest = None
        for (old in completed) {
            if (old.caseId == caseValue.caseId && old.status == "complete" && old.datasetVersion == caseValue.datasetVersion && old.promptHash == caseValue.promptHash) { reusable = Some(old) }
        }
        match (reusable) {
            case Some(old) => out.add(old)
            case None =>
                _ = createTeacherCaseWorkspace(options.root, options.runId, caseValue, options.starterRoot)
                let run = finalizeTeacherRun(runTeacherCase(caseValue, runOptions), true)
                out.add(run)
                _ = persistTeacherRunArtifacts(options.root, run, "generation_status=${run.status}", "verification_exit=${run.exitCode}")
                _ = persistCompletedTeacherRuns(completedPath, out.toArray())
        }
    }
    out.toArray()
}

public func validateTeacherExecutionPrivacy(repositoryRoot: String, artifactRoot: String, localOnly: Bool): Bool {
    if (!localOnly || repositoryRoot.trimEnd('/').isEmpty() || artifactRoot.trimEnd('/').isEmpty()) { return false }
    let repo = repositoryRoot.trimEnd('/')
    let artifacts = artifactRoot.trimEnd('/')
    return artifacts != repo && !artifacts.startsWith(repo + "/")
}

public func cangjieTeacherCliMain(args: Array<String>): Int64 {
    try {
        let options = parseTeacherCliOptions(args)
        if (options.command == "help" || options.command == "--help" || options.command.isEmpty()) {
            println("usage: cangjie_teacher manifest-check|run --manifest <path> --checksum <sha256> [run options]")
            return 0
        }
        if (options.command == "manifest-check") {
            let manifest = loadTeacherDatasetManifestFile(options.manifest, options.checksum)
            println("manifest valid=true cases=${manifest.cases.size} datasetVersion=${manifest.datasetVersion}")
            return 0
        }
        if (options.command == "run") {
            let runs = runTeacherBatchFromCli(options)
            var complete: Int64 = 0
            for (run in runs) { if (run.status == "complete") { complete += 1 } }
            println("teacher runId=${options.runId} total=${runs.size} complete=${complete}")
            return if (complete == runs.size) { 0 } else { 1 }
        }
        println("usage: cangjie_teacher manifest-check|run --manifest <path> --checksum <sha256> [run options]")
        2
    } catch (e: Exception) {
        println("teacher failed diagnostic=${e.message}")
        1
    }
}
