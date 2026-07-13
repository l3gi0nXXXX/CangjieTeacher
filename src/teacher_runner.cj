package cangjie_teacher

import std.collection.*

public class TeacherProcessResult {
    public let exitCode: Int64
    public let output: String
    public let timedOut: Bool
    public init(exitCode: Int64, output: String, timedOut!: Bool = false) { this.exitCode = exitCode; this.output = output; this.timedOut = timedOut }
}
public interface TeacherProcess {
    func generate(caseValue: TeacherCaseManifest, workspace: String, session: String, runtimeHome: String): TeacherProcessResult
}
public interface TeacherVerifier { func verify(caseValue: TeacherCaseManifest, solutionRoot: String): TeacherProcessResult }
public interface TeacherClock { func nowMillis(): Int64 }

public class TeacherRunOptions {
    public let runId: String
    public let root: String
    public let modelId: String
    public let process: TeacherProcess
    public let verifier: TeacherVerifier
    public let clock: TeacherClock
    public init(runId: String, root: String, modelId: String, process: TeacherProcess, verifier: TeacherVerifier, clock: TeacherClock) {
        this.runId = runId; this.root = root; this.modelId = modelId; this.process = process; this.verifier = verifier; this.clock = clock
    }
}

public func runTeacherCase(caseValue: TeacherCaseManifest, options: TeacherRunOptions): TeacherRunManifest {
    let paths = TeacherPaths(options.root)
    let started = options.clock.nowMillis()
    let generated = options.process.generate(caseValue, paths.workspace(options.runId, caseValue.caseId),
        paths.session(options.runId, caseValue.caseId), paths.runtimeHome(options.runId, caseValue.caseId))
    if (generated.timedOut) { return buildTeacherRun(caseValue, options, "timeout", 124, "${started}:timeout") }
    if (generated.exitCode != 0) { return buildTeacherRun(caseValue, options, "generation_failed", generated.exitCode, generated.output) }
    if (generated.output.isEmpty()) { return buildTeacherRun(caseValue, options, "empty_output", 3, "empty") }
    return verifyTeacherSolution(caseValue, options, generated.output)
}

public func verifyTeacherSolution(caseValue: TeacherCaseManifest, options: TeacherRunOptions, generatedEvidence: String): TeacherRunManifest {
    let checked = options.verifier.verify(caseValue, TeacherPaths(options.root).solution(caseValue.caseId))
    if (checked.exitCode != 0) { return buildTeacherRun(caseValue, options, "verification_failed", checked.exitCode, generatedEvidence + checked.output) }
    return buildTeacherRun(caseValue, options, "verified", 0, generatedEvidence + checked.output)
}

private func buildTeacherRun(caseValue: TeacherCaseManifest, options: TeacherRunOptions, status: String, exitCode: Int64, evidence: String): TeacherRunManifest {
    return TeacherRunManifest(options.runId, caseValue.caseId, caseValue.datasetVersion, options.modelId,
        caseValue.promptHash, 1, status, exitCode, teacherStableHash(evidence))
}

public func finalizeTeacherRun(run: TeacherRunManifest, evidenceValid: Bool): TeacherRunManifest {
    let status = if (run.status == "verified" && evidenceValid && !run.evidenceHash.isEmpty()) { "complete" } else { run.status }
    return TeacherRunManifest(run.runId, run.caseId, run.datasetVersion, run.modelId, run.promptHash,
        run.attempt, status, run.exitCode, run.evidenceHash)
}

public func runTeacherBatch(cases: Array<TeacherCaseManifest>, options: TeacherRunOptions,
    completed: Array<TeacherRunManifest>): Array<TeacherRunManifest> {
    let out = ArrayList<TeacherRunManifest>()
    for (caseValue in cases) {
        var reusable: ?TeacherRunManifest = None
        for (old in completed) {
            if (old.caseId == caseValue.caseId && old.status == "complete" && old.datasetVersion == caseValue.datasetVersion && old.promptHash == caseValue.promptHash) { reusable = Some(old) }
        }
        match (reusable) { case Some(old) => out.add(old); case None => out.add(finalizeTeacherRun(runTeacherCase(caseValue, options), true)) }
    }
    return out.toArray()
}
