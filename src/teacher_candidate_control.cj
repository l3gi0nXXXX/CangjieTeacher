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
    var targetVersion = ""; var citation = ""; var confirmations: Int64 = 0
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
                let currentBundle=teacherExecutableAtomBundle(currentIdentity,row,currentSpec)
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
    let quoted=teacherAuthorityQuotedAnchors(compilerOutput)
    let extracted=ArrayList<String>()
    for(anchor in quoted){if(teacherAuthorityStrongAnchor(anchor)&&!extracted.contains(anchor.toAsciiLower())){extracted.add(anchor.toAsciiLower())}}
    let strong=ArrayList<String>()
    let primary=ArrayList<String>()
    if(gap.contains("array-repeat")){
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
    let strongCoverage=strong.isEmpty()||teacherAuthorityAllAnchors(narrative,strong)&&teacherAuthorityAllAnchors(narrative,primary)&&teacherAuthorityAllSourceAnchors(positiveSource,strong)&&
        teacherAuthorityAllSourceAnchors(boundarySource,strong)&&teacherAuthorityAllSourceAnchors(negativeSource,primary)
    if(narrativeHits>=minimum&&sourceHits>=minimum&&eachSource&&strongCoverage){
        if(stdxProjectAware&&(!(narrative.contains("cjpm.toml")&&narrative.contains("bin-dependencies")&&narrative.contains("path-option"))||
            positiveDependencyProfile!="stdx-magic"||negativeDependencyProfile!="none"||boundaryDependencyProfile!="stdx-magic")){
            out.feedback=teacherAuthorityBoundedFeedback("Stdx dependency knowledge must explain cjpm.toml, target bin-dependencies, and path-option. Its positive and boundary atom tests must use dependency profile stdx-magic; its missing-dependency negative atom test must use profile none.")
            return out
        }
        out.ok=true;out.diagnostic="ok";return out
    }
    var names="";for(i in 0..required.size){if(i>0){names+=","};names+=required[i]}
    out.feedback=teacherAuthorityBoundedFeedback("Authority relevance failed. Required public failure anchors and prerequisites: ${names}. The explanation and example, plus positive and boundary sources, must demonstrate every listed item. The negative source must demonstrate the primary public failure anchor but may intentionally omit a prerequisite to prove the failure. Do not satisfy this check with comments, substitute a generic type fact, or include private paths, secrets, solutions, hidden tests, or references.")
    out
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
        else if(anchor=="uint8"){if(!code.contains(": uint8")&&!code.contains("uint8(")){return false}}
        else if(anchor=="rune"){if(!code.contains(": rune")&&!code.contains("array<rune>")&&!code.contains("r'")){return false}}
        else if(anchor=="repeat"){if(!code.contains("repeat:")){return false}}
        else if(anchor=="item:"){if(!code.contains("item:")){return false}}
        else if(anchor=="string-constructor"){if(!code.contains("string(")){return false}}
        else if(anchor=="array<rune>"){if(!code.contains("array<rune>")){return false}}
        else if(anchor=="fromrunearray"){if(!code.contains(".fromrunearray(")){return false}}
        else if(anchor.startsWith("stdx.")){var imported=false;for(line in code.split("\n")){if(line.trimAscii().startsWith("import ${anchor}")){imported=true;break}};if(!imported){return false}}
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
            if (row.datasetVersion==""||row.evidence==""||row.caseId==""||row.missingKnowledge==""||row.targetVersion==""||row.confirmations<2||candidateString(o,"failureTaxonomy")!="knowledge_gap") { return ([],"gap_contract_invalid") }
            if (row.evidenceHash != "sha256:${teacherStableHash(row.evidence)}") { return ([],"gap_evidence_hash_mismatch") }
            if (!row.citation.toAsciiLower().startsWith("https://docs.cangjie-lang.cn/")) { return ([],"citation_not_allowed") }
            if (ids.contains(row.caseId)) { return ([],"duplicate_gap_case") }; ids.add(row.caseId); rows.add(row)
        } catch (_: Exception) { return ([], "malformed_json") }
    }
    (rows.toArray(), "ok")
}

