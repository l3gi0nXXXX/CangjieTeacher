package cangjie_teacher

import std.collection.*
import std.fs.*
import std.sort.*
import stdx.encoding.json.*

private func teacherBaseString(object: JsonObject, name: String): String {
    match (object.get(name)) { case Some(value) => value.asString().getValue(); case None => "" }
}

private func teacherBaseInt(object: JsonObject, name: String): Int64 {
    match (object.get(name)) { case Some(value) => value.asInt().getValue(); case None => Int64(-1) }
}

private func teacherBaseBool(object: JsonObject, name: String): Bool {
    match (object.get(name)) { case Some(value) => value.asBool().getValue(); case None => false }
}

private func teacherBaseChangedLanes(object: JsonObject): Array<String> {
    let out = ArrayList<String>()
    match (object.get("changedLanes")) {
        case Some(value) => for (item in value.asArray().getItems()) { out.add(item.asString().getValue()) }
        case None => throw IllegalArgumentException("candidate_base_composite_mismatch")
    }
    let lanes = out.toArray(); let sorted = lanes.clone(); sort(sorted)
    let seen = HashSet<String>()
    for (lane in lanes) {
        if (!["knowledge", "rules", "skills"].contains(lane) || seen.contains(lane)) {
            throw IllegalArgumentException("candidate_base_composite_mismatch")
        }
        seen.add(lane)
    }
    if (lanes.isEmpty() || lanes != sorted) { throw IllegalArgumentException("candidate_base_composite_mismatch") }
    lanes
}

private func teacherBaseHash(value: String): Bool {
    let runes = value.toRuneArray()
    if (!value.startsWith("sha256:") || runes.size != 71) { return false }
    for (rune in runes[7..]) {
        if (!((rune >= r'0' && rune <= r'9') || (rune >= r'a' && rune <= r'f'))) { return false }
    }
    true
}

private func teacherBaseReadCanonicalJson(path: String): String {
    let file = teacherReadUtf8File(path); let raw = file.trimAscii()
    if (file != raw + "\n") { throw IllegalArgumentException("candidate_base_composite_mismatch") }
    raw
}

private func teacherBaseExactEntries(root: Path): Unit {
    let expected = HashSet<String>(["student-context-manifest.json", "student-agents-rules.json",
        "AGENTS.md", "student-skills.json", "student-skills.prompt.md",
        "knowledge-reference.json", "combination-audit.json"])
    for (entry in Directory.readFrom(root)) {
        if (entry.isSymbolicLink() || !entry.isRegular() || !expected.contains(entry.name)) {
            throw IllegalArgumentException("candidate_base_composite_mismatch")
        }
        expected.remove(entry.name)
    }
    if (!expected.isEmpty()) { throw IllegalArgumentException("candidate_base_composite_mismatch") }
}

private func teacherBaseValidateTrailingHash(raw: String, marker: String, hash: String): Unit {
    let suffix = marker + hash + "\"}"
    let rawRunes = raw.toRuneArray(); let suffixRunes = suffix.toRuneArray()
    if (!teacherBaseHash(hash) || !raw.endsWith(suffix) || rawRunes.size <= suffixRunes.size) {
        throw IllegalArgumentException("candidate_base_composite_mismatch")
    }
    let evidence = String(rawRunes[..rawRunes.size - suffixRunes.size]) + "}"
    if (hash != "sha256:${teacherStableHash(evidence)}") {
        throw IllegalArgumentException("candidate_base_composite_mismatch")
    }
}

