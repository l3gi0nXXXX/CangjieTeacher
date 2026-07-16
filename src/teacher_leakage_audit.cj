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
    let raw = value.toAsciiLower().replace("(", " ").replace(")", " ").replace("{", " ").replace("}", " ")
        .replace(",", " ").replace(";", " ").split(" ")
    for (token in raw) { if (token.size >= 5 && !seen.contains(token)) { seen.add(token); out.add(token) } }
    return out.toArray()
}

public func auditCandidateAgainstSolutions(candidate: TeacherCandidateExport, protectedArtifacts: Array<String>): LeakageAuditResult {
    let body = "${candidate.explanation}\n${candidate.example}\n${candidate.tests.positive}\n${candidate.tests.negative}\n${candidate.tests.boundary}".toAsciiLower()
    let violations = ArrayList<String>()
    for (artifact in protectedArtifacts) {
        let tokens = normalizedTokens(artifact)
        var shared: Int64 = 0
        for (token in tokens) { if (body.contains(token)) { shared++ } }
        if (shared >= 8 || (!artifact.isEmpty() && body.contains(artifact.toAsciiLower()))) { violations.add("protected_artifact_similarity") }
    }
    return LeakageAuditResult(violations.isEmpty(), violations.toArray())
}

public func auditCaseSpecificity(candidate: TeacherCandidateExport, signatures: Array<String>): LeakageAuditResult {
    let body = "${candidate.concept}\n${candidate.explanation}\n${candidate.example}\n${candidate.tests.positive}\n${candidate.tests.negative}\n${candidate.tests.boundary}".toAsciiLower()
    let violations = ArrayList<String>()
    if (body.contains("cj-humaneval-") || body.contains("expectedoutput") || body.contains("hidden_test")) { violations.add("case_marker") }
    for (signature in signatures) { if (!signature.isEmpty() && body.contains(signature.toAsciiLower())) { violations.add("case_signature") } }
    return LeakageAuditResult(violations.isEmpty(), violations.toArray())
}
