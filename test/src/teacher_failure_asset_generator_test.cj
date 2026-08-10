package cangjie_teacher_test

import std.unittest.testmacro.*
import std.fs.*
import std.time.*
import cangjie_teacher.*

private class R6GeneratorProcess <: TeacherCommandExecutor {
    public let response: String
    public var calls: Int64 = 0
    public init(response: String) { this.response = response }
    public func execute(spec: TeacherCommandSpec): TeacherProcessResult {
        calls += 1; _ = teacherAtomicWrite(spec.args[3], response + "\n")
        TeacherProcessResult(0, "ignored generator console output")
    }
}

class S2Generator <: TeacherFailureAssetGenerator {
    public func generate(request: TeacherFailureAssetGenerationRequest): String {
        let content = match (request.lane) {
            case "knowledge" => "g-rune"
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
    // R6-T2-UT/POS/NEG: generator process response is lane-bound and canonical.
    @TestCase public func r6T2StrictGeneratorProcessContract(): Unit {
        let root = "/tmp/teacher-r6-generator-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        try {
            Directory.create(Path("${root}/workspace"), recursive: true)
            _ = teacherAtomicWrite("${root}/generator", "deterministic generator adapter\n")
            let canonical = canonicalize(Path(root)).toString()
            let executable = "${canonical}/generator"
            let request = TeacherFailureAssetGenerationRequest(
                String(Array<Rune>(64, repeat: r'a')), String(Array<Rune>(64, repeat: r'b')),
                "rules", "Unicode边界🙂 reusable gap")
            let response = S2Generator().generate(request)
            let process = R6GeneratorProcess(response)
            let adapter = StrictProcessTeacherFailureAssetGenerator(executable,
                teacherValidationExecutableHash(executable), canonical, "${canonical}/workspace",
                executor: process)
            @Expect(adapter.generate(request), response); @Expect(process.calls, 1)

            Directory.create(Path("${root}/workspace-wrong"), recursive: true)
            let wrong = S2Generator().generate(TeacherFailureAssetGenerationRequest(
                request.failureEvidenceHash, request.classificationEvidenceHash,
                "skill", request.gapDescription))
            var diagnostic = ""
            try { _ = StrictProcessTeacherFailureAssetGenerator(executable,
                teacherValidationExecutableHash(executable), canonical,
                "${canonical}/workspace-wrong", executor: R6GeneratorProcess(wrong)).generate(request) }
            catch (e: Exception) { diagnostic = e.message }
            @Expect(diagnostic, "candidate_generation_invalid")
        } finally { try { remove(Path(root), recursive: true) } catch (_: Exception) {} }
    }

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