private func extractTeacherAtom(options:TeacherCliOptions,row:TeacherGapRow,run:TeacherRunManifest,solutionRoot:String,atomFeedback:String,
    executor:TeacherCommandExecutor):(TeacherAtomSpec,String) {
    if(options.model!="gpt-5.6-sol"){return (emptyTeacherAtomSpec(),"extractor_model_identity_invalid")}
    let solutionHash=teacherDirectoryHash(solutionRoot)
    let allowedEvidence=teacherSanitizeEvidence(row.evidence+"\n"+row.compilerOutput)
    let repair=if(atomFeedback==""){""}else{"\nA previous authority relevance or atom test failed. Correct the proposed knowledge explanation, example, test sources, or expected diagnostic using this sanitized compiler evidence, then return a complete replacement object:\n${atomFeedback}"}
    let prompt="Extract reusable Cangjie knowledge as one JSON object. Never include the case id, solution code, task answer, hidden tests, or reference text. Required fields: provider=codex, model=${options.model}, knowledgeFamily (K4 enum), concept, explanation, example, citation, sourceClass, positiveSource, negativeSource, boundarySource, negativeDiagnostic, positiveDependencyProfile, negativeDependencyProfile, boundaryDependencyProfile. Dependency profile values must be none or stdx-magic. Use stdx-magic only when a source imports stdx and its cjpm project must declare the bundled stdx binary dependency; for a missing-dependency negative test use none. The three Source fields must each be a complete small Cangjie main source; positive and boundary must compile, negative must fail. Set citation to exactly '${row.citation}' with no Markdown, label, hash, or appended metadata. Set sourceClass to exactly 'official'. negativeDiagnostic must be a short literal substring emitted by the Cangjie compiler for negativeSource, not an explanatory sentence. Do not place any evidence hash or binding metadata inside user-facing knowledge fields. Bind internally to gap=${row.missingKnowledge}, targetVersion=${row.targetVersion}, sourceEvidenceHash=${row.evidenceHash}, completedRunEvidenceHash=${run.evidenceHash}, solutionContentHash=${solutionHash}. Allowed first-attempt evidence follows:\n${allowedEvidence}${repair}"
    let extractorRoot="${options.root}/runs/${options.runId}/extractor-workspaces/${row.caseId}"
    try { if(!exists(Path(extractorRoot))){Directory.create(Path(extractorRoot),recursive:true)} } catch(_:Exception){return(emptyTeacherAtomSpec(),"extractor_workspace_failed")}
    let schemaPath="${extractorRoot}/response.schema.json";let responsePath="${extractorRoot}/response.json"
    try{_=teacherAtomicWrite(schemaPath,teacherExtractorOutputSchema())}catch(_:Exception){return(emptyTeacherAtomSpec(),"extractor_schema_write_failed")}
    var raw=""
    while(true){
        try{if(exists(Path(responsePath))){remove(Path(responsePath))}}catch(_:Exception){}
        let process=executor.execute(TeacherCommandSpec(options.extractor,["exec","--model",options.model,"--sandbox","read-only","--skip-git-repo-check","--ephemeral","--ignore-user-config","--ignore-rules","-C",solutionRoot,"--output-schema",schemaPath,"--output-last-message",responsePath,prompt],solutionRoot,timeoutMillis:options.timeoutMillis))
        if(process.timedOut||process.exitCode!=0||!exists(Path(responsePath))){continue}
        try{raw=teacherReadUtf8File(responsePath)}catch(_:Exception){continue}
        if(raw.trimAscii()==""){continue};break
    }
    if(raw.toRuneArray().size>262144){return(emptyTeacherAtomSpec(),"extractor_output_too_large")}
    try {
        let o=JsonValue.fromStr(raw.trimAscii()).asObject();let provider=candidateString(o,"provider");let model=candidateString(o,"model")
        if(provider!="codex"||model!=options.model){return(emptyTeacherAtomSpec(),"extractor_identity_mismatch")}
        let spec=TeacherAtomSpec(candidateString(o,"knowledgeFamily"),candidateString(o,"concept"),candidateString(o,"explanation"),candidateString(o,"example"),candidateString(o,"citation"),candidateString(o,"sourceClass"),candidateString(o,"positiveSource"),candidateString(o,"negativeSource"),candidateString(o,"boundarySource"),candidateString(o,"negativeDiagnostic"),candidateString(o,"positiveDependencyProfile"),candidateString(o,"negativeDependencyProfile"),candidateString(o,"boundaryDependencyProfile"),"sha256:${teacherStableHash(raw)}",provider,model)
        if(!teacherK4Family(spec.family)||spec.concept==""||spec.explanation==""||spec.example==""||spec.positiveSource==""||spec.negativeSource==""||spec.boundarySource==""||spec.negativeDiagnostic==""){return(emptyTeacherAtomSpec(),"extractor_contract_invalid")}
        if(spec.sourceClass!="official"||spec.citation!=row.citation||!spec.citation.startsWith("https://docs.cangjie-lang.cn/")){return(emptyTeacherAtomSpec(),"extractor_source_invalid")}
        if(candidateForbidden(spec.concept+spec.explanation+spec.example+spec.positiveSource+spec.negativeSource+spec.boundarySource)){return(emptyTeacherAtomSpec(),"extractor_contamination")}
        (spec,"ok")
    }catch(_:Exception){(emptyTeacherAtomSpec(),"malformed_extractor_json")}
}

