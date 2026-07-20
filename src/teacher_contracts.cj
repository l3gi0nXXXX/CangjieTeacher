package cangjie_teacher

import std.collection.*
import std.convert.Parsable

public let TEACHER_SCHEMA_VERSION = "teacher/v1"

public func teacherJoin(values: Array<String>, separator: String): String {
    var out = ""
    for (i in 0..values.size) { if (i > 0) { out += separator }; out += values[i] }
    return out
}

public class TeacherCaseManifest {
    public let caseId: String
    public let datasetVersion: String
    public let promptHash: String
    public let starterHash: String
    public let signature: String
    public let verifierHash: String
    public let prompt: String
    public let targetVersion: String
    public let requiredKnowledgeTags: Array<String>
    public init(caseId: String, datasetVersion: String, promptHash: String, starterHash: String,
        signature: String, verifierHash: String, prompt!: String = "", targetVersion!: String = "",
        requiredKnowledgeTags!: Array<String> = []) {
        this.caseId = caseId; this.datasetVersion = datasetVersion; this.promptHash = promptHash
        this.starterHash = starterHash; this.signature = signature; this.verifierHash = verifierHash
        this.prompt = prompt; this.targetVersion = targetVersion; this.requiredKnowledgeTags = requiredKnowledgeTags
    }
}

public class TeacherDatasetManifest {
    public let schemaVersion: String
    public let datasetVersion: String
    public let cases: Array<TeacherCaseManifest>
    public init(datasetVersion: String, cases: Array<TeacherCaseManifest>, schemaVersion!: String = TEACHER_SCHEMA_VERSION) {
        this.schemaVersion = schemaVersion; this.datasetVersion = datasetVersion; this.cases = cases
    }
}

public class TeacherRunManifest {
    public let runId: String
    public let caseId: String
    public let datasetVersion: String
    public let modelId: String
    public let promptHash: String
    public let attempt: Int64
    public let status: String
    public let exitCode: Int64
    public let evidenceHash: String
    public init(runId: String, caseId: String, datasetVersion: String, modelId: String, promptHash: String,
        attempt: Int64, status: String, exitCode: Int64, evidenceHash: String) {
        this.runId = runId; this.caseId = caseId; this.datasetVersion = datasetVersion; this.modelId = modelId
        this.promptHash = promptHash; this.attempt = attempt; this.status = status; this.exitCode = exitCode
        this.evidenceHash = evidenceHash
    }
}

public class TeacherObservation {
    public let caseId: String
    public let knowledgeFamily: String
    public let concept: String
    public let targetVersion: String
    public let explanation: String
    public let citation: String
    public let sourceClass: String
    public let evidenceHash: String
    public init(caseId: String, knowledgeFamily: String, concept: String, targetVersion: String,
        explanation: String, citation: String, sourceClass: String, evidenceHash: String) {
        this.caseId = caseId; this.knowledgeFamily = knowledgeFamily; this.concept = concept
        this.targetVersion = targetVersion; this.explanation = explanation; this.citation = citation
        this.sourceClass = sourceClass; this.evidenceHash = evidenceHash
    }
}

public class KnowledgeAtomTestBundle {
    public let positive: String
    public let negative: String
    public let boundary: String
    public init(positive: String, negative: String, boundary: String) {
        this.positive = positive; this.negative = negative; this.boundary = boundary
    }
    public func isComplete(): Bool { !positive.isEmpty() && !negative.isEmpty() && !boundary.isEmpty() }
}

public class TeacherCandidateExport {
    public let identity: String
    public let knowledgeFamily: String
    public let concept: String
    public let targetVersion: String
    public let explanation: String
    public let example: String
    public let citation: String
    public let sourceClass: String
    public let provenanceHash: String
    public let tests: KnowledgeAtomTestBundle
    public init(identity: String, knowledgeFamily: String, concept: String, targetVersion: String,
        explanation: String, example: String, citation: String, sourceClass: String,
        provenanceHash: String, tests: KnowledgeAtomTestBundle) {
        this.identity = identity; this.knowledgeFamily = knowledgeFamily; this.concept = concept
        this.targetVersion = targetVersion; this.explanation = explanation; this.example = example
        this.citation = citation; this.sourceClass = sourceClass; this.provenanceHash = provenanceHash; this.tests = tests
    }
}

private func escapeField(value: String): String {
    return value.replace("%", "%25").replace("\t", "%09").replace("\n", "%0A")
}
private func unescapeField(value: String): String {
    return value.replace("%0A", "\n").replace("%09", "\t").replace("%25", "%")
}

