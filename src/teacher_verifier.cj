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
        if (!exists(Path(testSource))) { return TeacherProcessResult(4, "verifier_fixture_missing") }
        let projectPath = "${solutionRoot}/cjpm.toml"
        let injectedTestPath = "${solutionRoot}/src/TestMain.cj"
        let originalProject = teacherReadUtf8File(projectPath)
        try {
            teacherCopyFile("${testSource}/cjpm.executable.toml", projectPath)
            teacherCopyFile("${testSource}/TestMain.cj", injectedTestPath)
            let commands: Array<Array<String>> = [["clean"], ["build", "-i"], ["test", "-j", "1"], ["run"]]
            var evidence = ""
            for (args in commands) {
                let result = this.executor.execute(TeacherCommandSpec("cjpm", args, solutionRoot, timeoutMillis: this.timeoutMillis))
                if (result.timedOut || result.exitCode != 0) { evidence += result.output; return TeacherProcessResult(result.exitCode, evidence, timedOut: result.timedOut) }
                if (args[0] == "run" && teacherVerifierRunOutputFailed(result.output)) {
                    return TeacherProcessResult(teacherVerifierRunFailureCode(result.output), teacherVerifierRunFailureDiagnostic(result.output))
                }
                evidence += result.output
            }
            TeacherProcessResult(0, evidence)
        } finally {
            _ = teacherAtomicWrite(projectPath, originalProject)
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
    if (output.trimAscii() == "invalid_response_encoding") { return "verifier_invalid_response_encoding" }
    var failureLine = ""
    for (line in output.split("\n")) { if (line.contains("Exception: CangjieEval failure:")) { failureLine=line.trimAscii();break } }
    var boundedLine=failureLine
    for (sensitiveBoundary in ["/Users/", "/home/", "/private/", "~/", "Authorization", "token", "password", "proxy"]) {
        boundedLine=boundedLine.split(sensitiveBoundary)[0].trimAscii()
    }
    // A benchmark assertion may describe an expected return value; normalize that
    // public phrase before the solution-oriented sanitizer sees its broad return guard.
    boundedLine=boundedLine.replace("return ","result ")
    var sanitized = teacherSanitizeEvidence("verifier_business_assertion_failed: ${boundedLine}")
    if (sanitized == "verifier_business_assertion_failed:") { sanitized="verifier_business_assertion_failed: Exception: CangjieEval failure:" }
    let runes = sanitized.toRuneArray()
    if (runes.size <= 256) { sanitized } else { String(runes[..256]) + "..." }
}

public func teacherCopyTree(source: String, target: String): Unit {
    if (!exists(Path(target))) { Directory.create(Path(target), recursive: true) }
    for (entry in Directory.readFrom(Path(source))) {
        let src = entry.path.toString()
        let dst = Path(target).join(entry.name).toString()
        if (entry.isDirectory()) { teacherCopyTree(src, dst) } else { teacherCopyFile(src, dst) }
    }
}