private func teacherExtractorOutputSchema():String{
    "{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"provider\",\"model\",\"knowledgeFamily\",\"concept\",\"explanation\",\"example\",\"citation\",\"sourceClass\",\"positiveSource\",\"negativeSource\",\"boundarySource\",\"negativeDiagnostic\",\"positiveDependencyProfile\",\"negativeDependencyProfile\",\"boundaryDependencyProfile\"],\"properties\":{\"provider\":{\"type\":\"string\",\"enum\":[\"codex\"]},\"model\":{\"type\":\"string\",\"enum\":[\"gpt-5.6-sol\"]},\"knowledgeFamily\":{\"type\":\"string\",\"enum\":[\"syntax\",\"standard_library\",\"stdx\",\"toolchain\",\"compiler_diagnostic\",\"version_migration\",\"engineering_practice\"]},\"concept\":{\"type\":\"string\"},\"explanation\":{\"type\":\"string\"},\"example\":{\"type\":\"string\"},\"citation\":{\"type\":\"string\"},\"sourceClass\":{\"type\":\"string\",\"enum\":[\"official\"]},\"positiveSource\":{\"type\":\"string\"},\"negativeSource\":{\"type\":\"string\"},\"boundarySource\":{\"type\":\"string\"},\"negativeDiagnostic\":{\"type\":\"string\"},\"positiveDependencyProfile\":{\"type\":\"string\",\"enum\":[\"none\",\"stdx-magic\"]},\"negativeDependencyProfile\":{\"type\":\"string\",\"enum\":[\"none\",\"stdx-magic\"]},\"boundaryDependencyProfile\":{\"type\":\"string\",\"enum\":[\"none\",\"stdx-magic\"]}}}"
}

private func emptyTeacherAtomSpec():TeacherAtomSpec{TeacherAtomSpec("","","","","","","","","","","","","","","","")}
private func teacherK4Family(v:String):Bool{["syntax","standard_library","stdx","toolchain","compiler_diagnostic","version_migration","engineering_practice"].contains(v)}

