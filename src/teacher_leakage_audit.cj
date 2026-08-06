package cangjie_teacher

import std.collection.*

public class LeakageAuditResult {
    public let passed: Bool
    public let violations: Array<String>
    public init(passed: Bool, violations: Array<String>) { this.passed = passed; this.violations = violations }
}

private func normalizedTokens(value: String): Array<String> {
    let out = ArrayList<String>()
    let seen = HashSet<String>()
    let raw = teacherLeakageNormalize(value).split(" ")
    for (token in raw) {
        if (token.toRuneArray().size >= 3 && !seen.contains(token)) { seen.add(token); out.add(token) }
    }
    return out.toArray()
}

private func teacherLeakageNormalize(value: String): String {
    let parts = ArrayList<String>()
    for (part in value.toAsciiLower().replace("\n", " ").replace("\t", " ").replace("\r", " ")
        .replace("(", " ").replace(")", " ").replace("{", " ").replace("}", " ")
        .replace("[", " ").replace("]", " ").replace(",", " ").replace(";", " ")
        .replace(":", " ").replace(".", " ").split(" ")) {
        if (!part.isEmpty()) { parts.add(part) }
    }
    teacherJoin(parts.toArray(), " ")
}

private func teacherLeakageWindowSimilar(material: String, artifactWindow: Array<Rune>): Bool {
    let gramSize: Int64 = if (artifactWindow.size < 24) { 3 } else { 4 }
    if (artifactWindow.size < gramSize) { return false }
    let total = artifactWindow.size - gramSize + 1
    var shared: Int64 = 0
    for (start in 0..total) {
        if (material.contains(String(artifactWindow[start..start + gramSize]))) { shared += 1 }
    }
    shared * 100 >= total * 70
}

public func teacherProtectedArtifactSimilar(material: String, protectedArtifact: String): Bool {
    let normalizedMaterial = teacherLeakageNormalize(material)
    let normalizedArtifact = teacherLeakageNormalize(protectedArtifact)
    let artifactRunes = normalizedArtifact.toRuneArray()
    let artifactTokens = normalizedTokens(normalizedArtifact)
    if (artifactRunes.size < 16) {
        // A protected identifier or visible literal can be a single short
        // token. Exact reuse is still authority leakage; public vocabulary
        // such as "Rune" remains below this distinctive-token threshold.
        return artifactRunes.size >= 8 && normalizedMaterial.contains(normalizedArtifact)
    }
    if (normalizedMaterial.contains(normalizedArtifact)) { return true }

    if (artifactTokens.size == 1 && normalizedArtifact.split(" ").size > 1) { return false }
    if (artifactTokens.size >= 4) {
        var shared: Int64 = 0
        for (token in artifactTokens) { if (normalizedMaterial.contains(token)) { shared += 1 } }
        if (shared * 100 >= artifactTokens.size * 80) { return true }
    }

    let windowSize: Int64 = if (artifactRunes.size < 24) { artifactRunes.size } else { 24 }
    let last = artifactRunes.size - windowSize
    var start: Int64 = 0
    while (start <= last) {
        if (teacherLeakageWindowSimilar(normalizedMaterial,
            artifactRunes[start..start + windowSize])) { return true }
        start += 8
    }
    if (last > 0 && (last % 8) != 0 &&
        teacherLeakageWindowSimilar(normalizedMaterial, artifactRunes[last..last + windowSize])) {
        return true
    }
    false
}

public func auditTextAgainstProtectedArtifacts(body: String,
    protectedArtifacts: Array<String>): LeakageAuditResult {
    let violations = ArrayList<String>()
    for (artifact in protectedArtifacts) {
        if (teacherProtectedArtifactSimilar(body, artifact)) { violations.add("protected_artifact_similarity") }
    }
    LeakageAuditResult(violations.isEmpty(), violations.toArray())
}

public func auditCandidateAgainstSolutions(candidate: TeacherCandidateExport, protectedArtifacts: Array<String>): LeakageAuditResult {
    let body = "${candidate.explanation}\n${candidate.example}\n${candidate.tests.positive}\n${candidate.tests.negative}\n${candidate.tests.boundary}".toAsciiLower()
    auditTextAgainstProtectedArtifacts(body, protectedArtifacts)
}

public func auditCaseSpecificity(candidate: TeacherCandidateExport, signatures: Array<String>): LeakageAuditResult {
    let body = "${candidate.concept}\n${candidate.explanation}\n${candidate.example}\n${candidate.tests.positive}\n${candidate.tests.negative}\n${candidate.tests.boundary}".toAsciiLower()
    let violations = ArrayList<String>()
    if (body.contains("cj-humaneval-") || body.contains("expectedoutput") || body.contains("hidden_test") ||
        body.contains("reference solution") || body.contains("assertion line") ||
        body.contains("rerun the test") || body.contains("compiler repair")) { violations.add("case_marker") }
    for (signature in signatures) { if (!signature.isEmpty() && body.contains(signature.toAsciiLower())) { violations.add("case_signature") } }
    return LeakageAuditResult(violations.isEmpty(), violations.toArray())
}

public func validateStudentVisibleMaterialAgainstAuthority(material: String, caseValue: TeacherCaseManifest,
    protectedArtifacts: Array<String>): Bool {
    let authority = ArrayList<String>()
    for (value in [caseValue.caseId, caseValue.prompt, caseValue.signature]) { authority.add(value) }
    for (value in protectedArtifacts) { authority.add(value) }
    auditTextAgainstProtectedArtifacts(material, authority.toArray()).passed
}

public func validateTeacherCandidateAgainstAuthority(candidate: TeacherCandidateExport, bundle: String,
    caseValue: TeacherCaseManifest, protectedArtifacts: Array<String>): Bool {
    let material = teacherJoin([candidate.identity, candidate.knowledgeFamily, candidate.concept,
        candidate.targetVersion, candidate.explanation, candidate.example, candidate.citation,
        candidate.sourceClass, candidate.provenanceHash, candidate.tests.positive,
        candidate.tests.negative, candidate.tests.boundary, bundle], "\n")
    validateStudentVisibleMaterialAgainstAuthority(material, caseValue, protectedArtifacts)
}
