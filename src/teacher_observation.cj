package cangjie_teacher

import std.collection.*

public func deriveKnowledgeObservation(caseValue: TeacherCaseManifest, family: String, concept: String,
    targetVersion: String, explanation: String, citation: String, sourceClass: String, evidence: String): TeacherObservation {
    let observation = TeacherObservation(caseValue.caseId, family, concept, targetVersion, explanation, citation,
        sourceClass, teacherStableHash(evidence))
    if (!validateObservationAgainstAuthority(observation, caseValue, [])) {
        throw IllegalArgumentException("teacher_observation_authority_leak")
    }
    observation
}

public func validateObservationNoSolutionLeak(observation: TeacherObservation): Bool {
    if (!validateTeacherObservation(observation)) { return false }
    let all = "${observation.concept}\n${observation.explanation}\n${observation.citation}".toAsciiLower()
    let forbidden = ["cj-humaneval-", "teacher-solutions", "teacher-tests", "/reference", "expectedoutput",
        "func solution", "hidden_test", "tasktext", "visibletestexcerpt", "compileroutput"]
    for (word in forbidden) { if (all.contains(word)) { return false } }
    if (observation.explanation.split("\n").size > 20 || observation.explanation.toRuneArray().size > 4000) { return false }
    return true
}

public func validateObservationAgainstAuthority(observation: TeacherObservation, caseValue: TeacherCaseManifest,
    protectedArtifacts: Array<String>): Bool {
    if (!validateObservationNoSolutionLeak(observation) || observation.caseId != caseValue.caseId) { return false }
    let body = "${observation.concept}\n${observation.explanation}\n${observation.citation}".toAsciiLower()
    let authority = [caseValue.caseId, caseValue.prompt, caseValue.signature]
    for (raw in authority) {
        if (teacherObservationContainsProtectedFragment(body, raw)) { return false }
    }
    for (raw in protectedArtifacts) {
        if (teacherObservationContainsProtectedFragment(body, raw)) { return false }
    }
    let allProtected = ArrayList<String>()
    for (raw in authority) { allProtected.add(raw) }
    for (raw in protectedArtifacts) { allProtected.add(raw) }
    auditTextAgainstProtectedArtifacts(body, allProtected.toArray()).passed
}

private func teacherObservationNormalize(value: String): String {
    let parts = ArrayList<String>()
    for (part in value.toAsciiLower().replace("\n", " ").replace("\t", " ").replace("\r", " ")
        .replace("(", " ").replace(")", " ").replace("{", " ").replace("}", " ")
        .replace(",", " ").replace(";", " ").split(" ")) {
        if (!part.isEmpty()) { parts.add(part) }
    }
    teacherJoin(parts.toArray(), " ")
}

private func teacherObservationContainsProtectedFragment(body: String, protectedArtifact: String): Bool {
    let normalizedBody = teacherObservationNormalize(body)
    let normalizedArtifact = teacherObservationNormalize(protectedArtifact)
    let artifactRunes = normalizedArtifact.toRuneArray()
    if (artifactRunes.size < 16) { return false }
    if (normalizedBody.contains(normalizedArtifact)) { return true }
    let windowSize: Int64 = 48
    if (artifactRunes.size < windowSize) { return false }
    for (start in 0..=artifactRunes.size - windowSize) {
        if (normalizedBody.contains(String(artifactRunes[start..start + windowSize]))) { return true }
    }
    false
}
