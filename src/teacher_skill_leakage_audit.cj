package cangjie_teacher

import std.collection.*

private func teacherSkillAuditBody(value: TeacherSkillCandidate): String {
    let fixtureBodies = value.tests.fixtures.map({fixture: TeacherSkillFixture =>
        "${fixture.fixtureId}\n${fixture.task}\n${fixture.expectedEvidence}"})
    teacherJoin([value.skillId, value.version, value.title, value.sourceCategory, value.applicability,
        value.lineage, value.procedure,
        teacherJoin(fixtureBodies, "\n")], "\n")
}

public func auditSkillAgainstProtectedArtifacts(value: TeacherSkillCandidate,
    protectedArtifacts: Array<String>): LeakageAuditResult {
    let body = teacherSkillAuditBody(value)
    let violations = ArrayList<String>()
    let protected = auditTextAgainstProtectedArtifacts(body, protectedArtifacts)
    for (violation in protected.violations) { violations.add(violation) }
    let lower = body.toAsciiLower()
    for (marker in ["cj-humaneval-", "hidden_test", "expectedoutput", "reference solution",
        "teacher-solutions", "student solution", "compiler repair", "rerun the test"]) {
        if (lower.contains(marker)) { violations.add("skill_case_specificity") }
    }
    LeakageAuditResult(violations.isEmpty(), violations.toArray())
}

public func auditSkillCombinationLeakage(value: TeacherSkillCandidate, knowledgeMaterial: String,
    protectedArtifacts: Array<String>): LeakageAuditResult {
    let combined = "${teacherSkillAuditBody(value)}\n${knowledgeMaterial}"
    let violations = ArrayList<String>()
    let protected = auditTextAgainstProtectedArtifacts(combined, protectedArtifacts)
    for (violation in protected.violations) { violations.add("combined_${violation}") }
    LeakageAuditResult(violations.isEmpty(), violations.toArray())
}

public func validateSkillGeneralizationEvidence(value: TeacherSkillCandidate): Bool {
    if (value.tests.fixtures.size < 3) { return false }
    let ids = HashSet<String>()
    for (fixture in value.tests.fixtures) {
        let body = "${fixture.fixtureId}\n${fixture.task}\n${fixture.expectedEvidence}".toAsciiLower()
        if (fixture.sourceClass != "non_humaneval" || fixture.fixtureId.isEmpty() ||
            fixture.task.isEmpty() || fixture.expectedEvidence.isEmpty() || ids.contains(fixture.fixtureId) ||
            body.contains("humaneval") || body.contains("hidden_test") || body.contains("expectedoutput")) {
            return false
        }
        ids.add(fixture.fixtureId)
    }
    let canonical = teacherJoin(value.tests.fixtures.map({fixture: TeacherSkillFixture =>
        teacherJoin([fixture.fixtureId, fixture.task, fixture.expectedEvidence, fixture.sourceClass], "\u{1f}")}), "\n")
    value.tests.evidenceHash == "sha256:${teacherStableHash(canonical)}"
}
