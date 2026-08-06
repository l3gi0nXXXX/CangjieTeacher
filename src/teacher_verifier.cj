package cangjie_teacher

import std.fs.*

public class CjpmTeacherVerifier <: TeacherVerifier {
    private let testsRoot: String
    private let executor: TeacherCommandExecutor
    private let timeoutMillis: Int64
    public init(testsRoot: String, executor!: TeacherCommandExecutor = NativeTeacherCommandExecutor(), timeoutMillis!: Int64 = 600000) {
        this.testsRoot = testsRoot; this.executor = executor; this.timeoutMillis = timeoutMillis
    }
    public func verify(caseValue: TeacherCaseManifest, solutionRoot: String): TeacherProcessResult {
        let testSource = "${this.testsRoot}/${caseValue.caseId}/tests"
        if (!exists(Path(testSource))) { return TeacherProcessResult(4, "infra_error") }
        let projectPath = "${solutionRoot}/cjpm.toml"
        let injectedTestPath = "${solutionRoot}/src/TestMain.cj"
        let originalProject = try { teacherReadUtf8File(projectPath) }
            catch (_: Exception) { return TeacherProcessResult(65, "infra_error") }
        try {
            try {
                teacherCopyFile("${testSource}/cjpm.executable.toml", projectPath)
                teacherCopyFile("${testSource}/TestMain.cj", injectedTestPath)
            } catch (_: Exception) { return TeacherProcessResult(4, "infra_error") }
            let commands: Array<Array<String>> = [["clean"], ["build", "-i"], ["test", "-j", "1"], ["run"]]
            for (args in commands) {
                let result = try {
                    this.executor.execute(TeacherCommandSpec("cjpm", args, solutionRoot, timeoutMillis: this.timeoutMillis))
                } catch (_: Exception) { return TeacherProcessResult(127, "infra_error") }
                if (result.timedOut) { return TeacherProcessResult(124, "timeout", timedOut: true) }
                if (result.exitCode != 0) {
                    let diagnostic = if (["build", "test", "run"].contains(args[0])) { "failed" } else { "infra_error" }
                    return TeacherProcessResult(result.exitCode, diagnostic)
                }
                if (args[0] == "run" && teacherVerifierRunOutputFailed(result.output)) {
                    return TeacherProcessResult(teacherVerifierRunFailureCode(result.output), teacherVerifierRunFailureDiagnostic(result.output))
                }
            }
            TeacherProcessResult(0, "passed")
        } finally {
            try { _ = teacherAtomicWrite(projectPath, originalProject) } catch (_: Exception) {}
            try { remove(Path(injectedTestPath)) } catch (_: Exception) {}
        }
    }
}

public func teacherVerifierRunOutputFailed(output: String): Bool {
    output.contains("Exception: CangjieEval failure:") || output.trimAscii() == "invalid_response_encoding"
}

private func teacherVerifierRunFailureCode(output: String): Int64 {
    if (output.trimAscii() == "invalid_response_encoding") { 65 } else { 5 }
}

public func teacherVerifierRunFailureDiagnostic(output: String): String {
    if (output.trimAscii() == "invalid_response_encoding") { "infra_error" } else { "failed" }
}

public func teacherCopyTree(source: String, target: String): Unit {
    if (!exists(Path(target))) { Directory.create(Path(target), recursive: true) }
    for (entry in Directory.readFrom(Path(source))) {
        let src = entry.path.toString()
        let dst = Path(target).join(entry.name).toString()
        if (entry.isDirectory()) { teacherCopyTree(src, dst) } else { teacherCopyFile(src, dst) }
    }
}
