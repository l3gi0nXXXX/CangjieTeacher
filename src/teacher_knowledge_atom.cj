package cangjie_teacher

import std.collection.*

public func normalizeObservation(value: TeacherObservation): TeacherObservation {
    return TeacherObservation(value.caseId, value.knowledgeFamily.toAsciiLower(), value.concept.toAsciiLower(),
        value.targetVersion, value.explanation, value.citation, value.sourceClass.toAsciiLower(), value.evidenceHash)
}
public func canonicalKnowledgeIdentity(value: TeacherObservation): String {
    let n = normalizeObservation(value)
    return teacherStableHash("${n.knowledgeFamily}|${n.concept}|${n.targetVersion}")
}

public class KnowledgeMergeResult {
    public let observations: Array<TeacherObservation>
    public let reviewRequired: Bool
    public init(observations: Array<TeacherObservation>, reviewRequired: Bool) { this.observations = observations; this.reviewRequired = reviewRequired }
}
public func mergeKnowledgeObservations(values: Array<TeacherObservation>): KnowledgeMergeResult {
    if (values.isEmpty()) { return KnowledgeMergeResult([], false) }
    let identity = canonicalKnowledgeIdentity(values[0])
    var review = false
    for (value in values) {
        if (canonicalKnowledgeIdentity(value) != identity || value.explanation != values[0].explanation || value.citation != values[0].citation) { review = true }
    }
    return KnowledgeMergeResult(values, review)
}
public func buildKnowledgeAtomTestBundle(positive: String, negative: String, boundary: String): KnowledgeAtomTestBundle {
    return KnowledgeAtomTestBundle(positive, negative, boundary)
}
public func renderCandidateKnowledgeExport(observation: TeacherObservation, example: String,
    tests: KnowledgeAtomTestBundle): TeacherCandidateExport {
    if (!validateObservationNoSolutionLeak(observation) || !tests.isComplete()) { throw IllegalArgumentException("candidate_not_exportable") }
    return TeacherCandidateExport(canonicalKnowledgeIdentity(observation), observation.knowledgeFamily, observation.concept,
        observation.targetVersion, observation.explanation, example, observation.citation, observation.sourceClass,
        teacherStableHash(renderTeacherObservation(observation)), tests)
}
