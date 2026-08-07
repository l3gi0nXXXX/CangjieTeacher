package cangjie_teacher

import std.collection.*

public class TeacherContextBaseStateV2 {
    // Preserve the caller path that passed the strict lexical gate separately from
    // the canonical path used for reads (notably /tmp versus /private/tmp on macOS).
    public let baseInputRoot: String
    public let baseRoot: String
    public let compositeHash: String
    public let rulesHash: String; public let rulesCount: Int64; public let rulesLineage: String
    public let rulesVisible: String; public let rulesAssets: Array<TeacherContextBaseAssetIdentity>
    public let skillsHash: String; public let skillsCount: Int64; public let skillsLineage: String
    public let skillsVisible: String; public let skillsAssets: Array<TeacherContextBaseAssetIdentity>
    public let knowledgeHash: String; public let knowledgeVersion: String
    public let knowledgeLineage: String; public let knowledgeVisible: String
    public let closureBindings: Array<String>; public let protectedArtifacts: Array<String>
    init(compositeHash: String, rulesHash: String, rulesCount: Int64, rulesLineage: String,
        rulesVisible: String, rulesAssets: Array<TeacherContextBaseAssetIdentity>,
        skillsHash: String, skillsCount: Int64, skillsLineage: String, skillsVisible: String,
        skillsAssets: Array<TeacherContextBaseAssetIdentity>, knowledgeHash: String,
        knowledgeVersion: String, knowledgeLineage: String, knowledgeVisible: String,
        closureBindings!: Array<String> = [], protectedArtifacts!: Array<String> = [],
        baseInputRoot!: String = "", baseRoot!: String = "") {
        this.baseInputRoot = baseInputRoot
        this.baseRoot = baseRoot
        this.compositeHash = compositeHash; this.rulesHash = rulesHash; this.rulesCount = rulesCount
        this.rulesLineage = rulesLineage; this.rulesVisible = rulesVisible; this.rulesAssets = rulesAssets
        this.skillsHash = skillsHash; this.skillsCount = skillsCount; this.skillsLineage = skillsLineage
        this.skillsVisible = skillsVisible; this.skillsAssets = skillsAssets
        this.knowledgeHash = knowledgeHash; this.knowledgeVersion = knowledgeVersion
        this.knowledgeLineage = knowledgeLineage; this.knowledgeVisible = knowledgeVisible
        this.closureBindings = closureBindings; this.protectedArtifacts = protectedArtifacts
    }
}

public class TeacherFailureAssetBuildRequestV2 {
    public let failure: TeacherCompletionFailureInput
    public let firstClassification: TeacherFailureAssetClassification
    public let secondClassification: TeacherFailureAssetClassification
    public let gapDescription: String
    public let generator: TeacherFailureAssetGenerator
    public let ruleFixtures: Array<TeacherAssetFixture>
    public let skillFixtures: Array<TeacherAssetFixture>
    public let fixtureExecutor: TeacherAssetFixtureExecutor
    public let knowledgeRequest: TeacherFailureKnowledgeRequest
    public let knowledgeAdapter: TeacherFailureKnowledgeAdapter
    public let sourceClosure: TeacherContextSourceClosure
    public let base: TeacherContextBaseStateV2
    public let candidateSetId: String
    public let ruleId: String; public let ruleConceptId: String
    public let skillId: String
    public let ruleOperation: String; public let ruleExpectedOldHash: String
    public let skillOperation: String; public let skillExpectedOldHash: String
    public let allowedRoot: String; public let outputRoot: String
    public init(failure: TeacherCompletionFailureInput,
        firstClassification: TeacherFailureAssetClassification,
        secondClassification: TeacherFailureAssetClassification, gapDescription: String,
        generator: TeacherFailureAssetGenerator, ruleFixtures: Array<TeacherAssetFixture>,
        skillFixtures: Array<TeacherAssetFixture>, fixtureExecutor: TeacherAssetFixtureExecutor,
        knowledgeRequest: TeacherFailureKnowledgeRequest,
        knowledgeAdapter: TeacherFailureKnowledgeAdapter, sourceClosure: TeacherContextSourceClosure,
        base: TeacherContextBaseStateV2, candidateSetId: String, ruleId: String,
        ruleConceptId: String, skillId: String, ruleOperation: String,
        ruleExpectedOldHash: String, skillOperation: String, skillExpectedOldHash: String,
        allowedRoot: String, outputRoot: String) {
        this.failure = failure; this.firstClassification = firstClassification
        this.secondClassification = secondClassification; this.gapDescription = gapDescription
        this.generator = generator; this.ruleFixtures = ruleFixtures; this.skillFixtures = skillFixtures
        this.fixtureExecutor = fixtureExecutor; this.knowledgeRequest = knowledgeRequest
        this.knowledgeAdapter = knowledgeAdapter; this.sourceClosure = sourceClosure; this.base = base
        this.candidateSetId = candidateSetId; this.ruleId = ruleId; this.ruleConceptId = ruleConceptId
        this.skillId = skillId; this.ruleOperation = ruleOperation
        this.ruleExpectedOldHash = ruleExpectedOldHash; this.skillOperation = skillOperation
        this.skillExpectedOldHash = skillExpectedOldHash; this.allowedRoot = allowedRoot
        this.outputRoot = outputRoot
    }
}

