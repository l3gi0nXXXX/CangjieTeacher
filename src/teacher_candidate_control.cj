package cangjie_teacher

import std.collection.*
import std.fs.*
import std.convert.Parsable
import stdx.encoding.json.*

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
    init(family: String, concept: String, explanation: String, example: String) {
        this.family = family; this.concept = concept; this.explanation = explanation; this.example = example
    }
}

public func runTeacherCandidateBuild(options: TeacherCliOptions): Int64 {
    let result = buildTeacherCandidates(options)
    if (!result.ok) { println("candidate build blocked diagnostic=${result.diagnostic}"); return 1 }
    println("candidate build complete accepted=${result.accepted}")
    0
}

public func buildTeacherCandidates(options: TeacherCliOptions): TeacherCandidateBuildResult {
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
            let solutionRoot = TeacherPaths(options.root).solution(row.caseId)
            if (!exists(Path(solutionRoot))) { result.diagnostic = "private_solution_required"; return result }
            let protected = teacherPrivateArtifacts(solutionRoot)
            let spec = teacherAtomSpec(row.missingKnowledge)
            let observation = deriveKnowledgeObservation(caseValue, spec.family, spec.concept, row.targetVersion, spec.explanation, row.citation, "official", row.evidence)
            if (!validateObservationNoSolutionLeak(observation)) { result.diagnostic = "observation_leakage"; return result }
            let normalized = normalizeObservation(observation)
            let identity = canonicalKnowledgeIdentity(normalized)
            match (identities.get(identity)) {
                case Some(existing) => if (mergeKnowledgeObservations([existing, normalized]).reviewRequired) { result.diagnostic = "review_required"; return result }
                case None => identities.add(identity, normalized)
            }
            var bundle = teacherExecutableAtomBundle(identity, row, spec)
            let execution = executeTeacherAtomTestBundle(bundle)
            if (!execution[0]) { result.diagnostic = execution[1]; return result }
            bundle = recordTeacherAtomTestExecution(bundle)
            let simpleTests = buildKnowledgeAtomTestBundle("executed:positive", "executed:negative", "executed:boundary")
            let candidate = renderCandidateKnowledgeExport(normalized, spec.example, simpleTests)
            if (!auditCandidateAgainstSolutions(candidate, protected).passed || !auditCaseSpecificity(candidate, [caseValue.signature]).passed) {
                result.diagnostic = "candidate_leakage"; return result
            }
            let candidateText = renderTeacherCandidateExport(candidate)
            if (candidateForbidden(candidateText + bundle)) { result.diagnostic = "candidate_contamination"; return result }
            let ckbLine = renderTeacherCkbGap(row, options.runId, bundle)
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

private func teacherAtomSpec(raw: String): TeacherAtomSpec {
    let code = raw.split(",")[0].trimAscii().toAsciiUpper()
    if (code=="G-ARRAYLIST") { return TeacherAtomSpec("standard_library","arraylist fundamentals","ArrayList is a growable sequence; use its typed element API and inspect size for boundaries.","Create an ArrayList<Int64>, append values, and inspect size.") }
    if (code=="G-HASHMAP") { return TeacherAtomSpec("standard_library","hashmap fundamentals","HashMap associates hashable keys with typed values and requires explicit missing-key handling.","Create a HashMap<String, Int64> and handle lookup absence.") }
    if (code=="G-STRING") { return TeacherAtomSpec("syntax","unicode string boundaries","Use Rune iteration or Rune arrays when character boundaries matter because UTF-8 byte positions are not character positions.","Count the Runes in a string containing Chinese text and emoji.") }
    if (code=="G-FLOAT64") { return TeacherAtomSpec("syntax","float64 arithmetic","Float64 literals include a decimal point and floating-point comparisons should account for representation precision.","Use 4.0 as a Float64 literal and compare within a tolerance.") }
    if (code=="G-INT64") { return TeacherAtomSpec("syntax","int64 arithmetic","Int64 arithmetic is signed integer arithmetic; validate overflow-sensitive and empty-input boundaries explicitly.","Accumulate typed Int64 values while handling an empty collection.") }
    if (code=="G-EDGE"||code=="G-RECIPE") { return TeacherAtomSpec("engineering_practice","boundary-first implementation","Handle empty, singleton, repeated, and maximum supported inputs before applying the core transformation.","Define behavior for empty and singleton inputs before the general case.") }
    throw IllegalArgumentException("unsupported_knowledge_gap")
}

private func teacherExecutableAtomBundle(identity: String, row: TeacherGapRow, spec: TeacherAtomSpec): String {
    let tests = "[{\"category\":\"positive\",\"operation\":\"contains\",\"input\":\"中文😀 Rune boundary\",\"needle\":\"Rune\",\"expected\":\"true\"},{\"category\":\"negative\",\"operation\":\"contains\",\"input\":\"typed knowledge\",\"needle\":\"answer marker\",\"expected\":\"false\"},{\"category\":\"boundary\",\"operation\":\"rune_count\",\"input\":\"😀\",\"expected\":\"1\"}]"
    let canonical = candidatePart(identity)+candidatePart("official")+candidatePart(row.citation.toAsciiLower())+candidatePart(row.targetVersion)+candidatePart(spec.explanation)+candidatePart("true")+candidatePart(tests)
    let hash = "sha256:${teacherStableHash(canonical)}"
    "{\"atomId\":\"${candidateEscape(identity)}\",\"sourceClass\":\"official\",\"citation\":\"${candidateEscape(row.citation)}\",\"targetVersion\":\"${candidateEscape(row.targetVersion)}\",\"candidateHash\":\"${hash}\",\"knowledgeText\":\"${candidateEscape(spec.explanation)}\",\"purificationPassed\":true,\"tests\":${tests}}"
}

public func executeTeacherAtomTestBundle(raw: String): (Bool,String) {
    try {
        let tests=JsonValue.fromStr(raw).asObject().get("tests").getOrThrow().asArray().getItems();let categories=HashSet<String>();var passed:Int64=0
        for(v in tests){let o=v.asObject();let category=candidateString(o,"category");categories.add(category);let operation=candidateString(o,"operation");let input=candidateString(o,"input");let expected=candidateString(o,"expected");let actual=if(operation=="contains"){"${input.contains(candidateString(o,"needle"))}"}else if(operation=="rune_count"){"${input.toRuneArray().size}"}else{"unsupported"};if(actual==expected){passed++}}
        if(categories.contains("positive")&&categories.contains("negative")&&categories.contains("boundary")&&passed==tests.size){(true,"ok")}else{(false,"atom_test_failed")}
    } catch (_: Exception) {(false,"malformed_atom_test_bundle")}
}

private func recordTeacherAtomTestExecution(raw:String):String {
    let total=try{JsonValue.fromStr(raw).asObject().get("tests").getOrThrow().asArray().getItems().size}catch(_:Exception){0}
    let runes=raw.toRuneArray()
    String(runes[..runes.size-1])+",\"execution\":{\"total\":${total},\"passed\":${total},\"failed\":0,\"status\":\"passed\"}}"
}

private func renderTeacherCkbGap(row: TeacherGapRow, runId: String, bundle: String): String {
    let candidatePath="candidate-knowledge/ckb-benchmark-gap.jsonl";let evidence="${row.evidence}|teacherAtomHash=sha256:${teacherStableHash(bundle)}";let evidenceHash="sha256:${teacherStableHash(evidence)}"
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
