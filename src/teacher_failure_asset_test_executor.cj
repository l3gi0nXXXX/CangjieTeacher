package cangjie_teacher

import std.collection.*

public class TeacherAssetFixture {
    public let fixtureId: String
    public let kind: String
    public let sourceClass: String
    public let content: String
    public let expectedEvidence: String
    public init(fixtureId: String, kind: String, sourceClass: String, content: String,
        expectedEvidence: String) {
        this.fixtureId = fixtureId; this.kind = kind; this.sourceClass = sourceClass
        this.content = content; this.expectedEvidence = expectedEvidence
    }
}

public class TeacherAssetFixtureExecution {
    public let fixture: TeacherAssetFixture
    public let fixtureHash: String
    public let executorKind: String
    public let providerIdentityHash: String
    public let modelVersion: String
    public let actualEvidence: String
    public let transcriptHash: String
    public let exitCode: Int64
    public let passed: Bool
    public init(fixture: TeacherAssetFixture, fixtureHash: String, executorKind: String,
        providerIdentityHash: String, modelVersion: String, actualEvidence: String,
        transcriptHash: String, exitCode: Int64, passed: Bool) {
        this.fixture = fixture; this.fixtureHash = fixtureHash; this.executorKind = executorKind
        this.providerIdentityHash = providerIdentityHash; this.modelVersion = modelVersion
        this.actualEvidence = actualEvidence; this.transcriptHash = transcriptHash
        this.exitCode = exitCode; this.passed = passed
    }
}

public interface TeacherAssetFixtureExecutor {
    func executorKind(): String
    func providerIdentityHash(): String
    func modelVersion(): String
    func execute(fixture: TeacherAssetFixture): (Int64, String, String)
}

public class FakeTeacherAssetFixtureExecutor <: TeacherAssetFixtureExecutor {
    public func executorKind(): String { "fake_contract" }
    public func providerIdentityHash(): String { "sha256:${teacherStableHash("fake-contract-provider")}" }
    public func modelVersion(): String { "fake-scaffold-v1" }
    public func execute(fixture: TeacherAssetFixture): (Int64, String, String) {
        (0, fixture.expectedEvidence, "fake execution completed for ${fixture.kind}")
    }
}

private func teacherFixtureCanonical(value: TeacherAssetFixture): String {
    teacherJoin([value.fixtureId, value.kind, value.sourceClass, value.content,
        value.expectedEvidence].map({v: String => "${v.toArray().size}:${v}"}), "")
}

private func teacherFixtureSafe(value: String): Bool {
    let lower = value.toAsciiLower()
    !lower.contains("cj-humaneval-") && !lower.contains("hidden_test") &&
        !lower.contains("reference solution") && !lower.contains("/users/") &&
        !lower.contains("authorization") && !lower.contains("token=")
}

public func executeTeacherAssetFixtureBundle(fixtures: Array<TeacherAssetFixture>,
    executor: TeacherAssetFixtureExecutor): Array<TeacherAssetFixtureExecution> {
    if (fixtures.isEmpty() || !["fake_contract", "student_completion_non_humaneval"].contains(executor.executorKind())) {
        throw IllegalArgumentException("candidate_test_evidence_invalid")
    }
    let ids = HashSet<String>(); let out = ArrayList<TeacherAssetFixtureExecution>()
    for (fixture in fixtures) {
        if (fixture.fixtureId.isEmpty() || ids.contains(fixture.fixtureId) ||
            !["unit", "positive", "negative", "boundary", "generalization"].contains(fixture.kind) ||
            !["official", "community", "non_humaneval_experiment"].contains(fixture.sourceClass) ||
            fixture.content.isEmpty() || fixture.expectedEvidence.isEmpty() ||
            !teacherFixtureSafe(fixture.content + fixture.expectedEvidence)) {
            throw IllegalArgumentException("candidate_test_evidence_invalid")
        }
        ids.add(fixture.fixtureId)
        let fixtureHash = "sha256:${teacherStableHash(teacherFixtureCanonical(fixture))}"
        let executed = executor.execute(fixture)
        let passed = executed[0] == 0 && executed[1] == fixture.expectedEvidence
        let transcriptHash = "sha256:${teacherStableHash(executed[2])}"
        out.add(TeacherAssetFixtureExecution(fixture, fixtureHash, executor.executorKind(),
            executor.providerIdentityHash(), executor.modelVersion(), executed[1], transcriptHash,
            executed[0], passed))
    }
    out.toArray()
}

private func teacherFixtureExecutionEscape(value: String): String {
    value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
}

public func renderTeacherAssetFixtureExecution(value: TeacherAssetFixtureExecution): String {
    if (!value.fixtureHash.startsWith("sha256:") || !value.transcriptHash.startsWith("sha256:") ||
        !value.providerIdentityHash.startsWith("sha256:") ||
        !["fake_contract", "student_completion_non_humaneval"].contains(value.executorKind)) {
        throw IllegalArgumentException("candidate_test_evidence_invalid")
    }
    let expectedHash = "sha256:${teacherStableHash(value.fixture.expectedEvidence)}"
    let actualHash = "sha256:${teacherStableHash(value.actualEvidence)}"
    "{\"schemaVersion\":\"teacher-candidate-fixture-execution-v1\"," +
        "\"fixtureId\":\"${teacherFixtureExecutionEscape(value.fixture.fixtureId)}\"," +
        "\"kind\":\"${value.fixture.kind}\",\"sourceClass\":\"${value.fixture.sourceClass}\"," +
        "\"fixtureHash\":\"${value.fixtureHash}\",\"executorKind\":\"${value.executorKind}\"," +
        "\"providerIdentityHash\":\"${value.providerIdentityHash}\",\"modelVersion\":\"${value.modelVersion}\"," +
        "\"expectedEvidenceHash\":\"${expectedHash}\",\"actualEvidenceHash\":\"${actualHash}\"," +
        "\"transcriptHash\":\"${value.transcriptHash}\",\"exitCode\":${value.exitCode},\"passed\":${value.passed}}"
}