public class TeacherIndependentSeedRequestV2 {
    public let sourceClosure: TeacherContextSourceClosure
    public let ruleProposal: TeacherFailureAssetGenerationResponse
    public let skillProposal: TeacherFailureAssetGenerationResponse
    public let ruleFixtures: Array<TeacherAssetFixture>
    public let skillFixtures: Array<TeacherAssetFixture>
    public let fixtureExecutor: TeacherAssetFixtureExecutor
    public let knowledgeRequest: TeacherFailureKnowledgeRequest
    public let knowledgeAdapter: TeacherIndependentKnowledgeAdapter
    public let candidateSetId: String; public let ruleId: String; public let ruleConceptId: String
    public let skillId: String; public let allowedRoot: String; public let outputRoot: String
    public init(sourceClosure: TeacherContextSourceClosure,
        ruleProposal: TeacherFailureAssetGenerationResponse,
        skillProposal: TeacherFailureAssetGenerationResponse,
        ruleFixtures: Array<TeacherAssetFixture>, skillFixtures: Array<TeacherAssetFixture>,
        fixtureExecutor: TeacherAssetFixtureExecutor, knowledgeRequest: TeacherFailureKnowledgeRequest,
        knowledgeAdapter: TeacherIndependentKnowledgeAdapter, candidateSetId: String,
        ruleId: String, ruleConceptId: String, skillId: String,
        allowedRoot: String, outputRoot: String) {
        this.sourceClosure = sourceClosure; this.ruleProposal = ruleProposal
        this.skillProposal = skillProposal; this.ruleFixtures = ruleFixtures
        this.skillFixtures = skillFixtures; this.fixtureExecutor = fixtureExecutor
        this.knowledgeRequest = knowledgeRequest; this.knowledgeAdapter = knowledgeAdapter
        this.candidateSetId = candidateSetId; this.ruleId = ruleId
        this.ruleConceptId = ruleConceptId; this.skillId = skillId
        this.allowedRoot = allowedRoot; this.outputRoot = outputRoot
    }
}

private func teacherPipelineEmptyTreeHash(): String {
    teacherContextLaneTreeHashV2([])
}

private func teacherPipelineInheritedLane(hash: String, count: Int64, lineage: String,
    visible: String): TeacherContextLaneV2 {
    TeacherContextLaneV2(false, hash, teacherPipelineEmptyTreeHash(), count, lineage, visible, [])
}

private func teacherPipelineAllPassed(values: Array<TeacherAssetFixtureExecution>): Bool {
    if (values.isEmpty()) { return false }
    for (value in values) {
        if (!value.passed || value.fixtureHash != teacherAssetFixtureHash(value.fixture) ||
            value.actualEvidence != value.fixture.expectedEvidence ||
            value.transcriptHash != "sha256:${teacherStableHash(value.transcript)}") { return false }
    }
    true
}

