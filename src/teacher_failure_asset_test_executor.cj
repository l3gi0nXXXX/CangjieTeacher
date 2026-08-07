package cangjie_teacher

import std.collection.*
import std.sort.*

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
    public let transcript: String
    public init(fixture: TeacherAssetFixture, fixtureHash: String, executorKind: String,
        providerIdentityHash: String, modelVersion: String, actualEvidence: String,
        transcriptHash: String, exitCode: Int64, passed: Bool, transcript!: String = "") {
        this.fixture = fixture; this.fixtureHash = fixtureHash; this.executorKind = executorKind
        this.providerIdentityHash = providerIdentityHash; this.modelVersion = modelVersion
        this.actualEvidence = actualEvidence; this.transcriptHash = transcriptHash
        this.exitCode = exitCode; this.passed = passed; this.transcript = transcript
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

// Transcript semantics normalize line endings and trailing line breaks without trimming spaces.
public func teacherTranscriptSemantic(value: String): String {
    let normalized = value.replace("\r\n", "\n").replace("\r", "\n")
    let runes = normalized.toRuneArray(); var end = runes.size
    while (end > 0 && runes[end - 1] == r'\n') { end -= 1 }
    if (end == 0) { "" } else { String(runes[..end]) }
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
        let transcript = teacherTranscriptSemantic(executed[2])
        let transcriptHash = "sha256:${teacherStableHash(transcript)}"
        out.add(TeacherAssetFixtureExecution(fixture, fixtureHash, executor.executorKind(),
            executor.providerIdentityHash(), executor.modelVersion(), executed[1], transcriptHash,
            executed[0], passed, transcript: transcript))
    }
    out.toArray()
}

public func teacherAssetFixtureHash(value: TeacherAssetFixture): String {
    "sha256:${teacherStableHash(teacherFixtureCanonical(value))}"
}

// Candidate writers and readers select repeated categories by the same stable fixture-id order.
public func teacherFirstEvidenceHashByFixtureId(
    entries: Array<(String, String, String)>, kind: String): String {
    let ids = ArrayList<String>()
    for (entry in entries) { if (entry[1] == kind) { ids.add(entry[0]) } }
    let sortedIds = ids.toArray(); sort(sortedIds)
    if (sortedIds.isEmpty()) { return "" }
    for (entry in entries) {
        if (entry[0] == sortedIds[0] && entry[1] == kind) { return entry[2] }
    }
    ""
}

public func renderTeacherAssetFixture(value: TeacherAssetFixture): String {
    let hash = teacherAssetFixtureHash(value)
    "{\"schemaVersion\":\"teacher-asset-fixture-v1\",\"fixtureId\":\"${teacherFixtureExecutionEscape(value.fixtureId)}\"," +
        "\"kind\":\"${value.kind}\",\"sourceClass\":\"${value.sourceClass}\"," +
        "\"content\":\"${teacherFixtureExecutionEscape(value.content)}\"," +
        "\"expectedEvidence\":\"${teacherFixtureExecutionEscape(value.expectedEvidence)}\"," +
        "\"fixtureHash\":\"${hash}\"}"
}

public func teacherAssetFixtureExecutionFiles(value: TeacherAssetFixtureExecution,
    prefix: String): Array<TeacherArtifactFile> {
    let transcript = teacherTranscriptSemantic(value.transcript)
    if (value.fixtureHash != teacherAssetFixtureHash(value.fixture) ||
        value.transcriptHash != "sha256:${teacherStableHash(transcript)}" ||
        value.fixture.expectedEvidence.contains("\r") || value.fixture.expectedEvidence.endsWith("\n") ||
        value.actualEvidence.contains("\r") || value.actualEvidence.endsWith("\n") ||
        value.passed != (value.exitCode == 0 && value.actualEvidence == value.fixture.expectedEvidence)) {
        throw IllegalArgumentException("candidate_test_evidence_invalid")
    }
    [
        TeacherArtifactFile("${prefix}/fixture.json", renderTeacherAssetFixture(value.fixture) + "\n"),
        TeacherArtifactFile("${prefix}/expected.txt", value.fixture.expectedEvidence + "\n"),
        TeacherArtifactFile("${prefix}/actual.txt", value.actualEvidence + "\n"),
        TeacherArtifactFile("${prefix}/transcript.txt", transcript + "\n"),
        TeacherArtifactFile("${prefix}/execution.json", renderTeacherAssetFixtureExecution(value) + "\n")
    ]
}

private func teacherFixtureExecutionEscape(value: String): String {
    value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
}

public func renderTeacherAssetFixtureExecution(value: TeacherAssetFixtureExecution): String {
    if (!value.fixtureHash.startsWith("sha256:") || !value.transcriptHash.startsWith("sha256:") ||
        value.transcriptHash != "sha256:${teacherStableHash(teacherTranscriptSemantic(value.transcript))}" ||
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
