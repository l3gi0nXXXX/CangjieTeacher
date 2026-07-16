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
    let transcriptHash: String; let provider: String; let model: String
    init(family: String, concept: String, explanation: String, example: String, citation: String, sourceClass: String,
        positiveSource: String, negativeSource: String, boundarySource: String, negativeDiagnostic: String,
        transcriptHash: String, provider: String, model: String) {
        this.family = family; this.concept = concept; this.explanation = explanation; this.example = example
        this.citation=citation;this.sourceClass=sourceClass;this.positiveSource=positiveSource;this.negativeSource=negativeSource
        this.boundarySource=boundarySource;this.negativeDiagnostic=negativeDiagnostic;this.transcriptHash=transcriptHash
        this.provider=provider;this.model=model
    }
}

public class TeacherAtomExecutionResult {
    public var ok=false;public var diagnostic="atom_test_failed";public var evidenceJson="";public var feedback="";public init(){}
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
    try {
        if (options.root == "" || options.manifest == "" || options.checksum == "" || options.authorityGap == "" || options.runId == "" || options.outputRoot == "") {
            result.diagnostic = "missing_required_cli_option"; return result
        }
        if (!candidateSafeId(options.runId)) { result.diagnostic = "run_id_invalid"; return result }
        if (!validateTeacherPathBoundary(options.root, options.outputRoot) || options.outputRoot.contains("..")) {
            result.diagnostic = "output_path_forbidden"; return result
        }
        let manifest = loadTeacherDatasetManifestFile(options.manifest, options.checksum)
        let cases = HashMap<String, TeacherCaseManifest>()
        for (item in manifest.cases) { cases.add(item.caseId, item) }
        let completed = loadCompletedTeacherRuns("${options.root}/runs/${options.runId}/completed.manifest")
        let runs = HashMap<String, TeacherRunManifest>()
        for (run in completed) {
            if (runs.contains(run.caseId)) { result.diagnostic = "duplicate_complete_run"; return result }
            if (run.runId == options.runId && run.status == "complete" && run.attempt == 1 && run.exitCode == 0) { runs.add(run.caseId, run) }
        }
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
                let extraction=extractTeacherAtom(options,row,run,solutionRoot,atomFeedback,extractorExecutor)
                if(extraction[1]!="ok"){result.diagnostic=extraction[1];return result};let currentSpec=extraction[0]
                let observation=deriveKnowledgeObservation(caseValue,currentSpec.family,currentSpec.concept,row.targetVersion,currentSpec.explanation,currentSpec.citation,currentSpec.sourceClass,row.evidence+currentSpec.transcriptHash)
                if(!validateObservationNoSolutionLeak(observation)){result.diagnostic="observation_leakage";return result}
                let normalized=normalizeObservation(observation);let currentIdentity=canonicalKnowledgeIdentity(normalized)
                match(identities.get(currentIdentity)){case Some(existing)=>if(mergeKnowledgeObservations([existing,normalized]).reviewRequired){result.diagnostic="review_required";return result};case None=>()}
                let currentBundle=teacherExecutableAtomBundle(currentIdentity,row,currentSpec)
                let execution=executeTeacherAtomTestBundle(currentBundle,"${options.root}/runs/${options.runId}/atom-test-workspaces/${currentIdentity}",executor:atomExecutor,timeoutMillis:options.timeoutMillis)
                if(!execution.ok){if(execution.diagnostic=="atom_test_timeout"){result.diagnostic=execution.diagnostic;return result};atomFeedback=execution.feedback;continue}
                acceptedSpec=Some(currentSpec);acceptedObservation=Some(normalized);identity=currentIdentity;bundle=recordTeacherAtomTestExecution(currentBundle,execution.evidenceJson);break
            }
            let spec=match(acceptedSpec){case Some(v)=>v;case None=>throw IllegalStateException("accepted_atom_missing")}
            let normalized=match(acceptedObservation){case Some(v)=>v;case None=>throw IllegalStateException("accepted_observation_missing")}
            identities.add(identity,normalized)
            let simpleTests = buildKnowledgeAtomTestBundle(spec.positiveSource, spec.negativeSource, spec.boundarySource)
            let candidate = renderCandidateKnowledgeExport(normalized, spec.example, simpleTests)
            if (!auditCandidateAgainstSolutions(candidate, protected).passed || !auditCaseSpecificity(candidate, [caseValue.signature]).passed) {
                result.diagnostic = "candidate_leakage"; return result
            }
            let candidateText = renderTeacherCandidateExport(candidate)
            if (candidateForbidden(candidateText + bundle)) { result.diagnostic = "candidate_contamination"; return result }
            let ckbLine = renderTeacherCkbGap(row, options.runId, bundle, spec.transcriptHash)
            if (observations != "") { observations += "\n"; atoms += "\n"; tests += "\n"; candidates += "\n"; ckb += "\n" }
            observations += renderTeacherObservation(normalized); atoms += "${identity}\t${teacherEscapeField(spec.explanation)}"
            tests += bundle; candidates += candidateText; ckb += ckbLine; result.accepted += 1
        }
        let base = options.outputRoot.trimEnd('/')
        if (exists(Path(base))) { result.diagnostic = "output_already_exists"; return result }
        Directory.create(Path(base).parent, recursive: true)
        let canonicalRoot=canonicalize(Path(options.root)).toString();let canonicalParent=canonicalize(Path(base).parent).toString()
        if (!canonicalParent.startsWith(canonicalRoot+"/")) { result.diagnostic="output_path_forbidden";return result }
        let stage=base+".tmp-"+teacherStableHash(ckb)
        try {
            _ = teacherAtomicWrite("${stage}/observations.tsv", observations + "\n")
            _ = teacherAtomicWrite("${stage}/atoms.tsv", atoms + "\n")
            _ = teacherAtomicWrite("${stage}/atom-tests.jsonl", tests + "\n")
            _ = teacherAtomicWrite("${stage}/candidate-knowledge.tsv", candidates + "\n")
            _ = teacherAtomicWrite("${stage}/candidate-knowledge/ckb-benchmark-gap.jsonl", ckb + "\n")
            rename(Path(stage),to:Path(base),overwrite:false)
        } catch (e:Exception) { try{remove(Path(stage),recursive:true)}catch(_:Exception){};throw e }
        result.ckbJsonl = ckb + "\n"; result.ok = true; result.diagnostic = "ok"
    } catch (e: IllegalArgumentException) { result.diagnostic = e.message } catch (_: Exception) { result.diagnostic = "candidate_build_failed" }
    result
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
    let repair=if(atomFeedback==""){""}else{"\nA previous atom test failed. Correct the proposed knowledge test sources or expected diagnostic using this sanitized compiler evidence, then return a complete replacement object:\n${atomFeedback}"}
    let prompt="Extract reusable Cangjie knowledge as one JSON object. Never include the case id, solution code, task answer, hidden tests, or reference text. Required fields: provider=codex, model=${options.model}, knowledgeFamily (K4 enum), concept, explanation, example, citation, sourceClass, positiveSource, negativeSource, boundarySource, negativeDiagnostic. The three Source fields must each be a complete small Cangjie main source; positive and boundary must compile, negative must fail. Set citation to exactly '${row.citation}' with no Markdown, label, hash, or appended metadata. Set sourceClass to exactly 'official'. negativeDiagnostic must be a short literal substring emitted by the Cangjie compiler for negativeSource, not an explanatory sentence. Do not place any evidence hash or binding metadata inside user-facing knowledge fields. Bind internally to gap=${row.missingKnowledge}, targetVersion=${row.targetVersion}, sourceEvidenceHash=${row.evidenceHash}, completedRunEvidenceHash=${run.evidenceHash}, solutionContentHash=${solutionHash}. Allowed first-attempt evidence follows:\n${allowedEvidence}${repair}"
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
        let spec=TeacherAtomSpec(candidateString(o,"knowledgeFamily"),candidateString(o,"concept"),candidateString(o,"explanation"),candidateString(o,"example"),candidateString(o,"citation"),candidateString(o,"sourceClass"),candidateString(o,"positiveSource"),candidateString(o,"negativeSource"),candidateString(o,"boundarySource"),candidateString(o,"negativeDiagnostic"),"sha256:${teacherStableHash(raw)}",provider,model)
        if(!teacherK4Family(spec.family)||spec.concept==""||spec.explanation==""||spec.example==""||spec.positiveSource==""||spec.negativeSource==""||spec.boundarySource==""||spec.negativeDiagnostic==""){return(emptyTeacherAtomSpec(),"extractor_contract_invalid")}
        if(spec.sourceClass!="official"||spec.citation!=row.citation||!spec.citation.startsWith("https://docs.cangjie-lang.cn/")){return(emptyTeacherAtomSpec(),"extractor_source_invalid")}
        if(candidateForbidden(spec.concept+spec.explanation+spec.example+spec.positiveSource+spec.negativeSource+spec.boundarySource)){return(emptyTeacherAtomSpec(),"extractor_contamination")}
        (spec,"ok")
    }catch(_:Exception){(emptyTeacherAtomSpec(),"malformed_extractor_json")}
}

