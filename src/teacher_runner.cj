package cangjie_teacher

import std.collection.*
import std.fs.*

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
    public let persistAttemptProgress: Bool
    public let failureInput: ?TeacherCompletionFailureInput
    public let failureClassification: ?TeacherFailureClassification
    public init(runId: String, root: String, modelId: String, process: TeacherProcess, verifier: TeacherVerifier,
        clock: TeacherClock, repairUntilVerified!: Bool = false, persistAttemptProgress!: Bool = false,
        failureInput!: ?TeacherCompletionFailureInput = None,
        failureClassification!: ?TeacherFailureClassification = None) {
        this.runId = runId; this.root = root; this.modelId = modelId; this.process = process; this.verifier = verifier; this.clock = clock
        this.repairUntilVerified = repairUntilVerified
        this.persistAttemptProgress = persistAttemptProgress
        this.failureInput = failureInput; this.failureClassification = failureClassification
    }
}

public func runTeacherCase(caseValue: TeacherCaseManifest, options: TeacherRunOptions): TeacherRunManifest {
    executeTeacherCase(caseValue, options).run
}

public func executeTeacherCase(caseValue: TeacherCaseManifest, options: TeacherRunOptions): TeacherCaseExecution {
    validateTeacherFailureBinding(caseValue, options)
    if (options.persistAttemptProgress) { return executeTeacherCaseWithProgress(caseValue, options) }
    executeTeacherCaseLegacy(caseValue, options)
}

