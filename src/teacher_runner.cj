package cangjie_teacher

import std.collection.*

public class TeacherProcessResult {
    public let exitCode: Int64
    public let output: String
    public let timedOut: Bool
    public init(exitCode: Int64, output: String, timedOut!: Bool = false) { this.exitCode = exitCode; this.output = output; this.timedOut = timedOut }
}
public class TeacherCaseExecution {
    public let run: TeacherRunManifest
    public let generationEvidence: String
    public let verifierEvidence: String
    public init(run: TeacherRunManifest, generationEvidence: String, verifierEvidence: String) {
        this.run = run; this.generationEvidence = generationEvidence; this.verifierEvidence = verifierEvidence
    }
}
public interface TeacherProcess {
    func generate(caseValue: TeacherCaseManifest, workspace: String, session: String, runtimeHome: String,
        verifierFeedback: String): TeacherProcessResult
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
    public let repairUntilVerified: Bool
    public init(runId: String, root: String, modelId: String, process: TeacherProcess, verifier: TeacherVerifier,
        clock: TeacherClock, repairUntilVerified!: Bool = false) {
        this.runId = runId; this.root = root; this.modelId = modelId; this.process = process; this.verifier = verifier; this.clock = clock
        this.repairUntilVerified = repairUntilVerified
    }
}

public func runTeacherCase(caseValue: TeacherCaseManifest, options: TeacherRunOptions): TeacherRunManifest {
    executeTeacherCase(caseValue, options).run
}

public func executeTeacherCase(caseValue: TeacherCaseManifest, options: TeacherRunOptions): TeacherCaseExecution {
    let paths = TeacherPaths(options.root)
    let started = options.clock.nowMillis()
    var feedback = ""
    var generationEvidence = ""
    var verifierEvidence = ""
    var teacherAttempt: Int64 = 0
    while (true) {
        teacherAttempt += 1
        let generated = options.process.generate(caseValue, paths.workspace(options.runId, caseValue.caseId),
            paths.session(options.runId, caseValue.caseId), paths.runtimeHome(options.runId, caseValue.caseId), feedback)
        generationEvidence += generated.output
        if (generated.timedOut) { return TeacherCaseExecution(buildTeacherRun(caseValue, options, "timeout", 124, "${started}:timeout", attempt: teacherAttempt), generationEvidence, verifierEvidence) }
        if (generated.exitCode != 0) { return TeacherCaseExecution(buildTeacherRun(caseValue, options, "generation_failed", generated.exitCode, generationEvidence, attempt: teacherAttempt), generationEvidence, verifierEvidence) }
        if (generated.output.isEmpty()) { return TeacherCaseExecution(buildTeacherRun(caseValue, options, "empty_output", 3, "empty", attempt: teacherAttempt), "empty", verifierEvidence) }
        let checked = options.verifier.verify(caseValue, paths.workspace(options.runId, caseValue.caseId))
        verifierEvidence += checked.output
        if (checked.exitCode == 0) {
            return TeacherCaseExecution(buildTeacherRun(caseValue, options, "verified", 0,
                generationEvidence + verifierEvidence, attempt: teacherAttempt), generationEvidence, verifierEvidence)
        }
        if (!options.repairUntilVerified || checked.timedOut) {
            return TeacherCaseExecution(buildTeacherRun(caseValue, options, "verification_failed", checked.exitCode,
                generationEvidence + verifierEvidence, attempt: teacherAttempt), generationEvidence, verifierEvidence)
        }
        feedback = teacherSanitizeEvidence(checked.output)
    }
    throw IllegalStateException("teacher_repair_loop_unreachable")
}

public func verifyTeacherSolution(caseValue: TeacherCaseManifest, options: TeacherRunOptions, generatedEvidence: String): TeacherRunManifest {
    let checked = options.verifier.verify(caseValue, TeacherPaths(options.root).workspace(options.runId, caseValue.caseId))
    if (checked.exitCode != 0) { return buildTeacherRun(caseValue, options, "verification_failed", checked.exitCode, generatedEvidence + checked.output) }
    return buildTeacherRun(caseValue, options, "verified", 0, generatedEvidence + checked.output)
}

private func buildTeacherRun(caseValue: TeacherCaseManifest, options: TeacherRunOptions, status: String, exitCode: Int64,
    evidence: String, attempt!: Int64 = 1): TeacherRunManifest {
    return TeacherRunManifest(options.runId, caseValue.caseId, caseValue.datasetVersion, options.modelId,
        caseValue.promptHash, attempt, status, exitCode, teacherStableHash(evidence))
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
