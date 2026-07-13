package cangjie_teacher

public func deriveKnowledgeObservation(caseValue: TeacherCaseManifest, family: String, concept: String,
    targetVersion: String, explanation: String, citation: String, sourceClass: String, evidence: String): TeacherObservation {
    return TeacherObservation(caseValue.caseId, family, concept, targetVersion, explanation, citation,
        sourceClass, teacherStableHash(evidence))
}

public func validateObservationNoSolutionLeak(observation: TeacherObservation): Bool {
    if (!validateTeacherObservation(observation)) { return false }
    let all = "${observation.concept}\n${observation.explanation}\n${observation.citation}".toAsciiLower()
    let forbidden = ["cj-humaneval-", "teacher-solutions", "teacher-tests", "/reference", "expectedoutput", "func solution", "hidden_test"]
    for (word in forbidden) { if (all.contains(word)) { return false } }
    if (observation.explanation.split("\n").size > 20 || observation.explanation.toRuneArray().size > 4000) { return false }
    return true
}

