package cangjie_teacher

import std.collection.*
import stdx.encoding.json.*

public class TeacherFrozenKnowledgeReference {
    public let knowledgeCandidateHash: String
    public let knowledgeVersion: String
    public let frozenCandidateManifestHash: String
    public let knowledgeContentHash: String
    public let assetLineage: String
    public let raw: String
    public init(knowledgeCandidateHash: String, knowledgeVersion: String,
        frozenCandidateManifestHash: String, knowledgeContentHash: String,
        assetLineage: String, raw: String) {
        this.knowledgeCandidateHash = knowledgeCandidateHash; this.knowledgeVersion = knowledgeVersion
        this.frozenCandidateManifestHash = frozenCandidateManifestHash
        this.knowledgeContentHash = knowledgeContentHash; this.assetLineage = assetLineage; this.raw = raw
    }
}

public class TeacherFailureKnowledgeRequest {
    public let missingKnowledge: String
    public let authorityEvidence: String
    public let atomBundle: String
    public let frozenReference: String
    public let workspaceRoot: String
    public let protectedArtifacts: Array<String>
    public init(missingKnowledge: String, authorityEvidence: String, atomBundle: String,
        frozenReference: String, workspaceRoot: String, protectedArtifacts: Array<String>) {
        this.missingKnowledge = missingKnowledge; this.authorityEvidence = authorityEvidence
        this.atomBundle = atomBundle; this.frozenReference = frozenReference
        this.workspaceRoot = workspaceRoot; this.protectedArtifacts = protectedArtifacts
    }
}

public class TeacherFailureKnowledgeAsset {
    public let reference: TeacherFrozenKnowledgeReference
    public let files: Array<TeacherArtifactFile>
    public let visibleContent: String
    public let auditContent: String
    public init(reference: TeacherFrozenKnowledgeReference, files: Array<TeacherArtifactFile>,
        visibleContent: String, auditContent: String) {
        this.reference = reference; this.files = files; this.visibleContent = visibleContent
        this.auditContent = auditContent
    }
}

public interface TeacherFailureKnowledgeAdapter {
    func build(classification: TeacherFailureAssetClassification,
        request: TeacherFailureKnowledgeRequest): TeacherFailureKnowledgeAsset
}

public interface TeacherIndependentKnowledgeAdapter {
    func buildIndependent(request: TeacherFailureKnowledgeRequest): TeacherFailureKnowledgeAsset
}

private func teacherKnowledgeString(object: JsonObject, name: String): String {
    match (object.get(name)) { case Some(value) => value.asString().getValue(); case None => "" }
}

private func teacherKnowledgeHash(value: String): Bool {
    if (!value.startsWith("sha256:") || value.toRuneArray().size != 71) { return false }
    for (rune in value.toRuneArray()[7..]) {
        if (!((rune >= r'0' && rune <= r'9') || (rune >= r'a' && rune <= r'f'))) { return false }
    }
    true
}

public func parseTeacherFrozenKnowledgeReference(raw: String): TeacherFrozenKnowledgeReference {
    try {
        let object = JsonValue.fromStr(raw).asObject()
        if (object.getFields().size != 6 ||
            teacherKnowledgeString(object, "schemaVersion") != "ckb-frozen-knowledge-reference-v1") {
            throw IllegalArgumentException("frozen_knowledge_reference_invalid")
        }
        let candidateHash = teacherKnowledgeString(object, "knowledgeCandidateHash")
        let version = teacherKnowledgeString(object, "knowledgeVersion")
        let manifestHash = teacherKnowledgeString(object, "frozenCandidateManifestHash")
        let contentHash = teacherKnowledgeString(object, "knowledgeContentHash")
        let lineage = teacherKnowledgeString(object, "assetLineage")
        let canonical = "{\"schemaVersion\":\"ckb-frozen-knowledge-reference-v1\"," +
            "\"knowledgeCandidateHash\":\"${candidateHash}\",\"knowledgeVersion\":\"${version}\"," +
            "\"frozenCandidateManifestHash\":\"${manifestHash}\",\"knowledgeContentHash\":\"${contentHash}\"," +
            "\"assetLineage\":\"${lineage}\"}"
        if (!teacherKnowledgeHash(candidateHash) || version.isEmpty() || !teacherKnowledgeHash(manifestHash) ||
            !teacherKnowledgeHash(contentHash) || !["independent", "humaneval_164_derived"].contains(lineage) ||
            raw != canonical) { throw IllegalArgumentException("frozen_knowledge_reference_invalid") }
        TeacherFrozenKnowledgeReference(candidateHash, version, manifestHash, contentHash, lineage, canonical)
    } catch (e: IllegalArgumentException) { throw e }
    catch (_: Exception) { throw IllegalArgumentException("frozen_knowledge_reference_invalid") }
}