private func teacherExtractorOutputSchema():String{
    "{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"provider\",\"model\",\"knowledgeFamily\",\"concept\",\"explanation\",\"example\",\"citation\",\"sourceClass\",\"positiveSource\",\"negativeSource\",\"boundarySource\",\"negativeDiagnostic\"],\"properties\":{\"provider\":{\"type\":\"string\",\"enum\":[\"codex\"]},\"model\":{\"type\":\"string\",\"enum\":[\"gpt-5.6-sol\"]},\"knowledgeFamily\":{\"type\":\"string\",\"enum\":[\"syntax\",\"standard_library\",\"stdx\",\"toolchain\",\"compiler_diagnostic\",\"version_migration\",\"engineering_practice\"]},\"concept\":{\"type\":\"string\"},\"explanation\":{\"type\":\"string\"},\"example\":{\"type\":\"string\"},\"citation\":{\"type\":\"string\"},\"sourceClass\":{\"type\":\"string\",\"enum\":[\"official\"]},\"positiveSource\":{\"type\":\"string\"},\"negativeSource\":{\"type\":\"string\"},\"boundarySource\":{\"type\":\"string\"},\"negativeDiagnostic\":{\"type\":\"string\"}}}"
}

private func emptyTeacherAtomSpec():TeacherAtomSpec{TeacherAtomSpec("","","","","","","","","","","","","")}
private func teacherK4Family(v:String):Bool{["syntax","standard_library","stdx","toolchain","compiler_diagnostic","version_migration","engineering_practice"].contains(v)}