public func renderTeacherCaseManifest(value: TeacherCaseManifest): String {
    return teacherJoin([value.caseId, value.datasetVersion, value.promptHash, value.starterHash, value.signature, value.verifierHash]
        .map({s: String => escapeField(s)}), "\t")
}
public func parseTeacherCaseManifest(text: String): TeacherCaseManifest {
    let f = text.split("\t").map({s: String => unescapeField(s)}).toArray()
    if (f.size != 6) { throw IllegalArgumentException("malformed_teacher_case_manifest") }
    return TeacherCaseManifest(f[0], f[1], f[2], f[3], f[4], f[5])
}
public func validateTeacherCaseManifest(value: TeacherCaseManifest): Bool {
    value.caseId.startsWith("CJ-HUMANEVAL-") && !value.datasetVersion.isEmpty() &&
        !value.promptHash.isEmpty() && !value.signature.isEmpty() && !value.starterHash.isEmpty()
}
public func renderTeacherObservation(value: TeacherObservation): String {
    return teacherJoin([value.caseId, value.knowledgeFamily, value.concept, value.targetVersion, value.explanation,
        value.citation, value.sourceClass, value.evidenceHash].map({s: String => escapeField(s)}), "\t")
}
public func parseTeacherObservation(text: String): TeacherObservation {
    let f = text.split("\t").map({s: String => unescapeField(s)}).toArray()
    if (f.size != 8) { throw IllegalArgumentException("malformed_teacher_observation") }
    return TeacherObservation(f[0], f[1], f[2], f[3], f[4], f[5], f[6], f[7])
}
public func validateTeacherObservation(value: TeacherObservation): Bool {
    let families = ["language", "standard_library", "type_adaptation", "algorithm_pattern", "diagnostic", "boundary_check",
        "syntax", "stdx", "toolchain", "compiler_diagnostic", "version_migration", "engineering_practice"]
    let sourceValid = (value.sourceClass == "official" || value.sourceClass == "approved") && !value.citation.isEmpty() ||
        value.sourceClass == "teacher_empirical" && value.citation.isEmpty()
    return families.contains(value.knowledgeFamily) && !value.concept.isEmpty() && !value.targetVersion.isEmpty() && sourceValid
}

public func renderTeacherRunManifest(value: TeacherRunManifest): String {
    return teacherJoin([value.runId, value.caseId, value.datasetVersion, value.modelId, value.promptHash,
        value.attempt.toString(), value.status, value.exitCode.toString(), value.evidenceHash]
        .map({s: String => escapeField(s)}), "\t")
}
public func parseTeacherRunManifest(text: String): TeacherRunManifest {
    let f = text.split("\t").map({s: String => unescapeField(s)}).toArray()
    if (f.size != 9) { throw IllegalArgumentException("malformed_teacher_run_manifest") }
    return TeacherRunManifest(f[0], f[1], f[2], f[3], f[4], Int64.parse(f[5]), f[6], Int64.parse(f[7]), f[8])
}
public func validateTeacherRunManifest(value: TeacherRunManifest): Bool {
    !value.runId.isEmpty() && value.caseId.startsWith("CJ-HUMANEVAL-") && !value.datasetVersion.isEmpty() &&
        !value.modelId.isEmpty() && value.attempt >= 1 && !value.status.isEmpty() && !value.evidenceHash.isEmpty()
}

public func renderTeacherDatasetManifest(value: TeacherDatasetManifest): String {
    return teacherJoin(value.cases.map({c: TeacherCaseManifest => renderTeacherCaseManifest(c)}), "\n")
}

public func validateTeacherCandidateExport(value: TeacherCandidateExport): Bool {
    !value.identity.isEmpty() && !value.knowledgeFamily.isEmpty() && !value.concept.isEmpty() &&
        !value.targetVersion.isEmpty() && !value.explanation.isEmpty() &&
        (((value.sourceClass == "official" || value.sourceClass == "approved") && !value.citation.isEmpty()) ||
            (value.sourceClass == "teacher_empirical" && value.citation.isEmpty())) &&
        !value.provenanceHash.isEmpty() && value.tests.isComplete()
}
public func renderTeacherCandidateExport(value: TeacherCandidateExport): String {
    if (!validateTeacherCandidateExport(value)) { throw IllegalArgumentException("invalid_teacher_candidate_export") }
    return teacherJoin([value.identity, value.knowledgeFamily, value.concept, value.targetVersion, value.explanation,
        value.example, value.citation, value.sourceClass, value.provenanceHash, value.tests.positive,
        value.tests.negative, value.tests.boundary].map({s: String => escapeField(s)}), "\t")
}
public func parseTeacherCandidateExport(text: String): TeacherCandidateExport {
    let f = text.split("\t").map({s: String => unescapeField(s)}).toArray()
    if (f.size != 12) { throw IllegalArgumentException("malformed_teacher_candidate_export") }
    let value = TeacherCandidateExport(f[0], f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8], KnowledgeAtomTestBundle(f[9], f[10], f[11]))
    if (!validateTeacherCandidateExport(value)) { throw IllegalArgumentException("invalid_teacher_candidate_export") }
    return value
}
