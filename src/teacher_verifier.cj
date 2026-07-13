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
                evidence += result.output
                if (result.timedOut || result.exitCode != 0) { return TeacherProcessResult(result.exitCode, evidence, timedOut: result.timedOut) }
            }
            TeacherProcessResult(0, evidence)
        } finally {
            _ = teacherAtomicWrite(projectPath, originalProject)
            try { remove(Path(injectedTestPath)) } catch (_: Exception) {}
        }
    }
}

public func teacherCopyTree(source: String, target: String): Unit {
    if (!exists(Path(target))) { Directory.create(Path(target), recursive: true) }
    for (entry in Directory.readFrom(Path(source))) {
        let src = entry.path.toString()
        let dst = Path(target).join(entry.name).toString()
        if (entry.isDirectory()) { teacherCopyTree(src, dst) } else { teacherCopyFile(src, dst) }
    }
}