private func teacherBaseRules(raw: String): (String, Int64, Array<TeacherContextBaseAssetIdentity>, String, String) {
    let object = JsonValue.fromStr(raw).asObject()
    if (object.getFields().size != 6 || teacherBaseString(object, "schemaVersion") !=
        "ckb-student-rules-bundle-v1") {
        throw IllegalArgumentException("candidate_base_composite_mismatch")
    }
    let identities = ArrayList<TeacherContextBaseAssetIdentity>(); let ids = ArrayList<String>()
    var bundleLineage = "independent"
    match (object.get("rules")) {
        case Some(value) => for (item in value.asArray().getItems()) {
            let row = item.asObject()
            if (row.getFields().size != 19 || teacherBaseString(row, "schemaVersion") !=
                "teacher-rule-candidate-v1" || teacherBaseString(row, "assetRole") != "rules") {
                throw IllegalArgumentException("candidate_base_composite_mismatch")
            }
            let id = teacherBaseString(row, "ruleId")
            let content = teacherBaseString(row, "content")
            let contentHash = teacherBaseString(row, "contentHash")
            let canonicalHash = teacherBaseString(row, "canonicalHash")
            let fields = [id, teacherBaseString(row, "conceptId"), teacherBaseString(row, "title"),
                teacherBaseString(row, "body"), teacherBaseString(row, "trigger"),
                teacherBaseString(row, "scope"), teacherBaseInt(row, "priority").toString(),
                teacherBaseString(row, "sourceEvidenceKind"), teacherBaseString(row, "sourceEvidenceHash"),
                "rules", teacherBaseString(row, "assetLineage"),
                teacherBaseString(row, "positiveEvidenceHash"), teacherBaseString(row, "negativeEvidenceHash"),
                teacherBaseString(row, "boundaryEvidenceHash"), teacherBaseString(row, "generalizationEvidenceHash")]
            let canonical = teacherJoin(fields.map({field: String => "${field.toArray().size}:${field}"}), "")
            let rendered = "\n## ${teacherBaseString(row, "title")}\n\n" +
                "${teacherBaseString(row, "body")}\n\nTrigger: ${teacherBaseString(row, "trigger")}\n" +
                "Scope: ${teacherBaseString(row, "scope")}\n"
            let lineage = teacherBaseString(row, "assetLineage")
            let priority = teacherBaseInt(row, "priority")
            let sourceKind = teacherBaseString(row, "sourceEvidenceKind")
            if (!teacherArtifactSafeComponent(id) || content != rendered || priority < 0 || priority > 1000 ||
                contentHash != "sha256:${teacherStableHash(content)}" ||
                canonicalHash != "sha256:${teacherStableHash(canonical)}" ||
                !["independent", "humaneval_164_derived"].contains(lineage) ||
                !((sourceKind == "independent_manifest" && lineage == "independent") ||
                    (sourceKind == "completion_failure" && lineage == "humaneval_164_derived")) ||
                !teacherBaseHash(teacherBaseString(row, "sourceEvidenceHash")) ||
                !teacherBaseHash(teacherBaseString(row, "positiveEvidenceHash")) ||
                !teacherBaseHash(teacherBaseString(row, "negativeEvidenceHash")) ||
                !teacherBaseHash(teacherBaseString(row, "boundaryEvidenceHash")) ||
                !teacherBaseHash(teacherBaseString(row, "generalizationEvidenceHash"))) {
                throw IllegalArgumentException("candidate_base_composite_mismatch")
            }
            if (lineage == "humaneval_164_derived") { bundleLineage = lineage }
            ids.add(id); identities.add(TeacherContextBaseAssetIdentity(id, canonicalHash,
                content: content, priority: teacherBaseInt(row, "priority")))
        }
        case None => throw IllegalArgumentException("candidate_base_composite_mismatch")
    }
    let sorted = ids.toArray().clone(); sort(sorted)
    if (ids.isEmpty() || ids.toArray() != sorted || HashSet<String>(ids.toArray()).size != ids.size ||
        teacherBaseInt(object, "ruleCount") != ids.size ||
        !teacherBaseHash(teacherBaseString(object, "canonicalHash"))) {
        throw IllegalArgumentException("candidate_base_composite_mismatch")
    }
    teacherBaseValidateTrailingHash(raw, ",\"canonicalHash\":\"",
        teacherBaseString(object, "canonicalHash"))
    (teacherBaseString(object, "rulesVersion"), teacherBaseInt(object, "contentBytes"), identities.toArray(),
        teacherBaseString(object, "canonicalHash"), bundleLineage)
}

