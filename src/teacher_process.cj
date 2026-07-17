package cangjie_teacher

import std.collection.*
import std.env.getVariables
import std.fs.*
import std.io.StringReader
import std.process.*
import std.time.*

public class TeacherCommandSpec {
    public let executable: String
    public let args: Array<String>
    public let cwd: String
    public let env: Array<(String, String)>
    public let timeoutMillis: Int64
    public init(executable: String, args: Array<String>, cwd: String,
        env!: Array<(String, String)> = [], timeoutMillis!: Int64 = 600000) {
        this.executable = executable; this.args = args; this.cwd = cwd; this.env = env; this.timeoutMillis = timeoutMillis
    }
}

public interface TeacherCommandExecutor { func execute(spec: TeacherCommandSpec): TeacherProcessResult }

public class NativeTeacherCommandExecutor <: TeacherCommandExecutor {
    public init() {}
    public func execute(spec: TeacherCommandSpec): TeacherProcessResult {
        let environment = HashMap<String, String>()
        for ((key, value) in getVariables()) { environment[key] = value }
        for (entry in spec.env) { environment[entry[0]] = entry[1] }
        try {
            let process = launch(spec.executable, spec.args, stdOut: ProcessRedirect.Pipe,
                stdErr: ProcessRedirect.Pipe, workingDirectory: Some(Path(spec.cwd)), environment: Some(environment))
            let stdout = spawn { try { StringReader(process.stdOutPipe).readToEnd() } catch (_: Exception) { "invalid_response_encoding" } }
            let stderr = spawn { try { StringReader(process.stdErrPipe).readToEnd() } catch (_: Exception) { "invalid_response_encoding" } }
            try {
                let code = process.wait(timeout: Some(Duration.millisecond * spec.timeoutMillis))
                TeacherProcessResult(code, stdout.get() + stderr.get())
            } catch (_: TimeoutException) {
                try { process.terminate(force: true) } catch (_: Exception) {}
                try { _ = stdout.get(); _ = stderr.get() } catch (_: Exception) {}
                TeacherProcessResult(124, "timeout", timedOut: true)
            }
        } catch (_: Exception) { TeacherProcessResult(127, "process_launch_failed") }
    }
}

public class CodexTeacherProcess <: TeacherProcess {
    private let executable: String
    private let model: String
    private let timeoutMillis: Int64
    private let executor: TeacherCommandExecutor
    public init(executable: String, model: String, timeoutMillis!: Int64 = 600000,
        executor!: TeacherCommandExecutor = NativeTeacherCommandExecutor()) {
        this.executable = executable; this.model = model; this.timeoutMillis = timeoutMillis; this.executor = executor
    }
    public func generate(caseValue: TeacherCaseManifest, workspace: String, session: String, runtimeHome: String,
        verifierFeedback: String): TeacherProcessResult {
        if (!exists(Path(workspace))) { Directory.create(Path(workspace), recursive: true) }
        if (!exists(Path(session))) { Directory.create(Path(session), recursive: true) }
        if (!exists(Path(runtimeHome))) { Directory.create(Path(runtimeHome), recursive: true) }
        let repair = if (verifierFeedback.isEmpty()) { "" } else if (verifierFeedback.startsWith("Teacher repair attempt ")) {
            "\n\n${verifierFeedback}"
        } else {
            "\n\nThe public verifier failed. Repair the implementation in the same workspace and rerun local checks. " +
            "Do not look for hidden tests or reference solutions. Sanitized verifier output:\n${verifierFeedback}"
        }
        let prompt = "${caseValue.prompt}\n\nRequired signature: ${caseValue.signature}\n" +
            "Work only inside the current workspace. Implement the case completely and run available local Cangjie checks. " +
            "Do not access CKB, teacher solutions, reference solutions, or hidden tests.${repair}"
        let args = ["exec", "--model", this.model, "--sandbox", "workspace-write", "--skip-git-repo-check",
            "--ephemeral", "--ignore-user-config", "--ignore-rules", "-C", workspace, prompt]
        return this.executor.execute(TeacherCommandSpec(this.executable, args, workspace,
            env: [("CANGJIE_TEACHER_SESSION", session)], timeoutMillis: this.timeoutMillis))
    }
}

public func createTeacherCaseWorkspace(root: String, runId: String, caseValue: TeacherCaseManifest,
    starterRoot: String): String {
    let workspace = TeacherPaths(root).workspace(runId, caseValue.caseId)
    if (exists(Path(workspace))) { remove(Path(workspace), recursive: true) }
    Directory.create(Path(workspace), recursive: true)
    let starter = "${starterRoot}/${caseValue.caseId}/starter"
    if (teacherDirectoryHash(starter) != caseValue.starterHash) { throw IllegalArgumentException("starter_hash_mismatch") }
    teacherCopyTree(starter, workspace)
    workspace
}
