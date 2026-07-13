package cangjie_teacher

public class TeacherEvidenceEntry {
    public let locator: String
    public let hash: String
    public init(locator: String, hash: String) { this.locator = locator; this.hash = hash }
}

public func writeRunManifest(run: TeacherRunManifest): String {
    return teacherJoin([run.runId, run.caseId, run.datasetVersion, run.modelId, run.promptHash,
        run.attempt.toString(), run.status, run.exitCode.toString(), run.evidenceHash], "\t")
}

public func verifyEvidenceIndex(entries: Array<TeacherEvidenceEntry>, contents: Array<String>): Bool {
    if (entries.size != contents.size || entries.isEmpty()) { return false }
    for (i in 0..entries.size) {
        if (entries[i].locator.isEmpty() || entries[i].hash != teacherStableHash(contents[i])) { return false }
    }
    return true
}
