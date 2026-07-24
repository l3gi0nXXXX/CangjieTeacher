package cangjie_teacher

import std.collection.*
import std.fs.*
import std.convert.Parsable
import stdx.encoding.json.*
import std.time.*

public class TeacherCandidateBuildResult {
    public var ok = false
    public var diagnostic = "candidate_build_failed"
    public var accepted: Int64 = 0
    public var ckbJsonl = ""
    public init() {}
}

private class TeacherGapRow {
    var datasetVersion = ""; var teacherRunId = ""; var evidenceHash = ""; var evidence = ""
    var caseId = ""; var benchmark = ""; var taskText = ""; var visibleTestExcerpt = ""; var compilerOutput = ""
    var missingKnowledge = ""; var interfaceId = ""; var contentFamily = ""; var updateMechanism = ""
    var targetVersion = ""; var citation = ""; var sourceClass = "official"; var failureTaxonomy = ""; var confirmations: Int64 = 0
    init() {}
}

private class TeacherAtomSpec {
    let family: String; let concept: String; let explanation: String; let example: String
    let citation: String; let sourceClass: String
    let positiveSource: String; let negativeSource: String; let boundarySource: String; let negativeDiagnostic: String
    let positiveDependencyProfile: String; let negativeDependencyProfile: String; let boundaryDependencyProfile: String
    let transcriptHash: String; let provider: String; let model: String
    init(family: String, concept: String, explanation: String, example: String, citation: String, sourceClass: String,
        positiveSource: String, negativeSource: String, boundarySource: String, negativeDiagnostic: String,
        positiveDependencyProfile: String, negativeDependencyProfile: String, boundaryDependencyProfile: String,
        transcriptHash: String, provider: String, model: String) {
        this.family = family; this.concept = concept; this.explanation = explanation; this.example = example
        this.citation=citation;this.sourceClass=sourceClass;this.positiveSource=positiveSource;this.negativeSource=negativeSource
        this.boundarySource=boundarySource;this.negativeDiagnostic=negativeDiagnostic;this.transcriptHash=transcriptHash
        this.positiveDependencyProfile=positiveDependencyProfile;this.negativeDependencyProfile=negativeDependencyProfile
        this.boundaryDependencyProfile=boundaryDependencyProfile
        this.provider=provider;this.model=model
    }
}

public class TeacherAtomExecutionResult {
    public var ok=false;public var diagnostic="atom_test_failed";public var evidenceJson="";public var feedback="";public init(){}
}

public class TeacherAuthorityRelevanceResult {
    public var ok=false;public var diagnostic="authority_relevance_failed";public var feedback=""
    public let anchors=ArrayList<String>()
    public init(){}
}

public func teacherRunCompleteForCandidate(run: TeacherRunManifest, expectedRunId: String): Bool {
    run.runId == expectedRunId && run.status == "complete" && run.attempt >= 1 && run.exitCode == 0
}

public func runTeacherCandidateBuild(options: TeacherCliOptions): Int64 {
    let result = buildTeacherCandidates(options)
    if (!result.ok) { println("candidate build blocked diagnostic=${result.diagnostic}"); return 1 }
    println("candidate build complete accepted=${result.accepted}")
    0
}

public func buildTeacherCandidates(options: TeacherCliOptions,
    extractorExecutor!:TeacherCommandExecutor=NativeTeacherCommandExecutor(),
    atomExecutor!:TeacherCommandExecutor=NativeTeacherCommandExecutor()): TeacherCandidateBuildResult {
    let result = TeacherCandidateBuildResult()
    var failureStage = "candidate_input_validation_failed"
    try {
        if (options.root == "" || options.manifest == "" || options.checksum == "" || options.authorityGap == "" || options.runId == "" || options.outputRoot == "") {
            result.diagnostic = "missing_required_cli_option"; return result
        }
        if (!candidateSafeId(options.runId)) { result.diagnostic = "run_id_invalid"; return result }
        if (!validateTeacherPathBoundary(options.root, options.outputRoot) || options.outputRoot.contains("..")) {
            result.diagnostic = "output_path_forbidden"; return result
        }
        failureStage = "candidate_manifest_load_failed"
        let manifest = loadTeacherDatasetManifestFile(options.manifest, options.checksum)
        let cases = HashMap<String, TeacherCaseManifest>()
        for (item in manifest.cases) { cases.add(item.caseId, item) }
        failureStage = "candidate_completed_run_load_failed"
        let completed = loadCompletedTeacherRuns("${options.root}/runs/${options.runId}/completed.manifest")
        let runs = HashMap<String, TeacherRunManifest>()
        for (run in completed) {
            if (runs.contains(run.caseId)) { result.diagnostic = "duplicate_complete_run"; return result }
            if (teacherRunCompleteForCandidate(run, options.runId)) { runs.add(run.caseId, run) }
        }
        failureStage = "candidate_authority_gap_load_failed"
        let parsed = parseTeacherAuthorityGapJsonl(teacherReadUtf8File(options.authorityGap))
        if (parsed[1] != "ok") { result.diagnostic = parsed[1]; return result }
        let rows = parsed[0]
        if (rows.isEmpty()) { result.diagnostic = "authority_gap_empty"; return result }
        let identities = HashMap<String, TeacherObservation>()
        var observations = ""; var atoms = ""; var tests = ""; var candidates = ""; var ckb = ""
        for (row in rows) {
            let caseValue = match (cases.get(row.caseId)) { case Some(v) => v; case None => result.diagnostic = "gap_case_not_in_manifest"; return result }
            let run = match (runs.get(row.caseId)) { case Some(v) => v; case None => result.diagnostic = "complete_teacher_run_required"; return result }
            if (row.datasetVersion != caseValue.datasetVersion || run.datasetVersion != row.datasetVersion) { result.diagnostic = "dataset_version_mismatch"; return result }
            if(run.promptHash!=caseValue.promptHash||run.modelId!="gpt-5.6-sol"||run.evidenceHash==""){result.diagnostic="complete_run_identity_invalid";return result}
            let solutionRoot = TeacherPaths(options.root).solution(row.caseId)
            if (!exists(Path(solutionRoot))||!validateTeacherSolutionBinding(options.root,run)) { result.diagnostic = "solution_evidence_binding_invalid"; return result }
            let protected = teacherPrivateArtifacts(solutionRoot)
            var atomFeedback="";var acceptedSpec:?TeacherAtomSpec=None;var acceptedObservation:?TeacherObservation=None;var identity="";var bundle=""
            while(true){
                failureStage = "candidate_extractor_failed"
                let extraction=extractTeacherAtom(options,row,run,solutionRoot,atomFeedback,extractorExecutor)
                if(extraction[1]!="ok"){result.diagnostic=extraction[1];return result};let currentSpec=extraction[0]
                let relevance=validateTeacherAuthorityRelevance(row.compilerOutput,row.missingKnowledge,currentSpec.explanation,currentSpec.example,
                    currentSpec.positiveSource,currentSpec.negativeSource,currentSpec.boundarySource,
                    positiveDependencyProfile:currentSpec.positiveDependencyProfile,negativeDependencyProfile:currentSpec.negativeDependencyProfile,
                    boundaryDependencyProfile:currentSpec.boundaryDependencyProfile)
                if(!relevance.ok){atomFeedback=relevance.feedback;continue}
                let observation=deriveKnowledgeObservation(caseValue,currentSpec.family,currentSpec.concept,row.targetVersion,currentSpec.explanation,currentSpec.citation,currentSpec.sourceClass,row.evidence+currentSpec.transcriptHash)
                if(!validateObservationNoSolutionLeak(observation)){result.diagnostic="observation_leakage";return result}
                let normalized=normalizeObservation(observation);let currentIdentity=canonicalKnowledgeIdentity(normalized)
                match(identities.get(currentIdentity)){case Some(existing)=>if(mergeKnowledgeObservations([existing,normalized]).reviewRequired){result.diagnostic="review_required";return result};case None=>()}
                let currentBundle=teacherExecutableAtomBundle(currentIdentity,row,currentSpec,options.root,run)
                failureStage = "candidate_atom_execution_failed"
                let execution=executeTeacherAtomTestBundle(currentBundle,"${options.root}/runs/${options.runId}/atom-test-workspaces/${currentIdentity}",executor:atomExecutor,timeoutMillis:options.timeoutMillis)
                if(!execution.ok){if(execution.diagnostic=="atom_test_timeout"){result.diagnostic=execution.diagnostic;return result};atomFeedback=execution.feedback;continue}
                acceptedSpec=Some(currentSpec);acceptedObservation=Some(normalized);identity=currentIdentity;bundle=recordTeacherAtomTestExecution(currentBundle,execution.evidenceJson);break
            }
            let spec=match(acceptedSpec){case Some(v)=>v;case None=>throw IllegalStateException("accepted_atom_missing")}
            let normalized=match(acceptedObservation){case Some(v)=>v;case None=>throw IllegalStateException("accepted_observation_missing")}
            failureStage = "candidate_identity_record_failed"
            identities.add(identity,normalized)
            let simpleTests = buildKnowledgeAtomTestBundle(spec.positiveSource, spec.negativeSource, spec.boundarySource)
            failureStage = "candidate_render_failed"
            let candidate = renderCandidateKnowledgeExport(normalized, spec.example, simpleTests)
            failureStage = "candidate_leakage_audit_failed"
            if (!auditCandidateAgainstSolutions(candidate, protected).passed || !auditCaseSpecificity(candidate, [caseValue.signature]).passed) {
                result.diagnostic = "candidate_leakage"; return result
            }
            failureStage = "candidate_export_render_failed"
            let candidateText = renderTeacherCandidateExport(candidate)
            if (candidateForbidden(candidateText + bundle)) { result.diagnostic = "candidate_contamination"; return result }
            failureStage = "candidate_ckb_render_failed"
            let ckbLine = renderTeacherCkbGap(row, options.runId, bundle, spec.transcriptHash)
            if (observations != "") { observations += "\n"; atoms += "\n"; tests += "\n"; candidates += "\n"; ckb += "\n" }
            observations += renderTeacherObservation(normalized); atoms += "${identity}\t${teacherEscapeField(spec.explanation)}"
            tests += bundle; candidates += candidateText; ckb += ckbLine; result.accepted += 1
        }
        failureStage = "candidate_publish_prepare_failed"
        let base = options.outputRoot.trimEnd('/')
        if (exists(Path(base))) { result.diagnostic = "output_already_exists"; return result }
        // A shared private Teacher root legitimately contains exports from
        // other cases. Creating an already existing parent raises in the
        // Cangjie filesystem API, so only create the directory when absent.
        if (!exists(Path(base).parent)) { Directory.create(Path(base).parent, recursive: true) }
        let canonicalRoot=canonicalize(Path(options.root)).toString();let canonicalParent=canonicalize(Path(base).parent).toString()
        if (!canonicalParent.startsWith(canonicalRoot+"/")) { result.diagnostic="output_path_forbidden";return result }
        let stage=base+".tmp-"+teacherStableHash(ckb)
        failureStage = "candidate_atomic_publish_failed"
        try {
            _ = teacherAtomicWrite("${stage}/observations.tsv", observations + "\n")
            _ = teacherAtomicWrite("${stage}/atoms.tsv", atoms + "\n")
            _ = teacherAtomicWrite("${stage}/atom-tests.jsonl", tests + "\n")
            _ = teacherAtomicWrite("${stage}/candidate-knowledge.tsv", candidates + "\n")
            _ = teacherAtomicWrite("${stage}/candidate-knowledge/ckb-benchmark-gap.jsonl", ckb + "\n")
            rename(Path(stage),to:Path(base),overwrite:false)
        } catch (e:Exception) { try{remove(Path(stage),recursive:true)}catch(_:Exception){};throw e }
        result.ckbJsonl = ckb + "\n"; result.ok = true; result.diagnostic = "ok"
    } catch (e: IllegalArgumentException) {
        // Only pre-existing stable contract codes are safe to expose. Runtime
        // exception messages may contain private paths or candidate payloads.
        result.diagnostic = if (candidateStableDiagnostic(e.message)) { e.message } else { failureStage }
    } catch (_: Exception) { result.diagnostic = failureStage }
    result
}

public func runTeacherCandidateReexport(options:TeacherCliOptions):Int64{
    let result=reexportTeacherCandidateBundle(options)
    if(!result.ok){println("candidate reexport blocked diagnostic=${result.diagnostic}");return 1}
    println("candidate reexport complete accepted=${result.accepted}");0
}