private func teacherPipelineProposal(proposals: Array<TeacherFailureAssetGenerationResponse>,
    lane: String): TeacherFailureAssetGenerationResponse {
    for (proposal in proposals) { if (proposal.lane == lane) { return proposal } }
    throw IllegalArgumentException("candidate_generation_invalid")
}

private func teacherPipelineClassificationHash(first: TeacherFailureAssetClassification,
    second: TeacherFailureAssetClassification): String {
    let a = renderTeacherFailureAssetClassifierResponse(first)
    let b = renderTeacherFailureAssetClassifierResponse(second)
    let inventory = "${teacherStableHash(a)}  classification-a.json\n" +
        "${teacherStableHash(b)}  classification-b.json\n"
    "sha256:${teacherStableHash(inventory)}"
}

public func buildTeacherFailureAssets(request: TeacherFailureAssetBuildRequestV2): TeacherFailureAssetsBuildResult {
    if (request.base.compositeHash == "none" || !teacherArtifactSafeComponent(request.candidateSetId) ||
        request.base.baseInputRoot.isEmpty() || request.base.baseRoot.isEmpty() ||
        renderTeacherCompletionFailureInput(request.failure).isEmpty()) {
        throw IllegalArgumentException("candidate_base_composite_mismatch")
    }
    let sourceClosure = bindTeacherContextSourceClosureToBase(request.sourceClosure,
        request.base.closureBindings)
    let classification = reconcileTeacherFailureAssetClassifications(request.firstClassification,
        request.secondClassification)
    if (classification.failureEvidenceHash != request.failure.evidenceHash ||
        sourceClosure.manifest.sourceKind != "completion_failures") {
        throw IllegalArgumentException("failure_classification_binding_mismatch")
    }
    let proposals = generateTeacherFailureAssetProposals(classification, request.gapDescription,
        request.generator)
    if (classifyTeacherAssetOutputKind(classification) == "none") {
        return TeacherFailureAssetsBuildResult(classification, proposals)
    }
    let validation = if (request.fixtureExecutor.executorKind() == "fake_contract") {
        "scaffold_contract"
    } else if (request.fixtureExecutor.executorKind() == "student_completion_non_humaneval") {
        "student_validated"
    } else { throw IllegalArgumentException("candidate_test_evidence_invalid") }

    var rules = teacherPipelineInheritedLane(request.base.rulesHash, request.base.rulesCount,
        request.base.rulesLineage, request.base.rulesVisible)
    var skills = teacherPipelineInheritedLane(request.base.skillsHash, request.base.skillsCount,
        request.base.skillsLineage, request.base.skillsVisible)
    var knowledge = teacherPipelineInheritedLane(request.base.knowledgeHash, 1,
        request.base.knowledgeLineage, request.base.knowledgeVisible)
    // Rules and skills are reconstructable from actual base rows plus the candidate operation,
    // so audit their final student-visible projections. An inherited frozen knowledge reference
    // is only a content-hash binding here; active knowledge supplies its new actual audit material.
    var rulesAudit = request.base.rulesVisible
    var skillsAudit = request.base.skillsVisible
    var knowledgeAudit = ""

    if (classification.rulesEligible) {
        let executions = executeTeacherAssetFixtureBundle(request.ruleFixtures, request.fixtureExecutor)
        if (!teacherPipelineAllPassed(executions)) {
            throw IllegalArgumentException("candidate_test_evidence_invalid")
        }
        let proposal = teacherPipelineProposal(proposals, "rules")
        let candidate = buildTeacherRuleCandidate(classification, request.ruleId, request.ruleConceptId,
            proposal.title, proposal.content, proposal.trigger, proposal.scope, proposal.priority,
            "completion_failure", request.failure.evidenceHash, TeacherRuleTestBundle(executions))
        let operation = buildTeacherContextAssetOperation("rules", candidate.ruleId,
            request.ruleOperation, request.ruleExpectedOldHash, candidate.canonicalHash,
            request.base.rulesAssets)
        let files = teacherRuleCandidateArtifactFiles(candidate, operation)
        let single = renderTeacherAgentsMarkdown([candidate])
        let fragment = String(single.toRuneArray()["# Student Rules\n".toRuneArray().size..])
        let visible = teacherContextAssetProjection("rules", applyTeacherContextAssetOperation(
            request.base.rulesAssets, operation, fragment, priority: candidate.priority))
        rules = TeacherContextLaneV2(true, "sha256:${teacherStableHash(visible)}",
            teacherContextLaneTreeHashV2(files), request.base.rulesAssets.size +
                if (request.ruleOperation == "add") { 1 } else { 0 },
            "humaneval_164_derived", visible, files)
        rulesAudit = visible
    }
    if (classification.skillEligible) {
        let executions = executeTeacherAssetFixtureBundle(request.skillFixtures, request.fixtureExecutor)
        if (!teacherPipelineAllPassed(executions)) {
            throw IllegalArgumentException("candidate_test_evidence_invalid")
        }
        let candidate = buildTeacherSkillCandidateFromFailureAsset(request.failure, classification,
            teacherPipelineProposal(proposals, "skill"), executions, request.skillId)
        let operation = buildTeacherContextAssetOperation("skills", candidate.skillId,
            request.skillOperation, request.skillExpectedOldHash, candidate.contentHash,
            request.base.skillsAssets)
        let files = teacherSkillCandidateArtifactFiles(candidate, operation, executions: executions)
        let visible = teacherContextAssetProjection("skills", applyTeacherContextAssetOperation(
            request.base.skillsAssets, operation, renderCandidateSkillExport(candidate)))
        skills = TeacherContextLaneV2(true, "sha256:${teacherStableHash(visible)}",
            teacherContextLaneTreeHashV2(files), request.base.skillsAssets.size +
                if (request.skillOperation == "add") { 1 } else { 0 },
            "humaneval_164_derived", visible, files)
        skillsAudit = visible
    }
    if (classification.knowledgeEligible) {
        let proposal = teacherPipelineProposal(proposals, "knowledge")
        if (proposal.content != request.knowledgeRequest.missingKnowledge) {
            throw IllegalArgumentException("failure_knowledge_adapter_invalid")
        }
        let asset = request.knowledgeAdapter.build(classification, request.knowledgeRequest)
        knowledge = TeacherContextLaneV2(true, asset.reference.knowledgeCandidateHash,
            teacherContextLaneTreeHashV2(asset.files), 1, "humaneval_164_derived",
            asset.visibleContent, asset.files)
        knowledgeAudit = asset.auditContent
    }

    let visible = [if (rules.eligible) { rules.visibleContent } else { request.base.rulesVisible },
        if (skills.eligible) { skills.visibleContent } else { request.base.skillsVisible },
        if (knowledge.eligible) { knowledge.visibleContent } else { request.base.knowledgeVisible }]
    if ((rules.eligible && skills.eligible && visible[0] == visible[1]) ||
        (rules.eligible && knowledge.eligible && visible[0] == visible[2]) ||
        (skills.eligible && knowledge.eligible && visible[1] == visible[2])) {
        throw IllegalArgumentException("candidate_generation_invalid")
    }
    let auditProtected = ArrayList<String>()
    for (value in sourceClosure.protectedArtifacts) { auditProtected.add(value) }
    for (value in request.base.protectedArtifacts) { auditProtected.add(value) }
    let audit = auditTeacherAssetCombinationLeakage(rulesAudit, skillsAudit, knowledgeAudit,
        auditProtected.toArray())
    if (!audit.passed) { throw IllegalArgumentException("protected_asset_combination") }

    let candidate = sealTeacherContextCandidateSetV2(request.candidateSetId,
        request.base.compositeHash, validation,
        teacherPipelineClassificationHash(request.firstClassification, request.secondClassification),
        sourceClosure, rules, skills, knowledge, if (knowledge.eligible) {
            parseTeacherFrozenKnowledgeReference(request.knowledgeRequest.frozenReference).knowledgeVersion
        } else { request.base.knowledgeVersion })
    _ = exportTeacherContextCandidateSetV2(candidate, request.allowedRoot, request.outputRoot,
        baseContextRoot: request.base.baseInputRoot)
    TeacherFailureAssetsBuildResult(classification, proposals, candidateSetV2: Some(candidate))
}