private func teacherExecutableAtomBundle(identity: String, row: TeacherGapRow, spec: TeacherAtomSpec): String {
    let tests = "[{\"category\":\"positive\",\"operation\":\"contains\",\"input\":\"atom\",\"needle\":\"atom\",\"expected\":\"true\",\"source\":\"${candidateEscape(spec.positiveSource)}\",\"dependencyProfile\":\"${candidateEscape(spec.positiveDependencyProfile)}\",\"expectedMode\":\"pass\"},{\"category\":\"negative\",\"operation\":\"contains\",\"input\":\"safe\",\"needle\":\"forbidden\",\"expected\":\"false\",\"source\":\"${candidateEscape(spec.negativeSource)}\",\"dependencyProfile\":\"${candidateEscape(spec.negativeDependencyProfile)}\",\"expectedMode\":\"compile_reject\",\"expectedDiagnostic\":\"${candidateEscape(spec.negativeDiagnostic)}\"},{\"category\":\"boundary\",\"operation\":\"rune_count\",\"input\":\"😀\",\"expected\":\"1\",\"source\":\"${candidateEscape(spec.boundarySource)}\",\"dependencyProfile\":\"${candidateEscape(spec.boundaryDependencyProfile)}\",\"expectedMode\":\"pass\"}]"
    let canonical = candidatePart(identity)+candidatePart(spec.sourceClass)+candidatePart(spec.citation.toAsciiLower())+candidatePart(row.targetVersion)+candidatePart(spec.explanation)+candidatePart("true")+candidatePart(tests)
    let hash = "sha256:${teacherStableHash(canonical)}"
    "{\"atomId\":\"${candidateEscape(identity)}\",\"knowledgeFamily\":\"${candidateEscape(spec.family)}\",\"sourceClass\":\"${candidateEscape(spec.sourceClass)}\",\"citation\":\"${candidateEscape(spec.citation)}\",\"targetVersion\":\"${candidateEscape(row.targetVersion)}\",\"candidateHash\":\"${hash}\",\"knowledgeText\":\"${candidateEscape(spec.explanation)}\",\"example\":\"${candidateEscape(spec.example)}\",\"extractor\":{\"provider\":\"${spec.provider}\",\"model\":\"${spec.model}\",\"exitCode\":0,\"transcriptHash\":\"${spec.transcriptHash}\"},\"purificationPassed\":true,\"tests\":${tests}}"
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
    let candidatePath="candidate-knowledge/ckb-benchmark-gap.jsonl";let evidence="${row.evidence}|teacherAtomHash=sha256:${teacherStableHash(bundle)}|extractorTranscriptHash=${transcriptHash}";let evidenceHash="sha256:${teacherStableHash(evidence)}"
    let identity="${row.benchmark.trimAscii().toAsciiLower()}:${row.datasetVersion.toAsciiLower()}:${row.caseId.toAsciiLower()}:${row.missingKnowledge.toAsciiUpper()}:${row.targetVersion.toAsciiLower()}"
    let canonical=candidatePart(identity)+candidatePart(row.taskText)+candidatePart(row.visibleTestExcerpt)+candidatePart(row.compilerOutput)+candidatePart(row.missingKnowledge.toAsciiUpper())+candidatePart(row.interfaceId)+candidatePart(row.contentFamily)+candidatePart(row.updateMechanism)+candidatePart(row.targetVersion)+candidatePart(row.citation)+candidatePart(bundle)+candidatePart("true")+candidatePart(runId)+candidatePart(evidenceHash)+candidatePart(evidence)+candidatePart(candidatePath)+candidatePart("1")+candidatePart("1")+candidatePart("knowledge_gap")+candidatePart("2")
    let hash="sha256:${teacherStableHash(canonical)}"
    "{\"schemaVersion\":\"ckb-benchmark-gap-v1\",\"datasetVersion\":\"${candidateEscape(row.datasetVersion)}\",\"teacherRunId\":\"${candidateEscape(runId)}\",\"evidenceHash\":\"${evidenceHash}\",\"evidence\":\"${candidateEscape(evidence)}\",\"candidateHash\":\"${hash}\",\"candidatePath\":\"${candidatePath}\",\"revision\":1,\"attempt\":1,\"failureTaxonomy\":\"knowledge_gap\",\"knowledgeGapConfirmations\":2,\"caseId\":\"${candidateEscape(row.caseId)}\",\"benchmark\":\"${candidateEscape(row.benchmark)}\",\"taskText\":\"${candidateEscape(row.taskText)}\",\"visibleTestExcerpt\":\"${candidateEscape(row.visibleTestExcerpt)}\",\"compilerOutput\":\"${candidateEscape(row.compilerOutput)}\",\"missingKnowledge\":\"${candidateEscape(row.missingKnowledge)}\",\"interfaceId\":\"${candidateEscape(row.interfaceId)}\",\"contentFamily\":\"${candidateEscape(row.contentFamily)}\",\"updateMechanism\":\"${candidateEscape(row.updateMechanism)}\",\"targetVersion\":\"${candidateEscape(row.targetVersion)}\",\"officialCitation\":\"${candidateEscape(row.citation)}\",\"knowledgeAtomTestBundle\":${bundle},\"knowledgeAtomCandidate\":true}"
}

private func teacherPrivateArtifacts(root:String):Array<String>{try{[teacherReadUtf8File("${root}/src/solution.cj")]}catch(_:Exception){[]}}
private func candidateForbidden(raw:String):Bool{let v=raw.toAsciiLower();v.contains("cj-humaneval-")||v.contains("canonical_solution")||v.contains("hidden_test")||v.contains("hidden assertion")||v.contains("teacher-solutions")||v.contains("/reference/")}
private func candidateSafeId(v:String):Bool{v!=""&&!v.contains("/")&&!v.contains("\\")&&!v.contains("..")&&v.toRuneArray().size<=128}
private func candidatePart(v:String):String{"${v.toArray().size}:${v}"}
private func teacherEscapeField(v:String):String{v.replace("%","%25").replace("\t","%09").replace("\n","%0A")}
private func candidateEscape(v:String):String{v.replace("\\","\\\\").replace("\"","\\\"").replace("\n","\\n").replace("\r","\\r").replace("\t","\\t")}
private func candidateString(o:JsonObject,k:String):String{match(o.get(k)){case Some(v)=>v.asString().getValue().trimAscii();case None=>""}}
private func candidateInt(o:JsonObject,k:String,f:Int64):Int64{match(o.get(k)){case Some(v)=>try{Int64.parse(v.toString())}catch(_:Exception){f};case None=>f}}