private func teacherBaseSkills(raw: String): (String, Int64, Array<TeacherContextBaseAssetIdentity>, String, String) {
    let object = JsonValue.fromStr(raw).asObject()
    if (object.getFields().size != 6 || teacherBaseString(object, "schemaVersion") !=
        "ckb-student-skill-bundle-v1") {
        throw IllegalArgumentException("candidate_base_composite_mismatch")
    }
    let identities = ArrayList<TeacherContextBaseAssetIdentity>(); let ids = ArrayList<String>()
    var bundleLineage = "independent"
    match (object.get("skills")) {
        case Some(value) => for (item in value.asArray().getItems()) {
            let row = item.asObject()
            if (row.getFields().size != 11) { throw IllegalArgumentException("candidate_base_composite_mismatch") }
            let id = teacherBaseString(row, "id"); let content = teacherBaseString(row, "content")
            let skillHash = teacherBaseString(row, "skillContentHash")
            let candidateHash = teacherBaseString(row, "candidateContentHash")
            let fields = [id, teacherBaseString(row, "version"), teacherBaseString(row, "title"),
                teacherBaseString(row, "procedure"), teacherBaseString(row, "sourceCategory"),
                teacherBaseString(row, "applicability"), teacherBaseString(row, "lineage"),
                teacherBaseString(row, "testEvidenceHash")]
            let canonical = teacherJoin(fields.map({field: String => "${field.toArray().size}:${field}"}), "")
            let rendered = "---\nname: ${id}\nversion: ${teacherBaseString(row, "version")}\n" +
                "source: ${teacherBaseString(row, "sourceCategory")}\nlineage: ${teacherBaseString(row, "lineage")}\n" +
                "content-hash: ${candidateHash}\n---\n\n# ${teacherBaseString(row, "title")}\n\n" +
                "Applicability: ${teacherBaseString(row, "applicability")}\n\n${teacherBaseString(row, "procedure")}\n"
            let lineage = teacherBaseString(row, "lineage")
            let sourceCategory = teacherBaseString(row, "sourceCategory")
            if (!teacherArtifactSafeComponent(id) || content != rendered ||
                skillHash != "sha256:${teacherStableHash(content)}" ||
                !teacherBaseHash(teacherBaseString(row, "testEvidenceHash")) ||
                candidateHash != "sha256:${teacherStableHash(canonical)}" ||
                !((sourceCategory == "general_engineering" && lineage == "independent") ||
                    (sourceCategory == "teacher_derived" && lineage == "humaneval_164_derived"))) {
                throw IllegalArgumentException("candidate_base_composite_mismatch")
            }
            if (lineage == "humaneval_164_derived") { bundleLineage = lineage }
            ids.add(id); identities.add(TeacherContextBaseAssetIdentity(id, candidateHash,
                content: content))
        }
        case None => throw IllegalArgumentException("candidate_base_composite_mismatch")
    }
    let sorted = ids.toArray().clone(); sort(sorted)
    if (ids.isEmpty() || ids.toArray() != sorted || HashSet<String>(ids.toArray()).size != ids.size ||
        teacherBaseInt(object, "skillCount") != ids.size ||
        !teacherBaseHash(teacherBaseString(object, "canonicalHash"))) {
        throw IllegalArgumentException("candidate_base_composite_mismatch")
    }
    teacherBaseValidateTrailingHash(raw, ",\"canonicalHash\":\"",
        teacherBaseString(object, "canonicalHash"))
    (teacherBaseString(object, "bundleVersion"), teacherBaseInt(object, "contentBytes"), identities.toArray(),
        teacherBaseString(object, "canonicalHash"), bundleLineage)
}