public func buildTeacherIndependentContextSeed(request: TeacherIndependentSeedRequestV2): TeacherContextCandidateSetV2 {
    if (request.sourceClosure.manifest.sourceKind != "independent_sources" ||
        !teacherArtifactSafeComponent(request.candidateSetId) ||
        request.ruleProposal.lane != "rules" || request.skillProposal.lane != "skill" ||
        request.ruleProposal.content == request.skillProposal.content) {
        throw IllegalArgumentException("candidate_lane_lineage_invalid")
    }
    let validation = if (request.fixtureExecutor.executorKind() == "fake_contract") {
        "scaffold_contract"
    } else if (request.fixtureExecutor.executorKind() == "student_completion_non_humaneval") {
        "student_validated"
    } else { throw IllegalArgumentException("candidate_test_evidence_invalid") }
    let ruleExecutions = executeTeacherAssetFixtureBundle(request.ruleFixtures, request.fixtureExecutor)
    let skillExecutions = executeTeacherAssetFixtureBundle(request.skillFixtures, request.fixtureExecutor)
    if (!teacherPipelineAllPassed(ruleExecutions) || !teacherPipelineAllPassed(skillExecutions)) {
        throw IllegalArgumentException("candidate_test_evidence_invalid")
    }
    let rule = buildTeacherIndependentRuleCandidate(request.ruleId, request.ruleConceptId,
        request.ruleProposal.title, request.ruleProposal.content, request.ruleProposal.trigger,
        request.ruleProposal.scope, request.ruleProposal.priority,
        request.sourceClosure.manifest.sourceManifestHash, TeacherRuleTestBundle(ruleExecutions))
    let ruleOperation = buildTeacherContextAssetOperation("rules", rule.ruleId, "add", "",
        rule.canonicalHash, [])
    let ruleFiles = teacherRuleCandidateArtifactFiles(rule, ruleOperation)
    let ruleVisible = renderTeacherAgentsMarkdown([rule])
    let rules = TeacherContextLaneV2(true, "sha256:${teacherStableHash(ruleVisible)}",
        teacherContextLaneTreeHashV2(ruleFiles), 1, "independent",
        ruleVisible, ruleFiles)

    let skill = buildTeacherIndependentSkillCandidate(request.skillId, request.skillProposal,
        skillExecutions)
    let skillOperation = buildTeacherContextAssetOperation("skills", skill.skillId, "add", "",
        skill.contentHash, [])
    let skillFiles = teacherSkillCandidateArtifactFiles(skill, skillOperation,
        executions: skillExecutions)
    let skillVisible = renderCandidateSkillExport(skill)
    let skills = TeacherContextLaneV2(true, "sha256:${teacherStableHash(skillVisible)}",
        teacherContextLaneTreeHashV2(skillFiles), 1, "independent",
        skillVisible, skillFiles)

    let knowledgeAsset = request.knowledgeAdapter.buildIndependent(request.knowledgeRequest)
    let knowledge = TeacherContextLaneV2(true, knowledgeAsset.reference.knowledgeCandidateHash,
        teacherContextLaneTreeHashV2(knowledgeAsset.files), 1, "independent",
        knowledgeAsset.visibleContent, knowledgeAsset.files)
    if (rules.visibleContent == skills.visibleContent || rules.visibleContent == knowledge.visibleContent ||
        skills.visibleContent == knowledge.visibleContent) {
        throw IllegalArgumentException("candidate_generation_invalid")
    }
    let audit = auditTeacherAssetCombinationLeakage(request.ruleProposal.content,
        request.skillProposal.content, knowledgeAsset.auditContent,
        request.sourceClosure.protectedArtifacts)
    if (!audit.passed) { throw IllegalArgumentException("protected_asset_combination") }
    let candidate = sealTeacherContextCandidateSetV2(request.candidateSetId, "none", validation,
        "", request.sourceClosure, rules, skills, knowledge,
        knowledgeAsset.reference.knowledgeVersion)
    _ = exportTeacherContextCandidateSetV2(candidate, request.allowedRoot, request.outputRoot)
    candidate
}