public func reexportTeacherCandidateBundle(options:TeacherCliOptions,
    atomExecutor!:TeacherCommandExecutor=NativeTeacherCommandExecutor()):TeacherCandidateBuildResult{
    let result=TeacherCandidateBuildResult();var stage=""
    try{
        if(options.root==""||options.manifest==""||options.checksum==""||options.authorityGap==""||options.runId==""||options.sourceExport==""||options.outputRoot==""){
            result.diagnostic="missing_required_cli_option";return result
        }
        if(!candidateSafeId(options.runId)){result.diagnostic="run_id_invalid";return result}
        if(!validateTeacherPathBoundary(options.root,options.sourceExport)||options.sourceExport.contains("..")||options.sourceExport==options.outputRoot){result.diagnostic="source_export_path_forbidden";return result}
        if(!validateTeacherPathBoundary(options.root,options.outputRoot)||options.outputRoot.contains("..")){result.diagnostic="output_path_forbidden";return result}
        if(exists(Path(options.outputRoot))){result.diagnostic="output_already_exists";return result}
        let canonicalRoot=canonicalize(Path(options.root)).toString().trimEnd('/');let canonicalSource=try{canonicalize(Path(options.sourceExport)).toString()}catch(_:Exception){result.diagnostic="source_export_path_forbidden";return result}
        if(!canonicalSource.startsWith(canonicalRoot+"/")){result.diagnostic="source_export_path_forbidden";return result}
        let required=["observations.tsv","atoms.tsv","atom-tests.jsonl","candidate-knowledge.tsv","candidate-knowledge/ckb-benchmark-gap.jsonl"]
        for(relative in required){if(!exists(Path("${options.sourceExport}/${relative}"))){result.diagnostic="source_export_missing_file";return result}}
        let observationRaw=teacherReadBoundedCandidateFile("${options.sourceExport}/observations.tsv");if(observationRaw[1]!="ok"){result.diagnostic=observationRaw[1];return result}
        let atomsRaw=teacherReadBoundedCandidateFile("${options.sourceExport}/atoms.tsv");if(atomsRaw[1]!="ok"){result.diagnostic=atomsRaw[1];return result}
        let bundleRaw=teacherReadBoundedCandidateFile("${options.sourceExport}/atom-tests.jsonl");if(bundleRaw[1]!="ok"){result.diagnostic=bundleRaw[1];return result}
        let candidateRaw=teacherReadBoundedCandidateFile("${options.sourceExport}/candidate-knowledge.tsv");if(candidateRaw[1]!="ok"){result.diagnostic=candidateRaw[1];return result}
        let ckbRaw=teacherReadBoundedCandidateFile("${options.sourceExport}/candidate-knowledge/ckb-benchmark-gap.jsonl");if(ckbRaw[1]!="ok"){result.diagnostic=ckbRaw[1];return result}
        for(raw in [observationRaw[0],atomsRaw[0],bundleRaw[0],candidateRaw[0],ckbRaw[0]]){if(!teacherCandidateSingleRecord(raw)){result.diagnostic="source_export_record_count_invalid";return result}}
        let manifest=loadTeacherDatasetManifestFile(options.manifest,options.checksum);let parsedGap=parseTeacherAuthorityGapJsonl(teacherReadUtf8File(options.authorityGap))
        if(parsedGap[1]!="ok"){result.diagnostic=parsedGap[1];return result};if(parsedGap[0].size!=1){result.diagnostic="authority_gap_count_invalid";return result};let row=parsedGap[0][0]
        var matchedCase:?TeacherCaseManifest=None;for(item in manifest.cases){if(item.caseId==row.caseId){matchedCase=Some(item)}}
        let caseValue=match(matchedCase){case Some(v)=>v;case None=>result.diagnostic="gap_case_not_in_manifest";return result}
        var matchedRun:?TeacherRunManifest=None;for(run in loadCompletedTeacherRuns("${options.root}/runs/${options.runId}/completed.manifest")){if(run.caseId==row.caseId){if(matchedRun.isSome()){result.diagnostic="duplicate_complete_run";return result};matchedRun=Some(run)}}
        let run=match(matchedRun){case Some(v)=>v;case None=>result.diagnostic="complete_teacher_run_required";return result}
        if(!teacherRunCompleteForCandidate(run,options.runId)||run.datasetVersion!=row.datasetVersion||row.datasetVersion!=caseValue.datasetVersion||row.teacherRunId!=options.runId||run.promptHash!=caseValue.promptHash||run.modelId!="gpt-5.6-sol"||run.evidenceHash==""){
            result.diagnostic="reexport_binding_invalid";return result
        }
        if(!validateTeacherSolutionBinding(options.root,run)){result.diagnostic="solution_evidence_binding_invalid";return result}
        let observation=try{parseTeacherObservation(observationRaw[0].trimAscii())}catch(_:Exception){result.diagnostic="malformed_teacher_observation";return result}
        let candidate=try{parseTeacherCandidateExport(candidateRaw[0].trimAscii())}catch(_:Exception){result.diagnostic="malformed_teacher_candidate_export";return result}
        if(observation.caseId!=row.caseId||candidate.identity!=canonicalKnowledgeIdentity(observation)||candidate.knowledgeFamily!=observation.knowledgeFamily||candidate.concept!=observation.concept||candidate.targetVersion!=observation.targetVersion||candidate.explanation!=observation.explanation||candidate.citation!=observation.citation||candidate.sourceClass!=observation.sourceClass){result.diagnostic="source_export_identity_mismatch";return result}
        if(atomsRaw[0].trimAscii()!="${candidate.identity}\t${teacherEscapeField(candidate.explanation)}"){result.diagnostic="source_export_atoms_mismatch";return result}
        if(!validateObservationNoSolutionLeak(observation)||!auditCandidateAgainstSolutions(candidate,teacherPrivateArtifacts(TeacherPaths(options.root).solution(row.caseId))).passed||!auditCaseSpecificity(candidate,[caseValue.signature]).passed||teacherReexportForbidden(candidateRaw[0]+"\n"+bundleRaw[0])){result.diagnostic="candidate_leakage";return result}
        let sourceValidation=validateTeacherReexportBundle(bundleRaw[0].trimAscii(),candidate,row,options.root,run)
        if(sourceValidation[1]!="ok"){result.diagnostic=sourceValidation[1];return result};let transcriptHash=sourceValidation[0]
        let ckbValidation=validateTeacherReexportCkb(ckbRaw[0].trimAscii(),bundleRaw[0].trimAscii(),row,options.runId,transcriptHash)
        if(ckbValidation!="ok"){result.diagnostic=ckbValidation;return result}
        let replay=executeTeacherAtomTestBundle(bundleRaw[0].trimAscii(),"${options.root}/runs/${options.runId}/reexport-atom-workspaces/${candidate.identity}",executor:atomExecutor,timeoutMillis:options.timeoutMillis)
        if(!replay.ok){result.diagnostic=replay.diagnostic;return result}
        let newBundle=renderTeacherReexportBundle(bundleRaw[0].trimAscii(),replay.evidenceJson)
        let newCkb=renderTeacherCkbGap(row,options.runId,newBundle,transcriptHash)
        let base=options.outputRoot.trimEnd('/');let canonicalParent=canonicalize(Path(base).parent).toString()
        if(!canonicalParent.startsWith(canonicalRoot+"/")){result.diagnostic="output_path_forbidden";return result}
        if(!exists(Path(base).parent)){Directory.create(Path(base).parent,recursive:true)}
        stage=base+".tmp-"+teacherStableHash(newCkb)
        if(exists(Path(stage))){remove(Path(stage),recursive:true)}
        try{
            _=teacherAtomicWrite("${stage}/observations.tsv",observationRaw[0].trimAscii()+"\n")
            _=teacherAtomicWrite("${stage}/atoms.tsv",atomsRaw[0].trimAscii()+"\n")
            _=teacherAtomicWrite("${stage}/atom-tests.jsonl",newBundle+"\n")
            _=teacherAtomicWrite("${stage}/candidate-knowledge.tsv",candidateRaw[0].trimAscii()+"\n")
            _=teacherAtomicWrite("${stage}/candidate-knowledge/ckb-benchmark-gap.jsonl",newCkb+"\n")
            rename(Path(stage),to:Path(base),overwrite:false)
        }catch(e:Exception){try{remove(Path(stage),recursive:true)}catch(_:Exception){};throw e}
        result.ok=true;result.diagnostic="ok";result.accepted=1;result.ckbJsonl=newCkb+"\n"
    }catch(_:Exception){if(stage!=""){try{remove(Path(stage),recursive:true)}catch(_:Exception){}};result.diagnostic="candidate_reexport_failed"}
    result
}

private func teacherReadBoundedCandidateFile(path:String):(String,String){
    try{let bytes=File.readFrom(Path(path));if(bytes.size>262144){return("","source_export_too_large")};let text=try{String.fromUtf8(bytes)}catch(_:Exception){return("","invalid_response_encoding")};(text,"ok")}catch(_:Exception){("","source_export_read_failed")}
}

private func teacherCandidateSingleRecord(raw:String):Bool{var count:Int64=0;for(line in raw.split("\n")){if(line.trimAscii()!=""){count++}};count==1}

private func validateTeacherReexportBundle(raw:String,candidate:TeacherCandidateExport,row:TeacherGapRow,root:String,run:TeacherRunManifest):(String,String){
    try{
        let o=JsonValue.fromStr(raw).asObject();let canonical=canonicalizeTeacherCkbKnowledgeAtomBundle(raw.toArray());if(canonical[1]!="ok"){return("",canonical[1])}
        for(key in ["atomId","knowledgeFamily","sourceClass","citation","targetVersion","candidateHash","knowledgeText","example","extractor","purificationPassed","tests","execution"]){if(!candidateHas(o,key)){return("","atom_contract_missing_field")}}
        let extractor=o.get("extractor").getOrThrow().asObject();let transcript=candidateString(extractor,"transcriptHash")
        for(key in ["provider","model","exitCode","transcriptHash"]){if(!candidateHas(extractor,key)){return("","atom_extractor_invalid")}}
        if(candidateString(o,"atomId")!=candidate.identity||candidateString(o,"knowledgeFamily")!=candidate.knowledgeFamily||candidateString(o,"sourceClass")!=candidate.sourceClass||candidateString(o,"citation")!=candidate.citation||candidateString(o,"targetVersion")!=candidate.targetVersion||candidateString(o,"knowledgeText")!=candidate.explanation||candidateString(o,"example")!=candidate.example){return("","atom_candidate_mismatch")}
        if(candidate.sourceClass=="teacher_empirical"&&!teacherEmpiricalProvenanceValid(o,row,root,run)){return("","unverified_teacher_empirical")}
        if(candidateString(extractor,"provider")!="codex"||candidateString(extractor,"model")!="gpt-5.6-sol"||candidateInt(extractor,"exitCode",-1)!=0||transcript==""){return("","atom_extractor_invalid")}
        if(!candidateBool(o,"purificationPassed")){return("","atom_purification_required")}
        let tests=o.get("tests").getOrThrow().asArray().getItems();if(tests.size!=3){return("","atom_test_categories_invalid")};let categories=HashSet<String>()
        var positive="";var negative="";var boundary=""
        for(value in tests){let test=value.asObject();let category=candidateString(test,"category");if(categories.contains(category)){return("","atom_test_categories_invalid")};categories.add(category)
            let mode=candidateString(test,"expectedMode");let source=candidateString(test,"source");let operation=candidateString(test,"operation")
            if(!["contains","rune_count"].contains(operation)||candidateString(test,"input")==""||candidateString(test,"expected")==""){return("","atom_test_contract_invalid")}
            if(category=="positive"&&mode=="pass"){positive=source}else if(category=="negative"&&mode=="compile_reject"&&candidateString(test,"expectedDiagnostic")!=""){negative=source}else if(category=="boundary"&&mode=="pass"){boundary=source}else{return("","atom_test_categories_invalid")}
        }
        if(positive!=candidate.tests.positive||negative!=candidate.tests.negative||boundary!=candidate.tests.boundary){return("","atom_test_source_mismatch")}
        let testsCanonical=o.get("tests").getOrThrow().toString();let atomCanonical=candidatePart(candidate.identity)+candidatePart(candidate.sourceClass)+candidatePart(candidate.citation.toAsciiLower())+candidatePart(row.targetVersion)+candidatePart(candidate.explanation)+candidatePart("true")+candidatePart(testsCanonical)
        if(candidateString(o,"candidateHash")!="sha256:${teacherStableHash(atomCanonical)}"){return("","atom_candidate_hash_mismatch")}
        let execution=o.get("execution").getOrThrow().asObject();let commandEvidence=candidateString(execution,"commandEvidence")
        if(candidateInt(execution,"total",0)!=3||candidateInt(execution,"passed",0)!=3||candidateInt(execution,"failed",-1)!=0||candidateString(execution,"status")!="passed"||candidateString(execution,"commandEvidenceHash")!="sha256:${teacherStableHash(commandEvidence)}"){return("","atom_execution_invalid")}
        (transcript,"ok")
    }catch(_:Exception){("","malformed_atom_test_bundle")}
}

private func validateTeacherReexportCkb(raw:String,bundleRaw:String,row:TeacherGapRow,runId:String,transcriptHash:String):String{
    try{
        let o=JsonValue.fromStr(raw).asObject();let embedded=o.get("knowledgeAtomTestBundle").getOrThrow().toString();let canonical=canonicalizeTeacherCkbKnowledgeAtomBundle(bundleRaw.toArray())
        for(key in ["schemaVersion","datasetVersion","teacherRunId","evidenceHash","evidence","candidateHash","candidatePath","revision","attempt","failureTaxonomy","knowledgeGapConfirmations","caseId","benchmark","taskText","visibleTestExcerpt","compilerOutput","missingKnowledge","interfaceId","contentFamily","updateMechanism","targetVersion","officialCitation","knowledgeAtomTestBundle","knowledgeAtomCandidate"]){if(!candidateHas(o,key)){return"source_gap_missing_field"}}
        if(canonical[1]!="ok"||embedded!=canonical[0]){return"source_bundle_mismatch"}
        if(candidateString(o,"schemaVersion")!="ckb-benchmark-gap-v1"||candidateString(o,"datasetVersion")!=row.datasetVersion||candidateString(o,"teacherRunId")!=runId||candidateString(o,"caseId")!=row.caseId||candidateString(o,"benchmark")!=row.benchmark||candidateString(o,"taskText")!=row.taskText||candidateString(o,"visibleTestExcerpt")!=row.visibleTestExcerpt||candidateString(o,"compilerOutput")!=row.compilerOutput||candidateString(o,"missingKnowledge")!=row.missingKnowledge||candidateString(o,"interfaceId")!=row.interfaceId||candidateString(o,"contentFamily")!=row.contentFamily||candidateString(o,"updateMechanism")!=row.updateMechanism||candidateString(o,"targetVersion")!=row.targetVersion||candidateString(o,"officialCitation")!=row.citation){return"source_gap_binding_invalid"}
        if(row.sourceClass=="teacher_empirical"&&candidateString(o,"sourceClass")!="teacher_empirical"){return"source_gap_binding_invalid"}
        if(candidateString(o,"candidatePath")!="candidate-knowledge/ckb-benchmark-gap.jsonl"||candidateInt(o,"revision",0)!=1||candidateInt(o,"attempt",0)!=1||candidateString(o,"failureTaxonomy")!=row.failureTaxonomy||candidateInt(o,"knowledgeGapConfirmations",-1)!=row.confirmations||!candidateBool(o,"knowledgeAtomCandidate")){return"source_gap_contract_invalid"}
        let canonicalEvidence="${row.evidence}|teacherAtomHash=sha256:${teacherStableHash(canonical[0])}|extractorTranscriptHash=${transcriptHash}${teacherEmpiricalEvidenceSuffix(canonical[0],row.sourceClass)}"
        let legacyEvidence="${row.evidence}|teacherAtomHash=sha256:${teacherStableHash(bundleRaw)}|extractorTranscriptHash=${transcriptHash}${teacherEmpiricalEvidenceSuffix(bundleRaw,row.sourceClass)}"
        let evidence=candidateString(o,"evidence");if(evidence!=canonicalEvidence&&evidence!=legacyEvidence){return"source_gap_evidence_mismatch"};if(candidateString(o,"evidenceHash")!="sha256:${teacherStableHash(evidence)}"){return"source_gap_evidence_hash_mismatch"}
        let expected=teacherCkbGapCandidateHash(row,runId,if(evidence==legacyEvidence){bundleRaw}else{canonical[0]},candidateString(o,"evidenceHash"),evidence)
        if(candidateString(o,"candidateHash")!=expected){return"source_gap_candidate_hash_mismatch"};"ok"
    }catch(_:Exception){"malformed_json"}
}

