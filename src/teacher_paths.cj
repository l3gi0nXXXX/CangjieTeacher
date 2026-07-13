package cangjie_teacher

public class TeacherPaths {
    public let root: String
    public init(root: String) { this.root = root.trimEnd('/') }
    public func solution(caseId: String): String { "${root}/teacher-solutions/${caseId}" }
    public func observation(caseId: String): String { "${root}/observations/${caseId}" }
    public func workspace(runId: String, caseId: String): String { "${root}/runs/${runId}/workspaces/${caseId}" }
    public func session(runId: String, caseId: String): String { "${root}/runs/${runId}/sessions/${caseId}" }
    public func runtimeHome(runId: String, caseId: String): String { "${root}/runs/${runId}/runtime-home/${caseId}" }
    public func candidateExport(): String { "${root}/candidate-knowledge" }
}

public func validateTeacherPathBoundary(root: String, candidate: String, caseId!: String = ""): Bool {
    let normalizedRoot = root.trimEnd('/')
    if (!candidate.startsWith(normalizedRoot + "/") || candidate.contains("/../") || candidate.endsWith("/..")) { return false }
    let forbidden = ["CangjieCommunityKnowledgeBase", "ckb-data", ".metis", "teacher-solutions/local-only"]
    for (part in forbidden) { if (candidate.contains(part)) { return false } }
    if (!caseId.isEmpty() && candidate.contains("CJ-HUMANEVAL-") && !candidate.contains(caseId)) { return false }
    return true
}