private func teacherKnowledgeAtomSources(object: JsonObject): (String, String, String, String, String, String) {
    let tests = object.get("tests").getOrThrow().asArray().getItems()
    var positive = ""; var negative = ""; var boundary = ""
    var positiveProfile = ""; var negativeProfile = ""; var boundaryProfile = ""
    for (value in tests) {
        let test = value.asObject(); let category = teacherKnowledgeString(test, "category")
        if (category == "positive") { positive = teacherKnowledgeString(test, "source"); positiveProfile = teacherKnowledgeString(test, "dependencyProfile") }
        else if (category == "negative") { negative = teacherKnowledgeString(test, "source"); negativeProfile = teacherKnowledgeString(test, "dependencyProfile") }
        else if (category == "boundary") { boundary = teacherKnowledgeString(test, "source"); boundaryProfile = teacherKnowledgeString(test, "dependencyProfile") }
    }
    (positive, negative, boundary, positiveProfile, negativeProfile, boundaryProfile)
}

public class ScaffoldTeacherFailureKnowledgeAdapter <: TeacherFailureKnowledgeAdapter & TeacherIndependentKnowledgeAdapter {
    let executor: TeacherCommandExecutor
    let timeoutMillis: Int64
    public init(executor: TeacherCommandExecutor, timeoutMillis!: Int64 = 600000) {
        this.executor = executor; this.timeoutMillis = timeoutMillis
    }
    public func build(classification: TeacherFailureAssetClassification,
        request: TeacherFailureKnowledgeRequest): TeacherFailureKnowledgeAsset {
        if (!classification.knowledgeEligible || classification.schemaVersion !=
            "ckb-completion-failure-classification-v2" || request.atomBundle.contains("ckb-benchmark-gap-v1")) {
            throw IllegalArgumentException("failure_knowledge_adapter_invalid")
        }
        buildValidated(request, "humaneval_164_derived")
    }
    public func buildIndependent(request: TeacherFailureKnowledgeRequest): TeacherFailureKnowledgeAsset {
        if (request.atomBundle.contains("ckb-benchmark-gap-v1")) {
            throw IllegalArgumentException("failure_knowledge_adapter_invalid")
        }
        buildValidated(request, "independent")
    }
    private func buildValidated(request: TeacherFailureKnowledgeRequest,
        expectedLineage: String): TeacherFailureKnowledgeAsset {
        try {
            let object = JsonValue.fromStr(request.atomBundle).asObject()
            let reference = parseTeacherFrozenKnowledgeReference(request.frozenReference)
            let atomHash = teacherKnowledgeString(object, "candidateHash")
            let sourceClass = teacherKnowledgeString(object, "sourceClass")
            let citation = teacherKnowledgeString(object, "citation")
            if (atomHash != reference.knowledgeCandidateHash ||
                !["official", "teacher_empirical"].contains(sourceClass) ||
                (sourceClass == "official" && !citation.startsWith("https://docs.cangjie-lang.cn/")) ||
                (sourceClass == "teacher_empirical" && !citation.isEmpty()) ||
                teacherKnowledgeString(object, "targetVersion") != reference.knowledgeVersion ||
                reference.assetLineage != expectedLineage) {
                throw IllegalArgumentException("failure_knowledge_adapter_invalid")
            }
            let sources = teacherKnowledgeAtomSources(object)
            let relevance = validateTeacherAuthorityRelevance(request.authorityEvidence,
                request.missingKnowledge, teacherKnowledgeString(object, "knowledgeText"),
                teacherKnowledgeString(object, "example"), sources[0], sources[1], sources[2],
                positiveDependencyProfile: sources[3], negativeDependencyProfile: sources[4],
                boundaryDependencyProfile: sources[5])
            if (!relevance.ok) { throw IllegalArgumentException("failure_knowledge_adapter_invalid") }
            let execution = executeTeacherKnowledgeAtomCandidate(request.atomBundle, request.workspaceRoot,
                executor: executor, timeoutMillis: timeoutMillis)
            if (!execution.ok) { throw IllegalArgumentException(execution.diagnostic) }
            let visible = teacherKnowledgeString(object, "knowledgeText") + "\n" +
                teacherKnowledgeString(object, "example")
            let audit = auditTextAgainstProtectedArtifacts(visible, request.protectedArtifacts)
            if (!audit.passed) { throw IllegalArgumentException("protected_asset_combination") }
            // The cross-repository knowledge lane is a frozen reference only. Authority,
            // atom and execution evidence stay in the Teacher-owned source closure.
            TeacherFailureKnowledgeAsset(reference, [
                TeacherArtifactFile("knowledge-candidate-reference.json", reference.raw + "\n")
            ], reference.raw + "\n", visible)
        } catch (e: IllegalArgumentException) { throw e }
        catch (_: Exception) { throw IllegalArgumentException("failure_knowledge_adapter_invalid") }
    }
}