private func renderTeacherReexportBundle(raw:String,execution:String):String{
    let o=JsonValue.fromStr(raw).asObject();let extractor=o.get("extractor").getOrThrow().asObject();let tests=o.get("tests").getOrThrow().toString()
    let canonical=candidatePart(candidateString(o,"atomId"))+candidatePart(candidateString(o,"sourceClass"))+candidatePart(candidateString(o,"citation").toAsciiLower())+candidatePart(candidateString(o,"targetVersion"))+candidatePart(candidateString(o,"knowledgeText"))+candidatePart("true")+candidatePart(tests)
    let provenance=match(o.get("teacherEmpiricalProvenance")){case Some(value)=>",\"teacherEmpiricalProvenance\":${value.toString()}";case None=>""}
    "{\"atomId\":\"${candidateEscape(candidateString(o,"atomId"))}\",\"knowledgeFamily\":\"${candidateEscape(candidateString(o,"knowledgeFamily"))}\",\"sourceClass\":\"${candidateEscape(candidateString(o,"sourceClass"))}\",\"citation\":\"${candidateEscape(candidateString(o,"citation"))}\",\"targetVersion\":\"${candidateEscape(candidateString(o,"targetVersion"))}\",\"candidateHash\":\"sha256:${teacherStableHash(canonical)}\",\"knowledgeText\":\"${candidateEscape(candidateString(o,"knowledgeText"))}\",\"example\":\"${candidateEscape(candidateString(o,"example"))}\",\"extractor\":{\"provider\":\"${candidateEscape(candidateString(extractor,"provider"))}\",\"model\":\"${candidateEscape(candidateString(extractor,"model"))}\",\"exitCode\":0,\"transcriptHash\":\"${candidateEscape(candidateString(extractor,"transcriptHash"))}\"},\"purificationPassed\":true,\"tests\":${tests}${provenance},\"execution\":${execution}}"
}

private func teacherReexportForbidden(raw:String):Bool{let value=raw.toAsciiLower();candidateForbidden(raw)||value.contains("/users/")||value.contains("/private/")||value.contains("authorization:")||value.contains("bearer ")||value.contains("api_key")||value.contains("token=")||value.contains("password=")||value.contains("secret=")}

private func candidateStableDiagnostic(value: String): Bool {
    ["candidate_not_exportable", "empty_manifest", "file_not_found", "invalid_manifest",
        "invalid_response_encoding", "invalid_teacher_candidate_export", "malformed_teacher_candidate_export",
        "malformed_teacher_manifest_json", "malformed_teacher_observation", "malformed_teacher_run_manifest",
        "manifest_checksum_mismatch", "solution_hash_missing", "unsupported_manifest_schema"].contains(value)
}

public func validateTeacherAuthorityRelevance(compilerOutput:String,missingKnowledge:String,explanation:String,example:String,
    positiveSource:String,negativeSource:String,boundarySource:String,positiveDependencyProfile!:String="",
    negativeDependencyProfile!:String="",boundaryDependencyProfile!:String=""):TeacherAuthorityRelevanceResult {
    let out=TeacherAuthorityRelevanceResult()
    // Extract only allow-listed quoted tokens before line sanitization: a pipe-flattened
    // compiler line may also contain "return code", which causes the whole line to be redacted.
    let gap=missingKnowledge.toAsciiLower()
    let compilerLower=compilerOutput.toAsciiLower()
    let combinedStringByteRune=gap=="g-string"&&compilerLower.contains("invalid binary operator '=='")&&
        compilerLower.contains("expected 'rune', found 'uint8'")
    let quoted=teacherAuthorityQuotedAnchors(compilerOutput)
    let extracted=ArrayList<String>()
    for(anchor in quoted){if(teacherAuthorityStrongAnchor(anchor)&&!extracted.contains(anchor.toAsciiLower())){extracted.add(anchor.toAsciiLower())}}
    let strong=ArrayList<String>()
    let primary=ArrayList<String>()
    if(gap.contains("unnecessary-undeclared-import-for-available-api")){
        strong.add("stringbuilder");strong.add("rune");primary.add("std.text")
    }else if(gap.contains("array-repeat")){
        strong.add("repeat");primary.add("item:")
    }else if(gap.contains("string-rune-array")){
        strong.add("string-constructor");strong.add("array<rune>");primary.add("fromrunearray")
    }else{
        for(anchor in extracted){strong.add(anchor)}
    }
    if(gap.contains("string-rune-contains")&&strong.isEmpty()){
        for(anchor in ["uint8","rune","contains","torunearray"]){teacherAuthorityAddAnchor(strong,anchor)}
        if(gap.contains("stringbuilder-append")){teacherAuthorityAddAnchor(strong,"stringbuilder.append")}
        primary.add("contains")
    }else if(gap.contains("string-rune-iteration")){
        strong.clear();primary.clear()
        for(anchor in ["uint8","rune","torunearray","=="]){teacherAuthorityAddAnchor(strong,anchor)}
        primary.add("==")
    }else if(gap.contains("rune-numeric-conversion")){
        strong.clear();primary.clear()
        strong.add("rune");strong.add("uint32");primary.add("rune")
    }else if(gap=="g-string-case-rune"){
        strong.clear();primary.clear()
        for(anchor in ["toasciilower","std.unicode","tolowercase"]){strong.add(anchor)}
        primary.add("tolower")
    }else if(gap=="g-rune-unicode-case"){
        strong.clear();primary.clear()
        for(anchor in ["std.unicode","rune","touppercase","tolowercase"]){strong.add(anchor)}
        primary.add("toupper");primary.add("tolower")
    }else if(gap=="g-logical-or-condition"){
        strong.clear();primary.clear();strong.add("||");primary.add("||")
    }else if(gap=="g-control-flow-parentheses"){
        strong.clear();primary.clear();strong.add("if");strong.add("while");strong.add("bool");primary.add("if")
    }else if(gap=="g-reserved-keyword-match"){
        strong.clear();primary.clear();strong.add("match");primary.add("match")
    }else if(combinedStringByteRune){
        strong.clear();primary.clear()
        strong.add("uint8");strong.add("rune");strong.add("torunearray")
        primary.add("uint8");primary.add("rune")
    }else if(gap.contains("rune-byte-compare")&&strong.isEmpty()){
        for(anchor in ["uint8","rune","torunearray"]){teacherAuthorityAddAnchor(strong,anchor)}
        primary.add("uint8");primary.add("rune")
    }else if(primary.isEmpty()){for(anchor in strong){primary.add(anchor)}}
    // In Cangjie 1.0, the numeric parse interface is provided by std.convert;
    // mentioning the method without its required import is not actionable knowledge.
    if(strong.contains("parse")&&!strong.contains("std.convert")){strong.add("std.convert")}
    // Rune case classification methods are extensions supplied by std.unicode.
    if(gap.contains("rune-unicode-import")&&!strong.contains("std.unicode")){strong.add("std.unicode")}
    let required=if(strong.isEmpty()){teacherAuthorityGapAnchors(missingKnowledge)}else{let anchors=ArrayList<String>();for(anchor in strong){anchors.add(anchor)};for(anchor in primary){teacherAuthorityAddAnchor(anchors,anchor)};anchors}
    for(anchor in required){out.anchors.add(anchor)}
    let stdxProjectAware=gap.contains("cjpm-dependency")&&compilerOutput.toAsciiLower().contains("stdx.")
    if(stdxProjectAware){for(anchor in ["cjpm.toml","bin-dependencies","path-option"]){teacherAuthorityAddAnchor(out.anchors,anchor)}}
    if(required.isEmpty()){out.diagnostic="authority_anchor_missing";out.feedback="Authority relevance failed: no safe public failure anchor was available; return knowledge that directly explains the canonical gap.";return out}
    let narrative=(explanation+"\n"+example).toAsciiLower()
    let positive=positiveSource.toAsciiLower();let negative=negativeSource.toAsciiLower();let boundary=boundarySource.toAsciiLower()
    let sources=(positive+"\n"+negative+"\n"+boundary)
    let minimum=if(required.size>1){2}else{1}
    var narrativeHits:Int64=0;var sourceHits:Int64=0
    for(anchor in required){if(teacherAuthorityAnchorPresent(narrative,anchor)){narrativeHits+=1};if(teacherAuthorityAnchorPresent(sources,anchor)){sourceHits+=1}}
    let eachSource=teacherAuthorityAnyAnchor(positive,required)&&teacherAuthorityAnyAnchor(negative,required)&&teacherAuthorityAnyAnchor(boundary,required)
    let strongCoverage=if(gap=="g-string-case-rune"||gap=="g-reserved-keyword-match"){true}else{strong.isEmpty()||teacherAuthorityAllAnchors(narrative,strong)&&teacherAuthorityAllAnchors(narrative,primary)&&teacherAuthorityAllSourceAnchors(positiveSource,strong)&&
        teacherAuthorityAllSourceAnchors(boundarySource,strong)&&teacherAuthorityAllSourceAnchors(negativeSource,primary)}
    if(narrativeHits>=minimum&&sourceHits>=minimum&&eachSource&&strongCoverage){
        let magic="$"+"{MAGIC_PATH}"
        let landedProject=narrative.contains("cjpm.toml")&&narrative.contains("[target.")&&narrative.contains(".bin-dependencies]")&&
            narrative.contains("path-option = [")&&narrative.contains(magic.toAsciiLower())&&narrative.contains("/dynamic/stdx")&&
            !narrative.contains("stdx = {")&&!narrative.contains("<bundled-stdx-path>")
        if(stdxProjectAware&&(!landedProject||
            positiveDependencyProfile!="stdx-magic"||negativeDependencyProfile!="none"||boundaryDependencyProfile!="stdx-magic")){
            out.feedback=teacherAuthorityBoundedFeedback("Stdx dependency knowledge must show cjpm.toml with an applicable [target.<triple>.bin-dependencies] table and a direct path-option = [\"${magic}/libs/.../dynamic/stdx\"] line. Do not use stdx = { ... } or <bundled-stdx-path>. Positive and boundary atom tests must use dependency profile stdx-magic; the missing-dependency negative atom test must use profile none.")
            return out
        }
        if(gap.contains("unnecessary-undeclared-import-for-available-api")&&
            (!(narrative.contains("api")&&(narrative.contains("provides")||narrative.contains("ownership")||narrative.contains("belongs"))&&
                narrative.contains("remove")&&narrative.contains("std.text"))||narrative.contains("add std.text")||narrative.contains("add a dependency")||
                narrative.contains("retain")||narrative.contains("preserve")||narrative.contains("runtime data")||
                narrative.contains("string literal")||narrative.contains("label")||narrative.contains("context")||
                positiveSource.toAsciiLower().contains("std.text")||boundarySource.toAsciiLower().contains("std.text")||
                !teacherAuthorityOnlyImportMentions(negativeSource,"std.text"))){
            out.feedback=teacherAuthorityBoundedFeedback("First verify which package provides the StringBuilder and Rune APIs, then remove the unnecessary undeclared import std.text instead of adding a dependency or retaining it as a label, context, runtime string, or comment. Positive and boundary sources must not contain std.text anywhere; the negative source may mention std.text only in its legal import line to reproduce the original dependency diagnostic.")
            return out
        }
        if(gap.contains("string-rune-iteration")&&
            (!teacherAuthorityStringRuneIterationPositive(narrative,positiveSource)||
             !teacherAuthorityStringRuneIterationPositive(narrative,boundarySource)||
             !teacherAuthorityStringRuneIterationNegative(negativeSource))){
            out.feedback=teacherAuthorityStringRuneIterationFeedback()
            return out
        }
        if(gap.contains("float64-abs")&&
            (!teacherAuthorityFloat64AbsPositive(narrative,positiveSource)||
             !teacherAuthorityFloat64AbsBoundary(narrative,boundarySource)||
             !teacherAuthorityFloat64AbsNegative(negativeSource))){
            out.feedback=teacherAuthorityFloat64AbsFeedback()
            return out
        }
        if(gap=="g-string-rune-contains"&&
            (!teacherAuthorityStringRuneContainsPositive(narrative,positiveSource)||
             !teacherAuthorityStringRuneContainsPositive(narrative,boundarySource)||
             !teacherAuthorityStringRuneContainsNegative(negativeSource))){
            out.feedback=teacherAuthorityStringRuneContainsFeedback()
            return out
        }
        if(gap=="g-string-case-rune"&&
            (!teacherAuthorityStringCaseRuneCompilerFact(compilerOutput)||
             !teacherAuthorityStringCaseRuneNarrative(narrative)||
             !teacherAuthorityStringCaseRunePositive(positiveSource)||
             !teacherAuthorityStringCaseRuneBoundary(boundarySource)||
             !teacherAuthorityStringCaseRuneNegative(negativeSource)||
             positiveDependencyProfile=="stdx-magic"||negativeDependencyProfile=="stdx-magic"||boundaryDependencyProfile=="stdx-magic")){
            out.feedback=teacherAuthorityStringCaseRuneFeedback()
            return out
        }
        if(gap=="g-rune-numeric-conversion"&&
            (!teacherAuthorityRuneNumericPositive(narrative,positiveSource)||
             !teacherAuthorityRuneNumericPositive(narrative,boundarySource)||
             !teacherAuthorityRuneNumericNegative(negativeSource))){
            out.feedback=teacherAuthorityRuneNumericFeedback()
            return out
        }
        if(gap=="g-rune-unicode-case"&&
            (!teacherAuthorityRuneUnicodeCaseNarrative(narrative)||
             !teacherAuthorityRuneUnicodeCasePositive(positiveSource)||
             !teacherAuthorityRuneUnicodeCaseBoundary(boundarySource)||
             !teacherAuthorityRuneUnicodeCaseNegative(negativeSource)||
             positiveDependencyProfile=="stdx-magic"||negativeDependencyProfile=="stdx-magic"||boundaryDependencyProfile=="stdx-magic")){
            out.feedback=teacherAuthorityRuneUnicodeCaseFeedback()
            return out
        }
        if(gap=="g-logical-or-condition"&&
            (!teacherAuthorityLogicalOrCompilerFact(compilerOutput)||
             !teacherAuthorityLogicalOrNarrative(narrative)||
             !teacherAuthorityLogicalOrPositive(positiveSource)||
             !teacherAuthorityLogicalOrPositive(boundarySource)||
             !teacherAuthorityLogicalOrNegative(negativeSource)||
             positiveDependencyProfile=="stdx-magic"||negativeDependencyProfile=="stdx-magic"||boundaryDependencyProfile=="stdx-magic")){
            out.feedback=teacherAuthorityLogicalOrFeedback()
            return out
        }
        if(gap=="g-control-flow-parentheses"&&
            (!teacherAuthorityControlFlowParenthesesCompilerFact(compilerOutput)||
             !teacherAuthorityControlFlowParenthesesNarrative(narrative)||
             !teacherAuthorityControlFlowParenthesesPositive(positiveSource)||
             !teacherAuthorityControlFlowParenthesesPositive(boundarySource)||
             !teacherAuthorityControlFlowParenthesesNegative(negativeSource)||
             positiveDependencyProfile=="stdx-magic"||negativeDependencyProfile=="stdx-magic"||boundaryDependencyProfile=="stdx-magic")){
            out.feedback=teacherAuthorityControlFlowParenthesesFeedback()
            return out
        }
        if(gap=="g-reserved-keyword-match"&&
            (!teacherAuthorityReservedMatchCompilerFact(compilerOutput)||
             !teacherAuthorityReservedMatchNarrative(narrative)||
             !teacherAuthorityReservedMatchPositive(positiveSource)||
             !teacherAuthorityReservedMatchBoundary(boundarySource)||
             !teacherAuthorityReservedMatchNegative(negativeSource)||
             positiveDependencyProfile=="stdx-magic"||negativeDependencyProfile=="stdx-magic"||boundaryDependencyProfile=="stdx-magic")){
            out.feedback=teacherAuthorityReservedMatchFeedback()
            return out
        }
        if(combinedStringByteRune&&
            (!teacherAuthorityCombinedStringByteRunePositive(narrative,positiveSource)||
             !teacherAuthorityCombinedStringByteRunePositive(narrative,boundarySource)||
             !teacherAuthorityCombinedStringByteRuneNegative(negativeSource))){
            out.feedback=teacherAuthorityCombinedStringByteRuneFeedback()
            return out
        }
        out.ok=true;out.diagnostic="ok";return out
    }
    var names="";for(i in 0..required.size){if(i>0){names+=","};names+=required[i]}
    if(combinedStringByteRune){
        out.feedback=teacherAuthorityCombinedStringByteRuneFeedback()
    }else if(gap=="g-rune-numeric-conversion"){
        out.feedback=teacherAuthorityRuneNumericFeedback()
    }else if(gap=="g-rune-unicode-case"){
        out.feedback=teacherAuthorityRuneUnicodeCaseFeedback()
    }else if(gap=="g-logical-or-condition"){
        out.feedback=teacherAuthorityLogicalOrFeedback()
    }else if(gap=="g-control-flow-parentheses"){
        out.feedback=teacherAuthorityControlFlowParenthesesFeedback()
    }else if(gap=="g-reserved-keyword-match"){
        out.feedback=teacherAuthorityReservedMatchFeedback()
    }else if(gap=="g-string-rune-contains"){
        out.feedback=teacherAuthorityStringRuneContainsFeedback()
    }else if(gap=="g-string-case-rune"){
        out.feedback=teacherAuthorityStringCaseRuneFeedback()
    }else if(gap.contains("float64-abs")){
        out.feedback=teacherAuthorityFloat64AbsFeedback()
    }else if(gap.contains("string-rune-iteration")){
        out.feedback=teacherAuthorityStringRuneIterationFeedback()
    }else if(gap.contains("rune-unicode-import")){
        out.feedback=teacherAuthorityBoundedFeedback("Authority relevance failed. Positive and boundary sources must each import std.unicode.* and call both Rune.isLowerCase() and isUpperCase(). The negative source must omit that import and call both Rune.isLowerCase() and Rune.isUpperCase() to reproduce the undeclared-identifier diagnostic. Keep the explanation and example aligned with those same public APIs; do not use comments or private evidence to satisfy the check.")
    }else if(gap.contains("string-rune-contains")){
        let builderRequirement=if(gap.contains("stringbuilder-append")){" For the StringBuilder variant, also demonstrate StringBuilder.append(Rune)."}else{""}
        out.feedback=teacherAuthorityBoundedFeedback("Authority relevance failed. Positive and boundary sources must each demonstrate UInt8, Rune, toRuneArray, and Array<Rune>.contains(Rune). The negative source must demonstrate the original mismatch with String.contains(Rune) or Array<UInt8>.contains(Rune).${builderRequirement} Keep the explanation and example aligned with these public type/API relationships; do not use comments or private evidence to satisfy the check.")
    }else{
        out.feedback=teacherAuthorityBoundedFeedback("Authority relevance failed. Required public failure anchors and prerequisites: ${names}. The explanation and example, plus positive and boundary sources, must demonstrate every listed item. The negative source must demonstrate the primary public failure anchor but may intentionally omit a prerequisite to prove the failure. Do not satisfy this check with comments, substitute a generic type fact, or include private paths, secrets, solutions, hidden tests, or references.")
    }
    out
}