private func teacherExecutableAtomBundle(identity: String, row: TeacherGapRow, spec: TeacherAtomSpec): String {
    let tests = "[{\"category\":\"positive\",\"operation\":\"contains\",\"input\":\"atom\",\"needle\":\"atom\",\"expected\":\"true\",\"source\":\"${candidateEscape(spec.positiveSource)}\",\"expectedMode\":\"pass\"},{\"category\":\"negative\",\"operation\":\"contains\",\"input\":\"safe\",\"needle\":\"forbidden\",\"expected\":\"false\",\"source\":\"${candidateEscape(spec.negativeSource)}\",\"expectedMode\":\"compile_reject\",\"expectedDiagnostic\":\"${candidateEscape(spec.negativeDiagnostic)}\"},{\"category\":\"boundary\",\"operation\":\"rune_count\",\"input\":\"😀\",\"expected\":\"1\",\"source\":\"${candidateEscape(spec.boundarySource)}\",\"expectedMode\":\"pass\"}]"
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
            _=teacherAtomicWrite("${root}/cjpm.toml","[package]\n  cjc-version = \"1.0.0\"\n  name = \"teacher_atom_${category}\"\n  version = \"1.0.0\"\n  output-type = \"executable\"\n")
            let source=candidateString(t,"source");if(source.trimAscii().startsWith("package ")){out.diagnostic="atom_source_package_forbidden";return out}
            _=teacherAtomicWrite("${root}/src/main.cj","package teacher_atom_${category}\n\n${source}\n");var categoryOk=true;var categoryEvidence=""
            for(args in [["clean"],["build","-i"],["test","-j","1"]]){let r=executor.execute(TeacherCommandSpec("cjpm",args,root,timeoutMillis:timeoutMillis));categoryEvidence+="${args[0]}:${r.exitCode}:sha256:${teacherStableHash(r.output)}|";if(r.timedOut){out.diagnostic="atom_test_timeout";return out};if(category=="negative"&&args[0]=="build"){categoryOk=r.exitCode!=0&&r.output.contains(candidateString(t,"expectedDiagnostic"));if(!categoryOk){out.feedback=teacherSanitizeEvidence("category=negative expectedDiagnostic=${candidateString(t,"expectedDiagnostic")} actualCompilerOutput=${r.output.replace(root,"[atom-workspace]")}")};break};if(r.exitCode!=0){categoryOk=false;out.feedback=teacherSanitizeEvidence("category=${category} command=${args[0]} expected=success actualCompilerOutput=${r.output.replace(root,"[atom-workspace]")}");break}}
            if(categoryOk){passed++};evidence+="${category}:${categoryEvidence}passed=${categoryOk};"
        }
        if(categories.contains("positive")&&categories.contains("negative")&&categories.contains("boundary")&&passed==3){out.ok=true;out.diagnostic="ok";out.evidenceJson="{\"total\":3,\"passed\":3,\"failed\":0,\"status\":\"passed\",\"commandEvidence\":\"${candidateEscape(evidence)}\",\"commandEvidenceHash\":\"sha256:${teacherStableHash(evidence)}\"}"}else{out.diagnostic="atom_test_failed";if(out.feedback==""){out.feedback="atom categories incomplete or failed"}}
    }catch(_:Exception){out.diagnostic="malformed_atom_test_bundle"};out
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

