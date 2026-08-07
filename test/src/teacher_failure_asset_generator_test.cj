package cangjie_teacher_test

import std.unittest.testmacro.*
import cangjie_teacher.*

class S2Generator <: TeacherFailureAssetGenerator {
    public func generate(request: TeacherFailureAssetGenerationRequest): String {
        let content = match (request.lane) {
            case "knowledge" => "Use the documented Rune conversion API for version 1.0."
            case "skill" => "Inspect byte and Rune types, then verify the boundary before rendering."
            case _ => "Preserve Rune boundaries in every bounded user-visible rendering operation."
        }
        let title = "Reusable ${request.lane} guidance"
        let evidence = "{\"schemaVersion\":\"teacher-failure-asset-generation-response-v1\"," +
            "\"lane\":\"${request.lane}\",\"title\":\"${title}\",\"content\":\"${content}\"," +
            "\"trigger\":\"When handling Unicode text\",\"scope\":\"Cangjie text rendering\",\"priority\":100}"
        renderTeacherFailureAssetGenerationResponse(TeacherFailureAssetGenerationResponse(request.lane,
            title, content, "When handling Unicode text", "Cangjie text rendering", 100,
            "sha256:${teacherStableHash(evidence)}"))
    }
}

class S2DuplicateGenerator <: TeacherFailureAssetGenerator {
    public func generate(request: TeacherFailureAssetGenerationRequest): String {
        let evidence = "{\"schemaVersion\":\"teacher-failure-asset-generation-response-v1\"," +
            "\"lane\":\"${request.lane}\",\"title\":\"Shared proposal\",\"content\":\"Duplicate content\"," +
            "\"trigger\":\"Generic trigger\",\"scope\":\"Generic scope\",\"priority\":1}"
        renderTeacherFailureAssetGenerationResponse(TeacherFailureAssetGenerationResponse(request.lane,
            "Shared proposal", "Duplicate content", "Generic trigger", "Generic scope", 1,
            "sha256:${teacherStableHash(evidence)}"))
    }
}

@Test
public class TeacherFailureAssetGeneratorTest {
    @TestCase public func failureAssetGeneratorProducesOnlyEligibleDistinctProposals(): Unit {
        let internal = s2InternalClassification("all_assets_gap", true, true, true, "multiple_reusable_gaps")
        let shared = reconcileTeacherFailureAssetClassifications(internal, internal)
        let proposals = generateTeacherFailureAssetProposals(shared, "Unicode边界🙂 reusable gap", S2Generator())
        @Expect(proposals.size, 3)
        @Expect(proposals[0].lane, "knowledge")
        @Expect(proposals[1].lane, "skill")
        @Expect(proposals[2].lane, "rules")
        var duplicateRejected = ""
        try { _ = generateTeacherFailureAssetProposals(shared, "generic safe gap", S2DuplicateGenerator()) }
        catch (e: Exception) { duplicateRejected = e.message }
        @Expect(duplicateRejected, "candidate_generation_invalid")
    }
}