private func teacherAuthorityCompactCode(source:String):String{
    teacherAuthorityCodeOnly(source).toAsciiLower().replace(" ","").replace("\t","").replace("\n","").replace("\r","")
}

private func teacherAuthorityLogicalOrCompilerFact(compilerOutput:String):Bool{
    let value=compilerOutput.toAsciiLower()
    value.contains("expected '{'")&&value.contains("found '||'")
}

private func teacherAuthorityControlFlowParenthesesCompilerFact(compilerOutput:String):Bool{
    let value=compilerOutput.toAsciiLower()
    value.contains("expected '('")&&value.contains("expected '(' after 'if'")
}

private func teacherAuthorityControlFlowParenthesesNarrative(narrative:String):Bool{
    narrative.contains("if")&&narrative.contains("while")&&narrative.contains("bool")&&
        narrative.contains("condition")&&narrative.contains("parenthes")&&
        (narrative.contains("brace")||narrative.contains("block"))
}

private func teacherAuthorityControlFlowParenthesesMain(source:String):Bool{
    let code=teacherAuthorityCompactCode(source)
    !code.contains("funcmain(")&&(code.contains("main(){")||code.contains("main():unit{"))
}

private func teacherAuthorityControlFlowParenthesesPositive(source:String):Bool{
    if(!teacherAuthorityControlFlowParenthesesMain(source)){return false}
    let raw=teacherAuthorityCodeOnly(source).toAsciiLower();let code=teacherAuthorityCompactCode(source)
    if(teacherAuthorityNamesBeforeType(raw,"bool").isEmpty()){return false}
    code.contains("if(")&&code.contains("while(")
}

private func teacherAuthorityControlFlowParenthesesNegative(source:String):Bool{
    if(!teacherAuthorityControlFlowParenthesesMain(source)){return false}
    let raw=teacherAuthorityCodeOnly(source).toAsciiLower();let code=teacherAuthorityCompactCode(source)
    for(name in teacherAuthorityNamesBeforeType(raw,"bool")){
        if(code.contains("if${name}{")&&!code.contains("if(${name}){")){return true}
    }
    false
}

private func teacherAuthorityControlFlowParenthesesFeedback():String{
    teacherAuthorityBoundedFeedback("Cangjie if and while control-flow expressions require a Bool condition enclosed in parentheses before the brace-delimited block. Positive and boundary sources must use main() without func, declare explicit Bool values, and demonstrate both if (condition) { ... } and while (condition) { ... }. The negative source must declare an explicit Bool and use if condition { ... } without the required parentheses to reproduce expected '(' after 'if'. Do not substitute a non-Bool condition, logical-OR placement error, func main, comments, or string labels. All dependency profiles are none.")
}

private func teacherAuthorityReservedMatchCompilerFact(compilerOutput:String):Bool{
    let value=compilerOutput.toAsciiLower()
    value.contains("expected identifier or pattern after 'var'")&&value.contains("found keyword 'match'")
}

private func teacherAuthorityReservedMatchNarrative(narrative:String):Bool{
    let ordinary=narrative.contains("ordinary identifier")&&narrative.contains("keyword")&&narrative.contains("match")&&
        (narrative.contains("cannot")||narrative.contains("must not"))
    let rename=narrative.contains("ismatch")&&(narrative.contains("rename")||narrative.contains("name"))
    let raw=narrative.contains("raw identifier")&&narrative.contains("`match`")&&
        (narrative.contains("legal")||narrative.contains("allowed")||narrative.contains("can be")||narrative.contains("use the raw"))
    ordinary&&rename&&raw
}

private func teacherAuthorityReservedMatchPositive(source:String):Bool{
    let code=teacherAuthorityCompactCode(source)
    !code.contains("varmatch")&&!code.contains("var`match`")&&
        code.contains("varismatch:bool=")&&code.contains("println(ismatch)")
}

private func teacherAuthorityReservedMatchBoundary(source:String):Bool{
    let code=teacherAuthorityCompactCode(source)
    code.contains("var`match`:bool=")&&code.contains("println(`match`)")&&!code.contains("varmatch")
}

private func teacherAuthorityReservedMatchNegative(source:String):Bool{
    let code=teacherAuthorityCompactCode(source)
    code.contains("varmatch:bool=")&&code.contains("println(match)")&&!code.contains("`match`")
}

private func teacherAuthorityReservedMatchFeedback():String{
    teacherAuthorityBoundedFeedback("Cangjie reserves match as a keyword, so plain var match cannot declare an ordinary identifier. The explanation/example must distinguish ordinary identifiers from raw identifiers: rename the variable to isMatch, or use the legal raw identifier `match` with backticks when retaining the spelling. The positive source must declare var isMatch: Bool and use isMatch. The boundary source must declare and use var `match`: Bool. The negative source must declare and use plain var match: Bool to reproduce expected identifier or pattern after 'var', found keyword 'match'. Do not claim that match can never be an identifier, and do not satisfy the gate with comments or string labels. All dependency profiles are none.")
}

private func teacherAuthorityStringCaseRuneCompilerFact(compilerOutput:String):Bool{
    let value=compilerOutput.toAsciiLower()
    value.contains("'tolower'")&&value.contains("not a member")&&value.contains("'string'")
}

private func teacherAuthorityStringCaseRuneNarrative(narrative:String):Bool{
    narrative.contains("string.toasciilower()")&&narrative.contains("ascii")&&narrative.contains("non-ascii")&&
        (narrative.contains("unchanged")||narrative.contains("preserv"))&&narrative.contains("std.unicode")&&
        narrative.contains("rune.tolowercase()")&&narrative.contains("string.tolower()")&&
        (narrative.contains("unavailable")||narrative.contains("not a member")||narrative.contains("does not provide"))&&
        !narrative.contains("tolowerascii")
}

private func teacherAuthorityStringCaseRunePositive(source:String):Bool{
    let raw=teacherAuthorityRuneUnicodeCaseCodeOnly(source).toAsciiLower();let code=teacherAuthorityCompactCode(source)
    if(code.contains(".tolowerascii(")||code.contains(".tolower(")||code.contains(".tolowercase(")){return false}
    teacherAuthorityStringAsciiLowerAssignment(raw,code,false)
}

private func teacherAuthorityStringCaseRuneBoundary(source:String):Bool{
    let raw=teacherAuthorityRuneUnicodeCaseCodeOnly(source).toAsciiLower();let code=teacherAuthorityCompactCode(source)
    if(!teacherAuthorityHasImport(raw,"std.unicode")||code.contains(".tolowerascii(")||code.contains(".tolower(")){return false}
    if(!teacherAuthorityStringAsciiLowerAssignment(raw,code,true)||!teacherAuthorityHasNonAsciiStringLiteral(source)||!teacherAuthorityHasNonAsciiRuneLiteral(source)){return false}
    for(rune in teacherAuthorityNamesBeforeType(raw,"rune")){if(code.contains("${rune}.tolowercase()")){return true}}
    false
}

private func teacherAuthorityStringCaseRuneNegative(source:String):Bool{
    let raw=teacherAuthorityRuneUnicodeCaseCodeOnly(source).toAsciiLower();let code=teacherAuthorityCompactCode(source)
    if(code.contains(".toasciilower(")||code.contains(".tolowerascii(")||code.contains(".tolowercase(")){return false}
    for(text in teacherAuthorityNamesBeforeType(raw,"string")){if(code.contains("${text}.tolower()")){return true}}
    false
}

private func teacherAuthorityStringAsciiLowerAssignment(raw:String,code:String,requirePreservation:Bool):Bool{
    let strings=teacherAuthorityNamesBeforeType(raw,"string")
    for(receiver in strings){for(result in strings){
        if(receiver==result||!code.contains("${result}:string=${receiver}.toasciilower()")){continue}
        if(!requirePreservation||code.contains("if(${result}!=${receiver}){throw")||code.contains("if(${receiver}!=${result}){throw")){return true}
    }}
    false
}

private func teacherAuthorityHasNonAsciiRuneLiteral(source:String):Bool{
    let runes=teacherAuthorityRuneUnicodeCaseCodeOnly(source).toRuneArray()
    if(runes.size<4){return false}
    for(i in 0..runes.size-3){if(runes[i]==r'r'&&runes[i+1]==r'\''&&runes[i+2]>r'\u{007f}'&&runes[i+3]==r'\''){return true}}
    false
}

private func teacherAuthorityHasNonAsciiStringLiteral(source:String):Bool{
    let runes=source.toRuneArray();var quoted=false;var escaped=false;var lineComment=false;var blockComment=false;var i:Int64=0
    while(i<runes.size){let c=runes[i];let next=if(i+1<runes.size){runes[i+1]}else{r'\u{0000}'}
        if(lineComment){if(c==r'\n'){lineComment=false};i+=1;continue}
        if(blockComment){if(c==r'*'&&next==r'/'){blockComment=false;i+=2}else{i+=1};continue}
        if(quoted){if(escaped){escaped=false}else if(c==r'\\'){escaped=true}else if(c==r'"'){quoted=false}else if(c>r'\u{007f}'){return true};i+=1;continue}
        if(c==r'/'&&next==r'/'){lineComment=true;i+=2;continue}
        if(c==r'/'&&next==r'*'){blockComment=true;i+=2;continue}
        if(c==r'"'){quoted=true};i+=1
    }
    false
}