public class UnavailableTeacherFailureKnowledgeAdapter <: TeacherFailureKnowledgeAdapter {
    public func build(classification: TeacherFailureAssetClassification,
        request: TeacherFailureKnowledgeRequest): TeacherFailureKnowledgeAsset {
        throw IllegalArgumentException("classification_requires_review")
    }
}

// Production S6 consumes only a separately precertified and frozen CKB reference.
// Atom generation/execution remains a prior workflow and cannot be substituted here.
public class FrozenTeacherFailureKnowledgeAdapter <: TeacherFailureKnowledgeAdapter &
    TeacherIndependentKnowledgeAdapter {
    public func build(classification: TeacherFailureAssetClassification,
        request: TeacherFailureKnowledgeRequest): TeacherFailureKnowledgeAsset {
        if (!classification.knowledgeEligible || classification.schemaVersion !=
            "ckb-completion-failure-classification-v2") {
            throw IllegalArgumentException("failure_knowledge_adapter_invalid")
        }
        buildFrozen(request, "humaneval_164_derived")
    }
    public func buildIndependent(request: TeacherFailureKnowledgeRequest): TeacherFailureKnowledgeAsset {
        buildFrozen(request, "independent")
    }
    private func buildFrozen(request: TeacherFailureKnowledgeRequest,
        expectedLineage: String): TeacherFailureKnowledgeAsset {
        if (!request.atomBundle.isEmpty() || !request.workspaceRoot.isEmpty() ||
            !request.authorityEvidence.isEmpty()) {
            throw IllegalArgumentException("failure_knowledge_adapter_invalid")
        }
        let reference = parseTeacherFrozenKnowledgeReference(request.frozenReference)
        if (reference.assetLineage != expectedLineage) {
            throw IllegalArgumentException("failure_knowledge_adapter_invalid")
        }
        let visible = reference.raw + "\n"
        let audit = auditTextAgainstProtectedArtifacts(visible, request.protectedArtifacts)
        if (!audit.passed) { throw IllegalArgumentException("protected_asset_combination") }
        TeacherFailureKnowledgeAsset(reference, [
            TeacherArtifactFile("knowledge-candidate-reference.json", visible)
        ], visible, visible)
    }
}