// The manifest path, not merely a caller-provided composite hash, is the authority for inherited lanes.
public func loadTeacherContextBaseStateV2(allowedRoot: String,
    baseContextRoot: String): TeacherContextBaseStateV2 {
    let root = Path(teacherResolveArtifactInput(allowedRoot, baseContextRoot, directory: true))
    let manifest = root.join("student-context-manifest.json").toString()
    teacherBaseExactEntries(root)
    try {
        let raw = teacherBaseReadCanonicalJson(manifest)
        let object = JsonValue.fromStr(raw).asObject()
        if (object.getFields().size != 26 || teacherBaseString(object, "schemaVersion") !=
            "ckb-student-context-bundle-v2") {
            throw IllegalArgumentException("candidate_base_composite_mismatch")
        }
        let compositeHash = teacherBaseString(object, "compositeHash")
        teacherBaseValidateTrailingHash(raw, ",\"compositeHash\":\"", compositeHash)
        _ = teacherBaseChangedLanes(object)
        if (teacherBaseString(object, "contextVersion").isEmpty() ||
            !(teacherBaseString(object, "baseCompositeHash") == "none" ||
                teacherBaseHash(teacherBaseString(object, "baseCompositeHash"))) ||
            !teacherBaseHash(teacherBaseString(object, "candidateSetHash")) ||
            !teacherBaseHash(teacherBaseString(object, "approvalHash")) ||
            !["scaffold_contract", "student_validated"].contains(teacherBaseString(object, "validationLevel")) ||
            !["independent", "humaneval_164_derived"].contains(teacherBaseString(object, "aggregateAssetLineage"))) {
            throw IllegalArgumentException("candidate_base_composite_mismatch")
        }
        let rulesVisible = teacherReadUtf8File(root.join("AGENTS.md").toString())
        let skillsVisible = teacherReadUtf8File(root.join("student-skills.prompt.md").toString())
        let rules = teacherBaseRules(teacherBaseReadCanonicalJson(root.join("student-agents-rules.json").toString()))
        let skills = teacherBaseSkills(teacherBaseReadCanonicalJson(root.join("student-skills.json").toString()))
        let knowledgeRaw = teacherBaseReadCanonicalJson(root.join("knowledge-reference.json").toString())
        let knowledge = parseTeacherFrozenKnowledgeReference(knowledgeRaw)
        let auditRaw = teacherBaseReadCanonicalJson(root.join("combination-audit.json").toString())
        let audit = JsonValue.fromStr(auditRaw).asObject()
        if (audit.getFields().size != 5 || teacherBaseString(audit, "schemaVersion") !=
            "ckb-student-context-combination-audit-v1" || !teacherBaseBool(audit, "passed") ||
            !teacherBaseHash(teacherBaseString(audit, "sourceClosureHash")) ||
            !teacherBaseHash(teacherBaseString(audit, "protectedClosureHash")) ||
            teacherBaseString(audit, "combinationAuditHash") != teacherBaseString(object, "combinationAuditHash")) {
            throw IllegalArgumentException("candidate_base_composite_mismatch")
        }
        let auditCanonical = "{\"schemaVersion\":\"ckb-student-context-combination-audit-v1\"," +
            "\"sourceClosureHash\":\"${teacherBaseString(audit, "sourceClosureHash")}\"," +
            "\"protectedClosureHash\":\"${teacherBaseString(audit, "protectedClosureHash")}\"," +
            "\"combinationAuditHash\":\"${teacherBaseString(audit, "combinationAuditHash")}\",\"passed\":true}"
        let combinationValues = [teacherBaseString(object, "rulesHash"),
            teacherBaseString(object, "skillProjectionHash"), teacherBaseString(object, "knowledgeContentHash"),
            teacherBaseString(audit, "sourceClosureHash"), teacherBaseString(audit, "protectedClosureHash")]
        let combinationEvidence = teacherJoin(combinationValues.map(
            {value: String => "${value.toArray().size}:${value}"}), "")
        let expectedCombination = "sha256:${teacherStableHash(combinationEvidence)}"
        if (auditRaw != auditCanonical || teacherBaseString(audit, "combinationAuditHash") != expectedCombination) {
            throw IllegalArgumentException("candidate_base_composite_mismatch")
        }
        let expectedAggregate = if (rules[4] == "independent" && skills[4] == "independent" &&
            knowledge.assetLineage == "independent") { "independent" } else { "humaneval_164_derived" }
        if (teacherBaseString(object, "aggregateAssetLineage") != expectedAggregate ||
            teacherBaseString(object, "rulesVersion") != rules[0] ||
            teacherBaseInt(object, "rulesCount") != rules[2].size ||
            teacherBaseInt(object, "rulesContentBytes") != rulesVisible.toArray().size ||
            teacherBaseInt(object, "rulesContentBytes") != rules[1] ||
            teacherBaseString(object, "rulesHash") != "sha256:${teacherStableHash(rulesVisible)}" ||
            rulesVisible != teacherContextAssetProjection("rules", rules[2]) ||
            teacherBaseString(object, "rulesBundleHash") != rules[3] ||
            teacherBaseString(object, "rulesAssetLineage") != rules[4] ||
            teacherBaseString(object, "skillBundleVersion") != skills[0] ||
            teacherBaseInt(object, "skillCount") != skills[2].size ||
            teacherBaseInt(object, "skillContentBytes") != skillsVisible.toArray().size ||
            teacherBaseInt(object, "skillContentBytes") != skills[1] ||
            teacherBaseString(object, "skillBundleHash") != skills[3] ||
            teacherBaseString(object, "skillAssetLineage") != skills[4] ||
            teacherBaseString(object, "skillProjectionHash") != "sha256:${teacherStableHash(skillsVisible)}" ||
            skillsVisible != teacherContextAssetProjection("skills", skills[2]) ||
            teacherBaseString(object, "knowledgeVersion") != knowledge.knowledgeVersion ||
            teacherBaseString(object, "knowledgeContentHash") != knowledge.knowledgeContentHash ||
            teacherBaseString(object, "frozenCandidateManifestHash") != knowledge.frozenCandidateManifestHash ||
            teacherBaseString(object, "knowledgeAssetLineage") != knowledge.assetLineage) {
            throw IllegalArgumentException("candidate_base_composite_mismatch")
        }
        let closureBindings = ["student-context-manifest.json", "student-agents-rules.json", "AGENTS.md",
            "student-skills.json", "student-skills.prompt.md", "knowledge-reference.json",
            "combination-audit.json"].map({name: String =>
                "sha256:${teacherStableHash(teacherReadUtf8File(root.join(name).toString()))}" })
        TeacherContextBaseStateV2(compositeHash, teacherBaseString(object, "rulesHash"),
            teacherBaseInt(object, "rulesCount"), teacherBaseString(object, "rulesAssetLineage"),
            rulesVisible, rules[2], teacherBaseString(object, "skillProjectionHash"),
            teacherBaseInt(object, "skillCount"), teacherBaseString(object, "skillAssetLineage"),
            skillsVisible, skills[2], knowledge.knowledgeCandidateHash, knowledge.knowledgeVersion,
            knowledge.assetLineage, knowledgeRaw + "\n", closureBindings: closureBindings,
            baseInputRoot: baseContextRoot, baseRoot: root.toString())
    } catch (e: IllegalArgumentException) { throw e }
    catch (_: Exception) { throw IllegalArgumentException("candidate_base_composite_mismatch") }
}