private func teacherAuthorityStringCaseRuneFeedback():String{
    teacherAuthorityBoundedFeedback("String has no toLower() member. The explanation/example must distinguish String.toAsciiLower(), which converts ASCII letters only and leaves non-ASCII text unchanged, from Unicode Rune conversion via import std.unicode.* and Rune.toLowerCase(); never use the nonexistent toLowerAscii name. The positive source must assign String.toAsciiLower() to an explicitly typed String. The boundary source must use a non-ASCII String and Rune, assert that toAsciiLower leaves the String unchanged, import std.unicode.*, and call toLowerCase() on the explicit Rune. The negative source must call toLower() on an explicit String to reproduce the compiler substring 'toLower' is not a member of struct 'String'. This standard-library knowledge requires no stdx-magic dependency; comments and string labels do not count as evidence.")
}

private func teacherAuthorityLogicalOrNarrative(narrative:String):Bool{
    narrative.contains("||")&&narrative.contains("bool")&&narrative.contains("condition")&&
        (narrative.contains("parenthes")||narrative.contains("inside"))&&
        (narrative.contains("brace")||narrative.contains("block")||narrative.contains("expected '{'"))
}

private func teacherAuthorityLogicalOrCode(source:String):String{
    teacherAuthorityRuneUnicodeCaseCodeOnly(source).toAsciiLower().replace(" ","").replace("\t","").replace("\n","").replace("\r","")
}

private func teacherAuthorityLogicalOrMainAndTypes(source:String):Bool{
    let raw=teacherAuthorityRuneUnicodeCaseCodeOnly(source).toAsciiLower()
    let code=teacherAuthorityLogicalOrCode(source)
    if(code.contains("funcmain(")||(!code.contains("main(){")&&!code.contains("main():unit{"))||teacherAuthorityHasIdentifierToken(raw,"or")){return false}
    teacherAuthorityNamesBeforeType(raw,"bool").size>=2
}

private func teacherAuthorityLogicalOrPositive(source:String):Bool{
    if(!teacherAuthorityLogicalOrMainAndTypes(source)){return false}
    let raw=teacherAuthorityRuneUnicodeCaseCodeOnly(source).toAsciiLower()
    let code=teacherAuthorityLogicalOrCode(source)
    let names=teacherAuthorityNamesBeforeType(raw,"bool")
    for(left in names){for(right in names){
        if(left!=right&&(code.contains("if(${left}||${right}){")||code.contains("while(${left}||${right}){"))){return true}
    }}
    false
}

private func teacherAuthorityLogicalOrNegative(source:String):Bool{
    if(!teacherAuthorityLogicalOrMainAndTypes(source)){return false}
    let raw=teacherAuthorityRuneUnicodeCaseCodeOnly(source).toAsciiLower()
    let code=teacherAuthorityLogicalOrCode(source)
    let names=teacherAuthorityNamesBeforeType(raw,"bool")
    for(left in names){for(right in names){
        if(left!=right&&(code.contains("if(${left})||(${right}){")||code.contains("while(${left})||(${right}){"))){return true}
    }}
    false
}

private func teacherAuthorityHasIdentifierToken(source:String,token:String):Bool{
    let runes=source.toRuneArray();let target=token.toRuneArray()
    if(target.isEmpty()||runes.size<target.size){return false}
    for(i in 0..=runes.size-target.size){
        var matches=true
        for(j in 0..target.size){if(runes[i+j]!=target[j]){matches=false;break}}
        if(matches){
            let leftOk=i==0||!teacherAuthorityIdentifierRune(runes[i-1])
            let after=i+target.size
            let rightOk=after>=runes.size||!teacherAuthorityIdentifierRune(runes[after])
            if(leftOk&&rightOk){return true}
        }
    }
    false
}

private func teacherAuthorityLogicalOrFeedback():String{
    teacherAuthorityBoundedFeedback("Cangjie logical OR uses Bool || Bool inside one complete parenthesized if or while condition. Positive and boundary sources must explicitly declare two Bool operands, use main() without the func keyword, and compile a form such as if (left || right) { ... }. The negative source must declare the same Bool operand types and reproduce the authority placement error with if (left) || (right) { ... }; set negativeDiagnostic to the compiler substring expected '{', found '||'. Do not substitute Int/Bool type errors, the nonexistent or keyword, func main, comments, or string labels. This syntax requires no stdx-magic dependency.")
}

private func teacherAuthorityStringRuneIterationPositive(narrative:String,source:String):Bool{
    let code=teacherAuthorityCompactCode(source)
    narrative.contains("direct string iteration")&&narrative.contains("uint8")&&narrative.contains("rune")&&
        narrative.contains("torunearray")&&(narrative.contains("same type")||narrative.contains("same-type"))&&
        code.contains(":string")&&code.contains("for(")&&code.contains("in")&&code.contains(":uint8")&&
        code.contains(":rune")&&code.contains(".torunearray(")&&code.contains("==")
}

private func teacherAuthorityStringRuneIterationNegative(source:String):Bool{
    let code=teacherAuthorityCompactCode(source)
    code.contains(":string")&&code.contains("for(")&&code.contains("in")&&code.contains("==")&&
        code.contains("r'")&&!code.contains(".torunearray(")
}

private func teacherAuthorityStringRuneIterationFeedback():String{
    teacherAuthorityBoundedFeedback("Direct String iteration produces UInt8 values, which are distinct from Rune values; positive and boundary sources must each demonstrate direct String iteration with UInt8, call toRuneArray to obtain Rune values, and compare only same-typed values with ==. The negative source must iterate a String directly and compare that UInt8 element with a Rune literal to reproduce the UInt8 == Rune diagnostic. Comments and string labels do not count as evidence.")
}

private func teacherAuthorityFloat64AbsNarrative(narrative:String):Bool{
    narrative.contains("global")&&narrative.contains("abs(value)")&&narrative.contains(".abs(")&&
        (narrative.contains("receiver")||narrative.contains("member"))
}

private func teacherAuthorityFloat64AbsPositive(narrative:String,source:String):Bool{
    let code=teacherAuthorityCompactCode(source)
    teacherAuthorityFloat64AbsNarrative(narrative)&&teacherAuthorityHasGlobalAbsCall(code)&&
        !code.contains(".abs(")&&code.contains(":float64")&&code.contains("-")
}

private func teacherAuthorityFloat64AbsBoundary(narrative:String,source:String):Bool{
    let code=teacherAuthorityCompactCode(source)
    teacherAuthorityFloat64AbsNarrative(narrative)&&teacherAuthorityHasGlobalAbsCall(code)&&
        !code.contains(".abs(")&&code.contains("abs(-0.0)")&&code.contains("abs(0.0)")
}

private func teacherAuthorityFloat64AbsNegative(source:String):Bool{
    let code=teacherAuthorityCompactCode(source)
    code.contains(":float64")&&code.contains(".abs(")
}

private func teacherAuthorityHasGlobalAbsCall(code:String):Bool{
    let runes=code.toRuneArray();let token="abs(".toRuneArray()
    if(runes.size<token.size){return false}
    for(i in 0..=runes.size-token.size){
        var matches=true
        for(j in 0..token.size){if(runes[i+j]!=token[j]){matches=false;break}}
        if(matches){
            if(i==0){return true}
            let previous=runes[i-1]
            let identifier=(previous>=r'a'&&previous<=r'z')||(previous>=r'0'&&previous<=r'9')||previous==r'_'
            if(!identifier&&previous!=r'.'){return true}
        }
    }
    false
}

private func teacherAuthorityFloat64AbsFeedback():String{
    teacherAuthorityBoundedFeedback("Float64 absolute value uses the global abs(value) function, not a receiver or member value.abs() call. Positive source must call global abs with a negative Float64; boundary source must call global abs(-0.0) and abs(0.0); neither may contain .abs(. The negative source must call a Float64 member .abs() to reproduce the undeclared-identifier diagnostic. Comments and string labels do not count as evidence.")
}

private func teacherAuthorityStringRuneContainsPositive(narrative:String,source:String):Bool{
    let raw=teacherAuthorityCodeOnly(source).toAsciiLower();let code=teacherAuthorityCompactCode(source)
    if(!narrative.contains("array<rune>.contains(rune)")||!code.contains(":uint8")||!code.contains(".torunearray(")){return false}
    teacherAuthorityTypedReceiverContainsRune(raw,code,"array<rune>")
}

private func teacherAuthorityStringRuneContainsNegative(source:String):Bool{
    let raw=teacherAuthorityCodeOnly(source).toAsciiLower();let code=teacherAuthorityCompactCode(source)
    teacherAuthorityTypedReceiverContainsRune(raw,code,"string")||teacherAuthorityTypedReceiverContainsRune(raw,code,"array<uint8>")
}

private func teacherAuthorityTypedReceiverContainsRune(raw:String,code:String,receiverType:String):Bool{
    let receivers=teacherAuthorityNamesBeforeType(raw,receiverType)
    let runes=teacherAuthorityNamesBeforeType(raw,"rune")
    for(receiver in receivers){
        for(rune in runes){if(code.contains("${receiver}.contains(${rune})")){return true}}
        if(code.contains("${receiver}.contains(r'")){return true}
    }
    false
}

private func teacherAuthorityNamesBeforeType(raw:String,typeName:String):ArrayList<String>{
    let out=ArrayList<String>();let runes=raw.toRuneArray();let typeRunes=typeName.toRuneArray()
    for(i in 0..runes.size){
        if(runes[i]!=r':'){continue}
        var typeStart=i+1
        while(typeStart<runes.size&&teacherAuthorityAsciiSpace(runes[typeStart])){typeStart+=1}
        if(typeStart+typeRunes.size>runes.size){continue}
        var matches=true
        for(j in 0..typeRunes.size){if(runes[typeStart+j]!=typeRunes[j]){matches=false;break}}
        if(!matches||i==0){continue}
        var end=i-1
        while(end>=0&&teacherAuthorityAsciiSpace(runes[end])){end-=1}
        var start=end
        while(start>=0&&teacherAuthorityIdentifierRune(runes[start])){start-=1}
        start+=1
        if(start<=end){let name=String(runes[start..end+1]);if(!out.contains(name)){out.add(name)}}
    }
    out
}

private func teacherAuthorityIdentifierRune(value:Rune):Bool{
    (value>=r'a'&&value<=r'z')||(value>=r'0'&&value<=r'9')||value==r'_'
}

private func teacherAuthorityAsciiSpace(value:Rune):Bool{
    value==r' '||value==r'\t'||value==r'\n'||value==r'\r'
}

private func teacherAuthorityStringRuneContainsFeedback():String{
    teacherAuthorityBoundedFeedback("Use explicit type annotations in every source, and the explanation or example must state exactly Array<Rune>.contains(Rune). Positive and boundary sources must declare runes: Array<Rune> from toRuneArray, needle: Rune, and byte: UInt8, then call the Array<Rune> receiver's contains with that Rune. The negative source must declare either text: String and needle: Rune before calling text.contains(needle) on that String receiver, or bytes: Array<UInt8> and needle: Rune before calling bytes.contains(needle) on that Array<UInt8> receiver, to reproduce the mismatched-types diagnostic. String construction from UInt8, String.contains(String), comments, and string labels do not satisfy this gate.")
}

private func teacherAuthorityRuneNumericPositive(narrative:String,source:String):Bool{
    if(!narrative.contains("uint32(rune)")||
        !(narrative.contains("first")||narrative.contains("two-step")||narrative.contains("two step"))){return false}
    let raw=teacherAuthorityCodeOnly(source).toAsciiLower();let code=teacherAuthorityCompactCode(source)
    for(rune in teacherAuthorityNamesBeforeType(raw,"rune")){
        for(target in teacherAuthorityRuneNumericTargets()){
            if(code.contains("${target}(uint32(${rune}))")){return true}
        }
    }
    false
}

private func teacherAuthorityRuneNumericNegative(source:String):Bool{
    let raw=teacherAuthorityCodeOnly(source).toAsciiLower();let code=teacherAuthorityCompactCode(source)
    for(rune in teacherAuthorityNamesBeforeType(raw,"rune")){
        if(code.contains("uint32(${rune})")){continue}
        for(target in teacherAuthorityRuneNumericTargets()){
            if(code.contains("${target}(${rune})")){return true}
        }
    }
    false
}

private func teacherAuthorityRuneNumericTargets():Array<String>{
    ["int8","int16","int32","int64","intnative","uint8","uint16","uint64","uintnative","float16","float32","float64"]
}

private func teacherAuthorityRuneNumericFeedback():String{
    teacherAuthorityBoundedFeedback("Rune numeric conversion is two-step: first obtain the Unicode scalar with UInt32(rune), then apply the target numeric conversion, for example Float64(UInt32(rune)) or Int64(UInt32(rune)). Positive and boundary sources must declare rune: Rune and execute that nested conversion for ASCII, zero, Chinese, or emoji values. The negative source must declare rune: Rune and use a direct target conversion such as Float64(rune) or Int64(rune) to reproduce the numeric-conversion diagnostic. Comments and string labels do not count as evidence.")
}

private func teacherAuthorityRuneUnicodeCaseNarrative(narrative:String):Bool{
    narrative.contains("rune")&&narrative.contains("std.unicode")&&
        narrative.contains("rune.touppercase()")&&narrative.contains("rune.tolowercase()")&&
        narrative.contains("rune.toupper()")&&narrative.contains("rune.tolower()")&&
        (narrative.contains("not declared")||narrative.contains("undeclared"))
}

private func teacherAuthorityRuneUnicodeCasePositive(source:String):Bool{
    let raw=teacherAuthorityRuneUnicodeCaseCodeOnly(source).toAsciiLower();let code=raw.replace(" ","").replace("\t","").replace("\n","").replace("\r","")
    if(!teacherAuthorityHasImport(raw,"std.unicode")){return false}
    var upper=false;var lower=false
    for(rune in teacherAuthorityNamesBeforeType(raw,"rune")){
        if(code.contains("${rune}.touppercase()")){upper=true}
        if(code.contains("${rune}.tolowercase()")){lower=true}
    }
    upper&&lower&&!code.contains(".toupper()")&&!code.contains(".tolower()")
}