private func executeTeacherCaseLegacy(caseValue: TeacherCaseManifest, options: TeacherRunOptions): TeacherCaseExecution {
    let paths = TeacherPaths(options.root)
    let started = options.clock.nowMillis()
    var feedback = teacherInitialFailureFeedback(options)
    var generationEvidence = ""
    var verifierEvidence = ""
    var teacherAttempt: Int64 = 0
    while (true) {
        probeTeacherTransportLease(paths.transportLease(options.runId, caseValue.caseId))
        let generated = options.process.generate(caseValue, paths.workspace(options.runId, caseValue.caseId),
            paths.session(options.runId, caseValue.caseId), paths.runtimeHome(options.runId, caseValue.caseId), feedback)
        probeTeacherTransportLease(paths.transportLease(options.runId, caseValue.caseId))
        generationEvidence += generated.output
        if (generated.timedOut || generated.exitCode != 0 || generated.output.isEmpty()) {
            if (options.repairUntilVerified) {
                feedback = "The previous model transport attempt did not produce a valid terminal result. " +
                    "Continue from the current workspace and finish the implementation."
                continue
            }
            let failedAttempt = teacherAttempt + 1
            if (generated.timedOut) { return TeacherCaseExecution(buildTeacherRun(caseValue, options, "timeout", 124, "${started}:timeout", attempt: failedAttempt), generationEvidence, verifierEvidence) }
            if (generated.exitCode != 0) { return TeacherCaseExecution(buildTeacherRun(caseValue, options, "generation_failed", generated.exitCode, generationEvidence, attempt: failedAttempt), generationEvidence, verifierEvidence) }
            return TeacherCaseExecution(buildTeacherRun(caseValue, options, "empty_output", 3, "empty", attempt: failedAttempt), "empty", verifierEvidence)
        }
        teacherAttempt += 1
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

private func executeTeacherCaseWithProgress(caseValue: TeacherCaseManifest,
    options: TeacherRunOptions): TeacherCaseExecution {
    let paths = TeacherPaths(options.root)
    let workspace = paths.workspace(options.runId, caseValue.caseId)
    probeTeacherTransportLease(paths.transportLease(options.runId, caseValue.caseId))
    if (!exists(Path("${workspace}/src"))) { throw IllegalArgumentException("teacher_attempt_workspace_missing") }
    let loaded = loadTeacherAttemptEvidence(options.root, options.runId, caseValue)
    let history = ArrayList<TeacherAttemptEvidence>()
    for (entry in loaded) { history.add(entry) }

    if (!history.isEmpty() && history[history.size - 1].status == "started") {
        let started = history[history.size - 1]
        let currentHash = teacherDirectoryHash("${workspace}/src")
        if (currentHash.isEmpty()) { throw IllegalArgumentException("teacher_attempt_workspace_missing") }
        let prior = ArrayList<TeacherAttemptEvidence>()
        for (i in 0..history.size - 1) { prior.add(history[i]) }
        let interrupted = TeacherAttemptEvidence(started.runId, started.caseId, started.promptHash, started.attempt,
            "interrupted", started.preSolutionHash, currentHash, "generation_interrupted", "",
            teacherAttemptRepeatCount(prior.toArray(), currentHash), started.previousEvidenceHash, "",
            transportCount: started.transportCount, transportRootHash: started.transportRootHash)
        history[history.size - 1] = persistTeacherAttemptCompleted(options.root, caseValue, interrupted, workspace)
    }
    if (!history.isEmpty()) {
        let last = history[history.size - 1]
        if (teacherDirectoryHash("${workspace}/src") != last.solutionHash) {
            throw IllegalArgumentException("teacher_attempt_workspace_mismatch")
        }
        if (last.status == "verified") {
            let chain = teacherAttemptEvidenceChain(history)
            let run = buildTeacherRun(caseValue, options, "verified", 0, chain, attempt: last.attempt)
            return TeacherCaseExecution(run, chain, "resumed_verified_attempt")
        }
    }

    var feedback = if (history.isEmpty()) { teacherInitialFailureFeedback(options) } else {
        let last = history[history.size - 1]
        if (last.status == "verification_failed") { last.verifierDiagnostic }
        else { "The previous model transport attempt did not produce a valid terminal result." }
    }
    var generationEvidence = teacherAttemptEvidenceChain(history)
    var verifierEvidence = ""
    while (true) {
        let teacherAttempt = history.size + 1
        let previousHash = if (history.isEmpty()) { "" } else { teacherAttemptEvidenceHash(history[history.size - 1]) }
        let preHash = teacherDirectoryHash("${workspace}/src")
        if (preHash.isEmpty()) { throw IllegalArgumentException("teacher_attempt_workspace_missing") }
        var generated = TeacherProcessResult(3, "")
        while (true) {
            probeTeacherTransportLease(paths.transportLease(options.runId, caseValue.caseId))
            var transport = loadTeacherTransportEvidence(options.root, options.runId, caseValue, teacherAttempt)
            if (!transport.isEmpty() && transport[transport.size - 1].status == "started") {
                _ = persistTeacherTransportInterrupted(options.root, transport[transport.size - 1])
                transport = loadTeacherTransportEvidence(options.root, options.runId, caseValue, teacherAttempt)
                feedback = "The previous model transport attempt did not produce a valid terminal result."
            }
            let transportAttempt = transport.size + 1
            let transportPrevious = if (transport.isEmpty()) { "" }
                else { teacherTransportEvidenceHash(transport[transport.size - 1]) }
            _ = persistTeacherTransportStarted(options.root, options.runId, caseValue, teacherAttempt,
                transportAttempt, transportPrevious)
            let guidance = teacherAttemptProgressGuidance(teacherAttempt, history.toArray(), feedback)
            generated = options.process.generate(caseValue, workspace, paths.session(options.runId, caseValue.caseId),
                paths.runtimeHome(options.runId, caseValue.caseId), guidance)
            probeTeacherTransportLease(paths.transportLease(options.runId, caseValue.caseId))
            generationEvidence += generated.output
            let startedTransport = parseTeacherTransportEvidence(teacherReadUtf8File(
                teacherTransportManifestPath(options.root, options.runId, caseValue.caseId,
                    teacherAttempt, transportAttempt)))
            _ = persistTeacherTransportCompleted(options.root, startedTransport, generated)
            if (!generated.timedOut && generated.exitCode == 0 && !generated.output.isEmpty()) { break }
            if (!options.repairUntilVerified) {
                let solutionHash = teacherDirectoryHash("${workspace}/src")
                if (solutionHash.isEmpty()) { throw IllegalArgumentException("teacher_attempt_solution_missing") }
                let completedTransport = loadTeacherTransportEvidence(options.root, options.runId,
                    caseValue, teacherAttempt)
                let diagnostic = if (generated.timedOut) { "generation_timeout" }
                    else if (generated.exitCode != 0) { "generation_process_failed" } else { "generation_empty_output" }
                let failed = TeacherAttemptEvidence(options.runId, caseValue.caseId, caseValue.promptHash, teacherAttempt,
                    "transport_failed", preHash, solutionHash, diagnostic, "",
                    teacherAttemptRepeatCount(history.toArray(), solutionHash), previousHash, "",
                    transportCount: completedTransport.size,
                    transportRootHash: teacherTransportChainRootHash(completedTransport))
                history.add(persistTeacherAttemptCompleted(options.root, caseValue, failed, workspace))
                let exit = if (generated.timedOut) { 124 } else if (generated.exitCode != 0) { generated.exitCode } else { 3 }
                return TeacherCaseExecution(buildTeacherRun(caseValue, options, "generation_failed", exit,
                    generationEvidence, attempt: teacherAttempt), generationEvidence, verifierEvidence)
            }
            feedback = "The previous model transport attempt did not produce a valid terminal result."
        }
        _ = persistTeacherAttemptStarted(options.root, options.runId, caseValue, teacherAttempt, previousHash, preHash)
        let solutionHash = teacherDirectoryHash("${workspace}/src")
        if (solutionHash.isEmpty()) { throw IllegalArgumentException("teacher_attempt_solution_missing") }
        let repeatCount = teacherAttemptRepeatCount(history.toArray(), solutionHash)

        let checked = options.verifier.verify(caseValue, workspace)
        verifierEvidence += checked.output
        let safeVerifier = teacherAttemptSafeDiagnostic(checked.output)
        let status = if (checked.exitCode == 0) { "verified" } else { "verification_failed" }
        let transport = loadTeacherTransportEvidence(options.root, options.runId, caseValue, teacherAttempt)
        let completed = TeacherAttemptEvidence(options.runId, caseValue.caseId, caseValue.promptHash, teacherAttempt,
            status, preHash, solutionHash, "generation_ok", safeVerifier, repeatCount, previousHash, "",
            transportCount: transport.size, transportRootHash: teacherTransportChainRootHash(transport))
        history.add(persistTeacherAttemptCompleted(options.root, caseValue, completed, workspace))
        if (checked.exitCode == 0) {
            let chain = teacherAttemptEvidenceChain(history)
            return TeacherCaseExecution(buildTeacherRun(caseValue, options, "verified", 0,
                generationEvidence + verifierEvidence + chain, attempt: teacherAttempt), generationEvidence, verifierEvidence)
        }
        if (!options.repairUntilVerified || checked.timedOut) {
            return TeacherCaseExecution(buildTeacherRun(caseValue, options, "verification_failed", checked.exitCode,
                generationEvidence + verifierEvidence, attempt: teacherAttempt), generationEvidence, verifierEvidence)
        }
        feedback = safeVerifier
    }
    throw IllegalStateException("teacher_repair_progress_loop_unreachable")
}

private func validateTeacherFailureBinding(caseValue: TeacherCaseManifest, options: TeacherRunOptions): Unit {
    match ((options.failureInput, options.failureClassification)) {
        case (Some(input), Some(classification)) =>
            if (input.caseId != caseValue.caseId) { throw IllegalArgumentException("failure_case_binding_mismatch") }
            _ = classifyTeacherOutputKind(input, classification)
        case (None, None) => ()
        case _ => throw IllegalArgumentException("incomplete_teacher_failure_binding")
    }
}

private func teacherInitialFailureFeedback(options: TeacherRunOptions): String {
    match ((options.failureInput, options.failureClassification)) {
        case (Some(input), Some(classification)) =>
            renderTeacherFailureObservationForModel(input, classification)
        case _ => ""
    }
}

private func teacherAttemptEvidenceChain(history: ArrayList<TeacherAttemptEvidence>): String {
    let hashes = ArrayList<String>()
    for (entry in history) { hashes.add(teacherAttemptEvidenceHash(entry)) }
    return teacherJoin(hashes.toArray(), "\n")
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
            if (teacherCompletedRunReusable(old, caseValue, options)) { reusable = Some(old) }
        }
        match (reusable) { case Some(old) => out.add(old); case None => out.add(finalizeTeacherRun(runTeacherCase(caseValue, options), true)) }
    }
    return out.toArray()
}

public func teacherCompletedRunReusable(old: TeacherRunManifest, caseValue: TeacherCaseManifest,
    options: TeacherRunOptions): Bool {
    validateTeacherRunManifest(old) && old.runId == options.runId && old.caseId == caseValue.caseId &&
        old.status == "complete" && old.exitCode == 0 && old.datasetVersion == caseValue.datasetVersion &&
        old.modelId == options.modelId && old.promptHash == caseValue.promptHash &&
        validateTeacherSolutionBinding(options.root, old) &&
        validateTeacherCompletedRunAttemptBinding(options.root, old, caseValue)
}