private func teacherPrivateArtifacts(root:String):Array<String>{let out=ArrayList<String>();teacherCollectPrivate(Path(root),out);out.toArray()}
private func teacherCollectPrivate(path:Path,out:ArrayList<String>):Unit{try{for(e in Directory.readFrom(path)){teacherCollectPrivate(e.path,out)}}catch(_:Exception){try{out.add(teacherReadUtf8File(path.toString()))}catch(_:Exception){}}}
private func candidateForbidden(raw:String):Bool{let v=raw.toAsciiLower();v.contains("cj-humaneval-")||v.contains("canonical_solution")||v.contains("hidden_test")||v.contains("hidden assertion")||v.contains("teacher-solutions")||v.contains("/reference/")}
private func candidateSafeId(v:String):Bool{v!=""&&!v.contains("/")&&!v.contains("\\")&&!v.contains("..")&&v.toRuneArray().size<=128}
private func candidatePart(v:String):String{"${v.toArray().size}:${v}"}
private func teacherEscapeField(v:String):String{v.replace("%","%25").replace("\t","%09").replace("\n","%0A")}
private func candidateEscape(v:String):String{v.replace("\\","\\\\").replace("\"","\\\"").replace("\n","\\n").replace("\r","\\r").replace("\t","\\t")}
private func candidateString(o:JsonObject,k:String):String{match(o.get(k)){case Some(v)=>v.asString().getValue().trimAscii();case None=>""}}
private func candidateInt(o:JsonObject,k:String,f:Int64):Int64{match(o.get(k)){case Some(v)=>try{Int64.parse(v.toString())}catch(_:Exception){f};case None=>f}}