private func teacherAuthorityRuneUnicodeCaseNegative(source:String):Bool{
    let raw=teacherAuthorityRuneUnicodeCaseCodeOnly(source).toAsciiLower();let code=raw.replace(" ","").replace("\t","").replace("\n","").replace("\r","")
    if(!teacherAuthorityHasImport(raw,"std.unicode")){return false}
    var upper=false;var lower=false
    for(rune in teacherAuthorityNamesBeforeType(raw,"rune")){
        if(code.contains("${rune}.toupper()")){upper=true}
        if(code.contains("${rune}.tolower()")){lower=true}
    }
    upper&&lower&&!code.contains(".touppercase()")&&!code.contains(".tolowercase()")
}

private func teacherAuthorityRuneUnicodeCaseBoundary(source:String):Bool{
    if(!teacherAuthorityRuneUnicodeCasePositive(source)){return false}
    let runes=teacherAuthorityRuneUnicodeCaseCodeOnly(source).toRuneArray()
    if(runes.size<4){return false}
    for(i in 0..runes.size-3){
        if(runes[i]==r'r'&&runes[i+1]==r'\''&&runes[i+2]>r'\u{007f}'&&runes[i+3]==r'\''){return true}
    }
    false
}

private func teacherAuthorityRuneUnicodeCaseCodeOnly(source:String):String{
    let code=teacherAuthorityCodeOnly(source);let runes=code.toRuneArray();let out=ArrayList<Rune>()
    var block=false;var i:Int64=0
    while(i<runes.size){
        if(!block&&runes[i]==r'/'&&i+1<runes.size&&runes[i+1]==r'*'){block=true;i+=2;continue}
        if(block&&runes[i]==r'*'&&i+1<runes.size&&runes[i+1]==r'/'){block=false;i+=2;continue}
        if(!block){out.add(runes[i])};i+=1
    }
    String(out.toArray())
}

private func teacherAuthorityRuneUnicodeCaseFeedback():String{
    teacherAuthorityBoundedFeedback("Rune Unicode case conversion is provided by the Cangjie 1.0 std.unicode Rune extensions. The explanation/example must say to import std.unicode.*, call Rune.toUpperCase() and Rune.toLowerCase(), and state that Rune.toUpper() and Rune.toLower() are undeclared. Positive and boundary sources must import std.unicode.*, explicitly declare Rune receivers, and call both correct methods; use Chinese or emoji in the boundary source. The negative source must keep the import, explicitly declare Rune receivers, and call both incorrect methods to reproduce the two undeclared-identifier diagnostics. This standard-library API needs no stdx-magic dependency. Comments and string labels do not count as evidence.")
}

private func teacherAuthorityCombinedStringByteRunePositive(narrative:String,source:String):Bool{
    if(!narrative.contains("string")||!narrative.contains("uint8")||!narrative.contains("torunearray")||
        !narrative.contains("rune")||!(narrative.contains("same type")||narrative.contains("same-type"))||
        !teacherAuthorityRuneParameterFact(narrative)){return false}
    let raw=teacherAuthorityCodeOnly(source).toAsciiLower();let code=teacherAuthorityCompactCode(source)
    let bytes=teacherAuthorityNamesBeforeType(raw,"uint8");let runes=teacherAuthorityNamesBeforeType(raw,"rune")
    if(!code.contains(":string")||!code.contains(":array<rune>")||!code.contains(".torunearray(")||
        !code.contains("funcacceptrune(value:rune)")){return false}
    if(!teacherAuthorityHasSameTypeEquality(code,bytes)||!teacherAuthorityHasSameTypeEquality(code,runes)){return false}
    for(rune in runes){if(code.contains("acceptrune(${rune})")){return true}}
    false
}

private func teacherAuthorityRuneParameterFact(narrative:String):Bool{
    narrative.contains("rune parameter")||
        (narrative.contains("parameter declared as rune")&&narrative.contains("rune argument"))
}

private func teacherAuthorityCombinedStringByteRuneNegative(source:String):Bool{
    let raw=teacherAuthorityCodeOnly(source).toAsciiLower();let code=teacherAuthorityCompactCode(source)
    let bytes=teacherAuthorityNamesBeforeType(raw,"uint8");let runes=teacherAuthorityNamesBeforeType(raw,"rune")
    if(!code.contains("funcacceptrune(value:rune)")){return false}
    for(byte in bytes){
        for(rune in runes){
            if((code.contains("${byte}==${rune}")||code.contains("${rune}==${byte}"))&&
                code.contains("acceptrune(${byte})")){return true}
        }
    }
    false
}

private func teacherAuthorityHasSameTypeEquality(code:String,names:ArrayList<String>):Bool{
    for(left in names){for(right in names){if(left!=right&&code.contains("${left}==${right}")){return true}}}
    false
}

private func teacherAuthorityCombinedStringByteRuneFeedback():String{
    teacherAuthorityBoundedFeedback("String element access produces UInt8, while toRuneArray produces Rune values. Positive and boundary sources must explicitly declare text: String, byte/otherByte: UInt8, runes: Array<Rune>, and rune/otherRune: Rune; compare UInt8 == UInt8 and Rune == Rune, define acceptRune(value: Rune), and call acceptRune(rune). The same negative source must reproduce both authority failures by comparing byte == rune and calling acceptRune(byte). The explanation/example must state the same-type comparison and use one of these precise facts: 'a Rune parameter requires a Rune' or 'a parameter declared as Rune requires a Rune argument'. Scattered parameter/Rune words, comments, and string labels do not count as evidence.")
}

private func teacherAuthorityQuotedAnchors(value:String):ArrayList<String>{
    let out=ArrayList<String>();let runes=value.toRuneArray();var open:Int64=-1
    for(i in 0..runes.size){if(runes[i]==r'\''){if(open<0){open=i+1}else{let raw=String(runes[open..i]).trimAscii();if(teacherAuthorityAnchorAllowed(raw)&&!out.contains(raw)){out.add(raw)};open=-1}}}
    out
}

private func teacherAuthorityAnchorAllowed(value:String):Bool{
    let runes=value.toRuneArray();if(runes.isEmpty()||runes.size>64||value.contains("/")||value.contains("\\")||value.toAsciiLower().contains("cangjie_humaneval")){return false}
    var meaningful=false
    for(c in runes){let ok=(c>=r'a'&&c<=r'z')||(c>=r'A'&&c<=r'Z')||(c>=r'0'&&c<=r'9')||c==r'_'||c==r'.'||c==r'|'||c==r'&'||c==r'='||c==r'!'||c==r'<'||c==r'>'||c==r'+'||c==r'-'||c==r'*'||c==r'%';if(!ok){return false};if((c>=r'a'&&c<=r'z')||(c>=r'A'&&c<=r'Z')||c==r'|'||c==r'&'||c==r'='){meaningful=true}}
    meaningful
}

private func teacherAuthorityStrongAnchor(value:String):Bool{
    let lower=value.toAsciiLower()
    if(["float16","float32","float64","int8","int16","int32","int64","uint8","uint16","uint32","uint64","rune","string","struct-string","arraylist","hashmap","bool","true","false","if","type","expected","found"].contains(lower)){return false}
    true
}

private func teacherAuthorityAddAnchor(anchors:ArrayList<String>,anchor:String):Unit{if(!anchors.contains(anchor)){anchors.add(anchor)}}

private func teacherAuthorityGapAnchors(gap:String):ArrayList<String>{
    let out=ArrayList<String>()
    for(part in gap.toAsciiLower().split("-")){let value=part.trimAscii();if(value!=""&&value!="g"&&!out.contains(value)){out.add(value)};if(out.size==3){break}}
    out
}

private func teacherAuthorityAnchorPresent(text:String,anchor:String):Bool{
    if(anchor=="bytes"){return text.contains("bytes")||text.contains("byte")||text.contains("uint8")}
    if(anchor=="index"){return text.contains("index")||text.contains("[")}
    if(anchor=="string-constructor"){return text.contains("string(")||text.contains("construct string")||text.contains("string constructor")}
    text.contains(anchor)
}

private func teacherAuthorityAnyAnchor(text:String,anchors:ArrayList<String>):Bool{for(anchor in anchors){if(teacherAuthorityAnchorPresent(text,anchor)){return true}};false}
private func teacherAuthorityAllAnchors(text:String,anchors:ArrayList<String>):Bool{for(anchor in anchors){if(!teacherAuthorityAnchorPresent(text,anchor)){return false}};true}
private func teacherAuthorityAllSourceAnchors(source:String,anchors:ArrayList<String>):Bool{
    let code=teacherAuthorityCodeOnly(source).toAsciiLower()
    for(anchor in anchors){
        if(anchor=="std.convert"){var imported=false;for(line in code.split("\n")){if(line.trimAscii().startsWith("import std.convert")){imported=true;break}};if(!imported){return false}}
        else if(anchor=="std.unicode"){var imported=false;for(line in code.split("\n")){if(line.trimAscii().startsWith("import std.unicode")){imported=true;break}};if(!imported){return false}}
        else if(anchor=="parse"){if(!code.contains(".parse(")){return false}}
        else if(anchor=="islowercase"){if(!code.contains(".islowercase(")){return false}}
        else if(anchor=="isuppercase"){if(!code.contains(".isuppercase(")){return false}}
        else if(anchor=="contains"){if(!code.contains(".contains(")){return false}}
        else if(anchor=="stringbuilder.append"){if(!code.contains("stringbuilder")||!code.contains(".append(")){return false}}
        else if(anchor=="torunearray"){if(!code.contains(".torunearray(")){return false}}
        else if(anchor=="uint8"){if(!code.contains(": uint8")&&!code.contains(":uint8")&&!code.contains("uint8(")){return false}}
        else if(anchor=="rune"){if(!code.contains(": rune")&&!code.contains(":rune")&&!code.contains("array<rune>")&&!code.contains("r'")){return false}}
        else if(anchor=="repeat"){if(!code.contains("repeat:")){return false}}
        else if(anchor=="item:"){if(!code.contains("item:")){return false}}
        else if(anchor=="string-constructor"){if(!code.contains("string(")){return false}}
        else if(anchor=="array<rune>"){if(!code.contains("array<rune>")){return false}}
        else if(anchor=="fromrunearray"){if(!code.contains(".fromrunearray(")){return false}}
        else if(anchor.startsWith("stdx.")||anchor.startsWith("std.")){if(!teacherAuthorityHasImport(source,anchor)){return false}}
        else if(!teacherAuthorityAnchorPresent(code,anchor)){return false}
    };true
}
private func teacherAuthorityCodeOnly(source:String):String{
    let out=ArrayList<Rune>();let runes=source.toRuneArray();var quoted=false;var escaped=false;var i:Int64=0
    while(i<runes.size){let c=runes[i]
        if(quoted){if(escaped){escaped=false}else if(c==r'\\'){escaped=true}else if(c==r'"'){quoted=false};i+=1;continue}
        if(c==r'"'){quoted=true;i+=1;continue}
        if(c==r'/'&&i+1<runes.size&&runes[i+1]==r'/'){while(i<runes.size&&runes[i]!=r'\n'){i+=1};continue}
        out.add(c);i+=1
    };String(out.toArray())
}

private func teacherAuthorityHasImport(source:String,packageName:String):Bool{
    let code=teacherAuthorityCodeOnly(source)
    for(line in code.split("\n")){if(teacherAuthorityImportLineMatches(line,packageName)){return true}}
    false
}

private func teacherAuthorityOnlyImportMentions(source:String,packageName:String):Bool{
    var found=false;let token=packageName.toAsciiLower()
    for(line in source.split("\n")){let lower=line.toAsciiLower();if(lower.contains(token)){if(lower.split(token).size!=2||!teacherAuthorityImportLineMatches(line,packageName)){return false};found=true}}
    found
}

private func teacherAuthorityImportLineMatches(line:String,packageName:String):Bool{
    let trimmed=line.trimAscii();let prefix="import ${packageName}";if(trimmed==prefix){return true}
    if(!trimmed.startsWith(prefix)){return false};let runes=trimmed.toRuneArray();let prefixSize=prefix.toRuneArray().size
    runes.size>prefixSize&&(runes[prefixSize]==r'.'||runes[prefixSize]==r' '||runes[prefixSize]==r'\t')
}

private func teacherAuthorityBoundedFeedback(value:String):String{
    let sanitized=teacherSanitizeEvidence(value);let runes=sanitized.toRuneArray();if(runes.size<=800){sanitized}else{String(runes[..800])+"..."}
}

private func parseTeacherAuthorityGapJsonl(text: String): (Array<TeacherGapRow>, String) {
    let rows = ArrayList<TeacherGapRow>(); let ids = HashSet<String>()
    for (line in text.split("\n")) {
        let raw = line.trimAscii(); if (raw == "") { continue }
        if (raw.toRuneArray().size > 262144) { return ([], "authority_gap_too_large") }
        try {
            let o = JsonValue.fromStr(raw).asObject(); let row = TeacherGapRow()
            if (candidateString(o,"schemaVersion") != "ckb-benchmark-gap-v1") { return ([], "unsupported_gap_schema") }
            row.datasetVersion=candidateString(o,"datasetVersion");row.teacherRunId=candidateString(o,"teacherRunId")
            row.evidenceHash=candidateString(o,"evidenceHash");row.evidence=candidateString(o,"evidence");row.caseId=candidateString(o,"caseId")
            row.benchmark=candidateString(o,"benchmark");row.taskText=candidateString(o,"taskText");row.visibleTestExcerpt=candidateString(o,"visibleTestExcerpt")
            row.compilerOutput=candidateString(o,"compilerOutput");row.missingKnowledge=candidateString(o,"missingKnowledge")
            row.interfaceId=candidateString(o,"interfaceId");row.contentFamily=candidateString(o,"contentFamily");row.updateMechanism=candidateString(o,"updateMechanism")
            row.targetVersion=candidateString(o,"targetVersion");row.citation=candidateString(o,"officialCitation");row.confirmations=candidateInt(o,"knowledgeGapConfirmations",0)
            row.sourceClass=candidateString(o,"sourceClass").toAsciiLower();if(row.sourceClass==""){row.sourceClass="official"};row.failureTaxonomy=candidateString(o,"failureTaxonomy").toAsciiLower()
            if (row.datasetVersion==""||row.evidence==""||row.caseId==""||row.missingKnowledge==""||row.targetVersion=="") { return ([],"gap_contract_invalid") }
            if (row.evidenceHash != "sha256:${teacherStableHash(row.evidence)}") { return ([],"gap_evidence_hash_mismatch") }
            if(row.sourceClass=="official"){
                if(row.confirmations<2||row.failureTaxonomy!="knowledge_gap"){return([],"gap_contract_invalid")}
                if(!row.citation.toAsciiLower().startsWith("https://docs.cangjie-lang.cn/")){return([],"citation_not_allowed")}
            }else if(row.sourceClass=="teacher_empirical"){
                if(row.citation!=""||!teacherEmpiricalFailureTaxonomy(row.failureTaxonomy)){return([],"unverified_teacher_empirical")}
            }else{return([],"source_class_not_allowed")}
            if (ids.contains(row.caseId)) { return ([],"duplicate_gap_case") }; ids.add(row.caseId); rows.add(row)
        } catch (_: Exception) { return ([], "malformed_json") }
    }
    (rows.toArray(), "ok")
}

private func teacherEmpiricalFailureTaxonomy(value:String):Bool{
    ["knowledge_gap","reasoning_error","reasoning_failure","unit_failure","test_failure"].contains(value)
}

private func extractTeacherAtom(options:TeacherCliOptions,row:TeacherGapRow,run:TeacherRunManifest,solutionRoot:String,atomFeedback:String,
    executor:TeacherCommandExecutor):(TeacherAtomSpec,String) {
    if(options.model!="gpt-5.6-sol"){return (emptyTeacherAtomSpec(),"extractor_model_identity_invalid")}
    let solutionHash=teacherDirectoryHash(solutionRoot)
    let allowedEvidence=teacherSanitizeEvidence(row.evidence+"\n"+row.compilerOutput)
    let repair=if(atomFeedback==""){""}else{"\nA previous authority relevance or atom test failed. Correct the proposed knowledge explanation, example, test sources, or expected diagnostic using this sanitized compiler evidence, then return a complete replacement object:\n${atomFeedback}"}
    let exactGapInstruction=if(row.missingKnowledge.toAsciiLower()=="g-logical-or-condition"){
        " For this exact gap, explain that Cangjie requires Bool || Bool inside one complete parenthesized if or while condition. Positive and boundary sources must explicitly declare two Bool operands and use main() without func in a compilable form such as if (left || right) { ... }. The negative source must use the same Bool types and the exact placement if (left) || (right) { ... }, with negativeDiagnostic set to expected '{', found '||'. Do not use Int operands, the nonexistent or keyword, func main, comments, or string labels as substitutes."
    }else if(row.missingKnowledge.toAsciiLower()=="g-control-flow-parentheses"){
        " For this exact gap, explain that Cangjie if and while control-flow expressions require each Bool condition inside parentheses before the brace-delimited block. Positive and boundary sources must use main() without func, declare explicit Bool values, and demonstrate both if (condition) { ... } and while (condition) { ... }. The negative source must declare an explicit Bool and use if condition { ... } without parentheses, with negativeDiagnostic set to expected '(' after 'if'. Do not substitute non-Bool conditions, logical-OR placement errors, comments, or string labels; all three dependency profiles are none."
    }else if(row.missingKnowledge.toAsciiLower()=="g-string-case-rune"){
        " For this exact gap, state that String.toLower() does not exist, String.toAsciiLower() converts ASCII letters only and leaves non-ASCII text unchanged, and Unicode conversion uses import std.unicode.* with Rune.toLowerCase(). The positive source must assign String.toAsciiLower() to an explicitly typed String. The boundary source must use a non-ASCII String and Rune, throw if the toAsciiLower result differs from the original String, import std.unicode.*, and call toLowerCase() on that Rune. The negative source must call toLower() on an explicit String and set negativeDiagnostic to the compiler substring 'toLower' is not a member of struct 'String'. Never use the nonexistent toLowerAscii name, comments, or string labels as evidence; all three dependency profiles are none."
    }else if(row.missingKnowledge.toAsciiLower()=="g-reserved-keyword-match"){
        " For this exact gap, state that match is a keyword and cannot be used as a plain ordinary identifier, but may legally be retained as the raw identifier `match` with backticks; also show the simpler rename isMatch. The positive source must declare and use var isMatch: Bool. The boundary source must declare and use var `match`: Bool with backticks. The negative source must declare and use plain var match: Bool and set negativeDiagnostic to expected identifier or pattern after 'var', found keyword 'match'. Do not claim that match can never be an identifier, and do not use comments or string labels as evidence; all dependency profiles are none."
    }else{""}
    let sourceInstruction=if(row.sourceClass=="teacher_empirical"){
        "Set citation to the empty string and sourceClass to exactly 'teacher_empirical'. State only the reusable rule demonstrated by the independent sources; do not claim an official citation."
    }else{
        "Set citation to exactly '${row.citation}' with no Markdown, label, hash, or appended metadata. Set sourceClass to exactly 'official'."
    }
    let prompt="Extract reusable Cangjie knowledge as one JSON object. Never include the case id, solution code, task answer, hidden tests, or reference text. Required fields: provider=codex, model=${options.model}, knowledgeFamily (K4 enum), concept, explanation, example, citation, sourceClass, positiveSource, negativeSource, boundarySource, negativeDiagnostic, positiveDependencyProfile, negativeDependencyProfile, boundaryDependencyProfile. Dependency profile values must be none or stdx-magic. Use stdx-magic only when a source imports stdx and its cjpm project must declare the bundled stdx binary dependency; for a missing-dependency negative test use none. For an stdx CJPM dependency gap, explanation/example must show an applicable [target.<triple>.bin-dependencies] table with a direct path-option line using the literal ${"$"+"{MAGIC_PATH}"} prefix and ending in /dynamic/stdx; do not invent an stdx = table entry or a placeholder path. For an unnecessary undeclared import gap, explanation/example must say to verify API ownership and remove the unnecessary import instead of adding a dependency; positive and boundary sources must not contain std.text anywhere, including comments or strings, while the negative source mentions std.text only in the legal import line that reproduces the diagnostic.${exactGapInstruction} The three Source fields must each be a complete small Cangjie main source; positive and boundary must compile, negative must fail. ${sourceInstruction} negativeDiagnostic must be a short literal substring emitted by the Cangjie compiler for negativeSource, not an explanatory sentence. Do not place any evidence hash or binding metadata inside user-facing knowledge fields. Bind internally to gap=${row.missingKnowledge}, targetVersion=${row.targetVersion}, sourceEvidenceHash=${row.evidenceHash}, completedRunEvidenceHash=${run.evidenceHash}, solutionContentHash=${solutionHash}. Allowed first-attempt evidence follows:\n${allowedEvidence}${repair}"
    let extractorRoot="${options.root}/runs/${options.runId}/extractor-workspaces/${row.caseId}"
    try { if(!exists(Path(extractorRoot))){Directory.create(Path(extractorRoot),recursive:true)} } catch(_:Exception){return(emptyTeacherAtomSpec(),"extractor_workspace_failed")}
    let schemaPath="${extractorRoot}/response.schema.json";let responsePath="${extractorRoot}/response.json"
    try{_=teacherAtomicWrite(schemaPath,teacherExtractorOutputSchema())}catch(_:Exception){return(emptyTeacherAtomSpec(),"extractor_schema_write_failed")}
    var raw=""
    var transportFailures:Int64=0
    while(true){
        try{if(exists(Path(responsePath))){remove(Path(responsePath))}}catch(_:Exception){}
        let structured=transportFailures<3
        let requestPrompt=if(structured){prompt}else{"${prompt}\nReturn only the JSON object, without Markdown fences or commentary."}
        let args=if(structured){
            ["exec","--model",options.model,"--sandbox","read-only","--skip-git-repo-check","--ephemeral","--ignore-user-config","--ignore-rules","-C",solutionRoot,"--output-schema",schemaPath,"--output-last-message",responsePath,requestPrompt]
        }else{
            ["exec","--model",options.model,"--sandbox","read-only","--skip-git-repo-check","--ephemeral","--ignore-user-config","--ignore-rules","-C",solutionRoot,"--output-last-message",responsePath,requestPrompt]
        }
        let process=executor.execute(TeacherCommandSpec(options.extractor,args,solutionRoot,timeoutMillis:options.timeoutMillis))
        if(process.timedOut||process.exitCode!=0||!exists(Path(responsePath))){transportFailures++;continue}
        try{raw=teacherReadUtf8File(responsePath)}catch(_:Exception){transportFailures++;continue}
        if(raw.trimAscii()==""){transportFailures++;continue};break
    }
    if(raw.toRuneArray().size>262144){return(emptyTeacherAtomSpec(),"extractor_output_too_large")}
    try {
        let o=JsonValue.fromStr(raw.trimAscii()).asObject();let provider=candidateString(o,"provider");let model=candidateString(o,"model")
        if(!teacherExtractorObjectContractValid(o)){return(emptyTeacherAtomSpec(),"extractor_contract_invalid")}
        if(provider!="codex"||model!=options.model){return(emptyTeacherAtomSpec(),"extractor_identity_mismatch")}
        let spec=TeacherAtomSpec(candidateString(o,"knowledgeFamily"),candidateString(o,"concept"),candidateString(o,"explanation"),candidateString(o,"example"),candidateString(o,"citation"),candidateString(o,"sourceClass"),candidateString(o,"positiveSource"),candidateString(o,"negativeSource"),candidateString(o,"boundarySource"),candidateString(o,"negativeDiagnostic"),candidateString(o,"positiveDependencyProfile"),candidateString(o,"negativeDependencyProfile"),candidateString(o,"boundaryDependencyProfile"),"sha256:${teacherStableHash(raw)}",provider,model)
        if(!teacherK4Family(spec.family)||spec.concept==""||spec.explanation==""||spec.example==""||spec.positiveSource==""||spec.negativeSource==""||spec.boundarySource==""||spec.negativeDiagnostic==""){return(emptyTeacherAtomSpec(),"extractor_contract_invalid")}
        if(spec.sourceClass!=row.sourceClass||spec.citation!=row.citation||(row.sourceClass=="official"&&!spec.citation.startsWith("https://docs.cangjie-lang.cn/"))){return(emptyTeacherAtomSpec(),"extractor_source_invalid")}
        if(candidateForbidden(spec.concept+spec.explanation+spec.example+spec.positiveSource+spec.negativeSource+spec.boundarySource)){return(emptyTeacherAtomSpec(),"extractor_contamination")}
        (spec,"ok")
    }catch(_:Exception){(emptyTeacherAtomSpec(),"malformed_extractor_json")}
}

private func teacherExtractorObjectContractValid(o:JsonObject):Bool{
    let fields=o.getFields()
    let names=["provider","model","knowledgeFamily","concept","explanation","example","citation","sourceClass",
        "positiveSource","negativeSource","boundarySource","negativeDiagnostic","positiveDependencyProfile",
        "negativeDependencyProfile","boundaryDependencyProfile"]
    if(fields.size!=names.size){return false}
    for(name in names){
        match(o.get(name)){
            case Some(value)=>try{_=value.asString().getValue()}catch(_:Exception){return false}
            case None=>return false
        }
    }
    let profiles=["none","stdx-magic"]
    profiles.contains(candidateString(o,"positiveDependencyProfile"))&&
        profiles.contains(candidateString(o,"negativeDependencyProfile"))&&
        profiles.contains(candidateString(o,"boundaryDependencyProfile"))
}

private func teacherExtractorOutputSchema():String{
    "{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"provider\",\"model\",\"knowledgeFamily\",\"concept\",\"explanation\",\"example\",\"citation\",\"sourceClass\",\"positiveSource\",\"negativeSource\",\"boundarySource\",\"negativeDiagnostic\",\"positiveDependencyProfile\",\"negativeDependencyProfile\",\"boundaryDependencyProfile\"],\"properties\":{\"provider\":{\"type\":\"string\",\"enum\":[\"codex\"]},\"model\":{\"type\":\"string\",\"enum\":[\"gpt-5.6-sol\"]},\"knowledgeFamily\":{\"type\":\"string\",\"enum\":[\"syntax\",\"standard_library\",\"algorithm_pattern\",\"stdx\",\"toolchain\",\"compiler_diagnostic\",\"version_migration\",\"engineering_practice\"]},\"concept\":{\"type\":\"string\"},\"explanation\":{\"type\":\"string\"},\"example\":{\"type\":\"string\"},\"citation\":{\"type\":\"string\"},\"sourceClass\":{\"type\":\"string\",\"enum\":[\"official\",\"teacher_empirical\"]},\"positiveSource\":{\"type\":\"string\"},\"negativeSource\":{\"type\":\"string\"},\"boundarySource\":{\"type\":\"string\"},\"negativeDiagnostic\":{\"type\":\"string\"},\"positiveDependencyProfile\":{\"type\":\"string\",\"enum\":[\"none\",\"stdx-magic\"]},\"negativeDependencyProfile\":{\"type\":\"string\",\"enum\":[\"none\",\"stdx-magic\"]},\"boundaryDependencyProfile\":{\"type\":\"string\",\"enum\":[\"none\",\"stdx-magic\"]}}}"
}

private func emptyTeacherAtomSpec():TeacherAtomSpec{TeacherAtomSpec("","","","","","","","","","","","","","","","")}
private func teacherK4Family(v:String):Bool{["syntax","standard_library","algorithm_pattern","stdx","toolchain","compiler_diagnostic","version_migration","engineering_practice"].contains(v)}

private func teacherExecutableAtomBundle(identity: String, row: TeacherGapRow, spec: TeacherAtomSpec,root:String,run:TeacherRunManifest): String {
    let tests = "[{\"category\":\"positive\",\"operation\":\"contains\",\"input\":\"atom\",\"needle\":\"atom\",\"expected\":\"true\",\"source\":\"${candidateEscape(spec.positiveSource)}\",\"dependencyProfile\":\"${candidateEscape(spec.positiveDependencyProfile)}\",\"expectedMode\":\"pass\"},{\"category\":\"negative\",\"operation\":\"contains\",\"input\":\"safe\",\"needle\":\"forbidden\",\"expected\":\"false\",\"source\":\"${candidateEscape(spec.negativeSource)}\",\"dependencyProfile\":\"${candidateEscape(spec.negativeDependencyProfile)}\",\"expectedMode\":\"compile_reject\",\"expectedDiagnostic\":\"${candidateEscape(spec.negativeDiagnostic)}\"},{\"category\":\"boundary\",\"operation\":\"rune_count\",\"input\":\"😀\",\"expected\":\"1\",\"source\":\"${candidateEscape(spec.boundarySource)}\",\"dependencyProfile\":\"${candidateEscape(spec.boundaryDependencyProfile)}\",\"expectedMode\":\"pass\"}]"
    let canonical = candidatePart(identity)+candidatePart(spec.sourceClass)+candidatePart(spec.citation.toAsciiLower())+candidatePart(row.targetVersion)+candidatePart(spec.explanation)+candidatePart("true")+candidatePart(tests)
    let hash = "sha256:${teacherStableHash(canonical)}"
    let provenance=if(spec.sourceClass=="teacher_empirical"){",\"teacherEmpiricalProvenance\":${teacherEmpiricalProvenance(row,root,run)}"}else{""}
    "{\"atomId\":\"${candidateEscape(identity)}\",\"knowledgeFamily\":\"${candidateEscape(spec.family)}\",\"sourceClass\":\"${candidateEscape(spec.sourceClass)}\",\"citation\":\"${candidateEscape(spec.citation)}\",\"targetVersion\":\"${candidateEscape(row.targetVersion)}\",\"candidateHash\":\"${hash}\",\"knowledgeText\":\"${candidateEscape(spec.explanation)}\",\"example\":\"${candidateEscape(spec.example)}\",\"extractor\":{\"provider\":\"${spec.provider}\",\"model\":\"${spec.model}\",\"exitCode\":0,\"transcriptHash\":\"${spec.transcriptHash}\"},\"purificationPassed\":true,\"tests\":${tests}${provenance}}"
}

private func teacherEmpiricalProvenance(row:TeacherGapRow,root:String,run:TeacherRunManifest):String{
    let binding=teacherReadUtf8File("${root}/runs/${run.runId}/evidence/${run.caseId}/solution.binding")
    "{\"originalFailureEvidenceHash\":\"${candidateEscape(row.evidenceHash)}\",\"completedRunManifestHash\":\"sha256:${teacherStableHash(renderTeacherRunManifest(run))}\",\"solutionBindingHash\":\"sha256:${teacherStableHash(binding)}\"}"
}

private func teacherEmpiricalProvenanceValid(object:JsonObject,row:TeacherGapRow,root:String,run:TeacherRunManifest):Bool{
    if(row.sourceClass!="teacher_empirical"){return true}
    try{object.get("teacherEmpiricalProvenance").getOrThrow().toString()==teacherEmpiricalProvenance(row,root,run)}catch(_:Exception){false}
}

public func executeTeacherAtomTestBundle(raw:String,workspaceRoot:String,
    executor!:TeacherCommandExecutor=NativeTeacherCommandExecutor(),timeoutMillis!:Int64=600000):TeacherAtomExecutionResult {
    let out=TeacherAtomExecutionResult()
    try {
        let tests=JsonValue.fromStr(raw).asObject().get("tests").getOrThrow().asArray().getItems();let categories=HashSet<String>();var evidence="";var passed:Int64=0
        for(v in tests){let t=v.asObject();let category=candidateString(t,"category");categories.add(category);let root="${workspaceRoot}/${category}";if(exists(Path(root))){remove(Path(root),recursive:true)};Directory.create(Path("${root}/src"),recursive:true)
            let project=teacherAtomProjectToml(category,candidateString(t,"dependencyProfile"));if(project[1]!=""){out.diagnostic=project[1];return out}
            _=teacherAtomicWrite("${root}/cjpm.toml",project[0])
            let source=candidateString(t,"source");if(source.trimAscii().startsWith("package ")){out.diagnostic="atom_source_package_forbidden";return out}
            _=teacherAtomicWrite("${root}/src/main.cj","package teacher_atom_${category}\n\n${source}\n");var categoryOk=true;var categoryEvidence=""
            for(args in [["clean"],["build","-i"],["test","-j","1"]]){let r=executor.execute(TeacherCommandSpec("cjpm",args,root,timeoutMillis:timeoutMillis));categoryEvidence+="${args[0]}:${r.exitCode}:sha256:${teacherStableHash(r.output)}|";if(r.timedOut){out.diagnostic="atom_test_timeout";return out};if(category=="negative"&&args[0]=="build"){categoryOk=r.exitCode!=0&&r.output.contains(candidateString(t,"expectedDiagnostic"));if(!categoryOk){out.feedback=teacherSanitizeEvidence("category=negative expectedDiagnostic=${candidateString(t,"expectedDiagnostic")} actualCompilerOutput=${r.output.replace(root,"[atom-workspace]")}")};break};if(r.exitCode!=0){categoryOk=false;out.feedback=teacherSanitizeEvidence("category=${category} command=${args[0]} expected=success actualCompilerOutput=${r.output.replace(root,"[atom-workspace]")}");break}}
            if(categoryOk){passed++};evidence+="${category}:${categoryEvidence}passed=${categoryOk};"
        }
        if(categories.contains("positive")&&categories.contains("negative")&&categories.contains("boundary")&&passed==3){out.ok=true;out.diagnostic="ok";out.evidenceJson="{\"total\":3,\"passed\":3,\"failed\":0,\"status\":\"passed\",\"commandEvidence\":\"${candidateEscape(evidence)}\",\"commandEvidenceHash\":\"sha256:${teacherStableHash(evidence)}\"}"}else{out.diagnostic="atom_test_failed";if(out.feedback==""){out.feedback="atom categories incomplete or failed"}}
    }catch(_:Exception){out.diagnostic="malformed_atom_test_bundle"};out
}

private func teacherAtomProjectToml(category:String,profile:String):(String,String){
    let base="[package]\n  cjc-version = \"1.0.0\"\n  name = \"teacher_atom_${category}\"\n  version = \"1.0.0\"\n  output-type = \"executable\"\n"
    if(profile==""||profile=="none"){return(base,"")}
    if(profile!="stdx-magic"){return("","atom_dependency_profile_forbidden")}
    let magic="$"+"{MAGIC_PATH}"
    let targets="\n[target.x86_64-unknown-linux-gnu.bin-dependencies]\n  path-option = [\"${magic}/libs/cangjie-stdx-linux-x64-1.0.0.1/linux_x86_64_llvm/dynamic/stdx\"]\n\n[target.x86_64-unknown-windows-gnu.bin-dependencies]\n  path-option = [\"${magic}/libs/cangjie-stdx-windows-x64-1.0.0.1/windows_x86_64_llvm/dynamic/stdx\"]\n\n[target.x86_64-w64-mingw32.bin-dependencies]\n  path-option = [\"${magic}/libs/cangjie-stdx-windows-x64-1.0.0.1/windows_x86_64_llvm/dynamic/stdx\"]\n\n[target.aarch64-unknown-linux-gnu.bin-dependencies]\n  path-option = [\"${magic}/libs/cangjie-stdx-linux-aarch64-1.0.0.1/linux_aarch64_llvm/dynamic/stdx\"]\n\n[target.aarch64-apple-darwin.bin-dependencies]\n  path-option = [\"${magic}/libs/cangjie-stdx-mac-aarch64-1.0.0.1/darwin_aarch64_llvm/dynamic/stdx\"]\n"
    (base+targets,"")
}

private func recordTeacherAtomTestExecution(raw:String,evidence:String):String {
    let runes=raw.toRuneArray()
    String(runes[..runes.size-1])+",\"execution\":${evidence}}"
}

private func renderTeacherCkbGap(row: TeacherGapRow, runId: String, bundle: String,transcriptHash:String): String {
    let canonicalized=canonicalizeTeacherCkbKnowledgeAtomBundle(bundle.toArray())
    if(canonicalized[1]!="ok"){throw IllegalArgumentException(canonicalized[1])}
    let canonicalBundle=canonicalized[0]
    let candidatePath="candidate-knowledge/ckb-benchmark-gap.jsonl";let evidence="${row.evidence}|teacherAtomHash=sha256:${teacherStableHash(canonicalBundle)}|extractorTranscriptHash=${transcriptHash}${teacherEmpiricalEvidenceSuffix(canonicalBundle,row.sourceClass)}";let evidenceHash="sha256:${teacherStableHash(evidence)}"
    let hash=teacherCkbGapCandidateHash(row,runId,canonicalBundle,evidenceHash,evidence)
    let sourceField=if(row.sourceClass=="teacher_empirical"){",\"sourceClass\":\"teacher_empirical\""}else{""}
    "{\"schemaVersion\":\"ckb-benchmark-gap-v1\",\"datasetVersion\":\"${candidateEscape(row.datasetVersion)}\",\"teacherRunId\":\"${candidateEscape(runId)}\",\"evidenceHash\":\"${evidenceHash}\",\"evidence\":\"${candidateEscape(evidence)}\",\"candidateHash\":\"${hash}\",\"candidatePath\":\"${candidatePath}\",\"revision\":1,\"attempt\":1,\"failureTaxonomy\":\"${candidateEscape(row.failureTaxonomy)}\",\"knowledgeGapConfirmations\":${row.confirmations}${sourceField},\"caseId\":\"${candidateEscape(row.caseId)}\",\"benchmark\":\"${candidateEscape(row.benchmark)}\",\"taskText\":\"${candidateEscape(row.taskText)}\",\"visibleTestExcerpt\":\"${candidateEscape(row.visibleTestExcerpt)}\",\"compilerOutput\":\"${candidateEscape(row.compilerOutput)}\",\"missingKnowledge\":\"${candidateEscape(row.missingKnowledge)}\",\"interfaceId\":\"${candidateEscape(row.interfaceId)}\",\"contentFamily\":\"${candidateEscape(row.contentFamily)}\",\"updateMechanism\":\"${candidateEscape(row.updateMechanism)}\",\"targetVersion\":\"${candidateEscape(row.targetVersion)}\",\"officialCitation\":\"${candidateEscape(row.citation)}\",\"knowledgeAtomTestBundle\":${canonicalBundle},\"knowledgeAtomCandidate\":true}"
}

private func teacherEmpiricalEvidenceSuffix(bundle:String,sourceClass:String):String{
    if(sourceClass!="teacher_empirical"){return ""}
    let o=JsonValue.fromStr(bundle).asObject();let provenance=o.get("teacherEmpiricalProvenance").getOrThrow().asObject();let execution=o.get("execution").getOrThrow().asObject()
    "|originalFailureEvidenceHash=${candidateString(provenance,"originalFailureEvidenceHash")}|completedRunManifestHash=${candidateString(provenance,"completedRunManifestHash")}|solutionBindingHash=${candidateString(provenance,"solutionBindingHash")}|independentExperimentEvidenceHash=${candidateString(execution,"commandEvidenceHash")}"
}

private func teacherCkbGapCandidateHash(row:TeacherGapRow,runId:String,bundle:String,evidenceHash:String,evidence:String):String{
    let identity="${row.benchmark.trimAscii().toAsciiLower()}:${row.datasetVersion.toAsciiLower()}:${row.caseId.toAsciiLower()}:${row.missingKnowledge.toAsciiUpper()}:${row.targetVersion.toAsciiLower()}"
    let sourcePart=if(row.sourceClass=="teacher_empirical"){candidatePart(row.sourceClass)}else{""}
    let canonical=candidatePart(identity)+candidatePart(row.taskText)+candidatePart(row.visibleTestExcerpt)+candidatePart(row.compilerOutput)+candidatePart(row.missingKnowledge.toAsciiUpper())+candidatePart(row.interfaceId)+candidatePart(row.contentFamily)+candidatePart(row.updateMechanism)+candidatePart(row.targetVersion)+candidatePart(row.citation)+candidatePart(bundle)+candidatePart("true")+candidatePart(runId)+candidatePart(evidenceHash)+candidatePart(evidence)+candidatePart("candidate-knowledge/ckb-benchmark-gap.jsonl")+candidatePart("1")+candidatePart("1")+candidatePart(row.failureTaxonomy)+candidatePart("${row.confirmations}")+sourcePart
    "sha256:${teacherStableHash(canonical)}"
}

public func canonicalizeTeacherCkbKnowledgeAtomBundle(raw:Array<UInt8>):(String,String){
    if(raw.size>262144){return("","atom_test_bundle_too_large")}
    let text=try{String.fromUtf8(raw)}catch(_:Exception){return("","invalid_response_encoding")}
    try{
        let canonical=JsonValue.fromStr(text.trimAscii()).asObject().toString()
        if(canonical.toRuneArray().size>262144){return("","atom_test_bundle_too_large")}
        if(teacherCkbBundleForbidden(canonical)){return("","atom_content_contamination")}
        (canonical,"ok")
    }catch(_:Exception){("","malformed_atom_test_bundle")}
}

private func teacherCkbBundleForbidden(raw:String):Bool{
    let value=raw.toAsciiLower()
    candidateForbidden(raw)||value.contains("/users/")||value.contains("/private/")||value.contains("authorization:")||
        value.contains("bearer ")||value.contains("api_key")||value.contains("token=")||value.contains("password")
}

private func teacherPrivateArtifacts(root:String):Array<String>{try{[teacherReadUtf8File("${root}/src/solution.cj")]}catch(_:Exception){[]}}
private func candidateForbidden(raw:String):Bool{let v=raw.toAsciiLower();v.contains("cj-humaneval-")||v.contains("canonical_solution")||v.contains("hidden_test")||v.contains("hidden assertion")||v.contains("teacher-solutions")||v.contains("/reference/")}
private func candidateSafeId(v:String):Bool{v!=""&&!v.contains("/")&&!v.contains("\\")&&!v.contains("..")&&v.toRuneArray().size<=128}
private func candidatePart(v:String):String{"${v.toArray().size}:${v}"}
private func teacherEscapeField(v:String):String{v.replace("%","%25").replace("\t","%09").replace("\n","%0A")}
private func candidateEscape(v:String):String{v.replace("\\","\\\\").replace("\"","\\\"").replace("\n","\\n").replace("\r","\\r").replace("\t","\\t")}
private func candidateString(o:JsonObject,k:String):String{match(o.get(k)){case Some(v)=>v.asString().getValue().trimAscii();case None=>""}}
private func candidateInt(o:JsonObject,k:String,f:Int64):Int64{match(o.get(k)){case Some(v)=>try{Int64.parse(v.toString())}catch(_:Exception){f};case None=>f}}
private func candidateBool(o:JsonObject,k:String):Bool{match(o.get(k)){case Some(v)=>try{v.asBool().getValue()}catch(_:Exception){false};case None=>false}}
private func candidateHas(o:JsonObject,k:String):Bool{match(o.get(k)){case Some(_)=>true;case None=>false}}
