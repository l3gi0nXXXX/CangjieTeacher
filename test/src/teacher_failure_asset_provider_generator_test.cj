package cangjie_teacher_test

import cangjie_teacher.*
import std.collection.*
import std.fs.*
import std.time.DateTime
import std.unittest.*
import std.unittest.testmacro.*

private class FailureGeneratorFakeExecutor <: TeacherCommandExecutor {
    let mode: String
    public let specs = ArrayList<TeacherCommandSpec>()
    public init(mode!: String = "ok") { this.mode = mode }
    public func execute(spec: TeacherCommandSpec): TeacherProcessResult {
        specs.add(spec)
        if (mode == "timeout") { return TeacherProcessResult(124, "ignored secret", timedOut: true) }
        if (mode == "nonzero") { return TeacherProcessResult(9, "Authorization: ignored") }
        var output = ""
        for (i in 0..spec.args.size - 1) {
            if (spec.args[i] == "--output-last-message") { output = spec.args[i + 1] }
        }
        if (mode == "missing") { return TeacherProcessResult(0, "") }
        if (mode == "invalid_utf8") {
            File.writeTo(Path(output), [UInt8(0xff), UInt8(0xfe)])
            return TeacherProcessResult(0, "")
        }
        let requestedLane = failureGeneratorTestRequestLane(spec.args[spec.args.size - 1])
        let lane = if (mode == "wrong_lane") { if (requestedLane == "rules") { "skill" } else { "rules" } } else { requestedLane }
        let valid = failureGeneratorTestResponse(lane)
        let body = match (mode) {
            case "malformed" => "{"
            case "forbidden" => valid.replace("General 中文🙂", "hidden_test answer")
            case "oversized_rule" => valid.replace("General 中文🙂 rules guidance",
                String(Array<Rune>(1001, repeat: r'x')))
            case "untrusted_hash" => String(valid.toRuneArray()[..valid.toRuneArray().size - 1]) +
                ",\"proposalHash\":\"sha256:${String(Array<Rune>(64, repeat: r'0'))}\"}"
            case _ => valid
        }
        File.writeTo(Path(output), body.toArray())
        TeacherProcessResult(0, "provider console ignored")
    }
}

@Test
public class TeacherFailureAssetProviderGeneratorTest {
    @TestCase public func providerGeneratorPinsCodexAndSealsAllThreeLanes(): Unit {
        for (lane in ["knowledge", "skill", "rules"]) {
            let fixture = failureGeneratorFixture("valid-${lane}", lane)
            try {
                let fake = FailureGeneratorFakeExecutor()
                let result = executeTeacherFailureAssetProviderGenerator(fixture.args, executor: fake,
                    codexExecutable: "/fake/codex", timeoutMillis: 4321)
                @Expect(result.ok, true); @Expect(result.diagnostic, "ok"); @Expect(fake.specs.size, 1)
                let spec = fake.specs[0]
                @Expect(spec.executable, "/fake/codex"); @Expect(spec.cwd, fixture.root)
                @Expect(spec.timeoutMillis, 4321); @Expect(spec.args.contains("gpt-5.6-sol"), true)
                @Expect(spec.args.contains("read-only"), true); @Expect(spec.args.contains("--ephemeral"), true)
                @Expect(spec.args.contains("--ignore-user-config"), true); @Expect(spec.args.contains("--ignore-rules"), true)
                @Expect(spec.args.contains("--output-schema"), true); @Expect(spec.args.contains("--output-last-message"), true)
                let response = parseTeacherFailureAssetGenerationResponse(
                    teacherReadUtf8File(fixture.output).trimAscii())
                @Expect(response.lane, lane); @Expect(response.content.contains("中文🙂"), true)
                @Expect(response.proposalHash.startsWith("sha256:"), true)
                @Expect(spec.args[spec.args.size - 1].contains("trusted adapter computes and seals"), true)
                @Expect(spec.args[spec.args.size - 1].contains("at most 1000 UTF-8 bytes"), lane == "rules")
            } finally { failureGeneratorRemove(fixture.root) }
        }
    }

    @TestCase public func providerGeneratorRejectsProcessAndMalformedOutputs(): Unit {
        for ((mode, diagnostic) in [("timeout", "provider_timeout"),
            ("nonzero", "provider_process_failed"), ("missing", "provider_output_missing"),
            ("malformed", "malformed_json"), ("invalid_utf8", "invalid_response_encoding"),
            ("wrong_lane", "lane_mismatch"), ("forbidden", "forbidden_data"),
            ("oversized_rule", "response_contract_invalid")]) {
            let fixture = failureGeneratorFixture("reject-${mode}", "rules")
            try {
                let result = executeTeacherFailureAssetProviderGenerator(fixture.args,
                    executor: FailureGeneratorFakeExecutor(mode: mode),
                    codexExecutable: "/fake/codex", timeoutMillis: 1000)
                @Expect(result.ok, false); @Expect(result.diagnostic, diagnostic)
                @Expect(exists(Path(fixture.output)), false)
            } finally { failureGeneratorRemove(fixture.root) }
        }
    }

    @TestCase public func providerGeneratorRejectsBadHashUnsafePathsAndStrictArguments(): Unit {
        let badHash = failureGeneratorFixture("bad-hash", "rules", failureHash: "bad")
        try {
            let result = executeTeacherFailureAssetProviderGenerator(badHash.args,
                executor: FailureGeneratorFakeExecutor(), codexExecutable: "/fake/codex", timeoutMillis: 1000)
            @Expect(result.diagnostic, "request_contract_invalid"); @Expect(exists(Path(badHash.output)), false)
        } finally { failureGeneratorRemove(badHash.root) }

        let badProposalHash = failureGeneratorFixture("untrusted-proposal-hash", "rules")
        try {
            let result = executeTeacherFailureAssetProviderGenerator(badProposalHash.args,
                executor: FailureGeneratorFakeExecutor(mode: "untrusted_hash"),
                codexExecutable: "/fake/codex", timeoutMillis: 1000)
            @Expect(result.diagnostic, "response_contract_invalid")
            @Expect(exists(Path(badProposalHash.output)), false)
        } finally { failureGeneratorRemove(badProposalHash.root) }

        let duplicate = failureGeneratorFixture("duplicate", "rules")
        try {
            let args = ["--request", duplicate.request, "--request", duplicate.request]
            @Expect(executeTeacherFailureAssetProviderGenerator(args, executor: FailureGeneratorFakeExecutor(),
                codexExecutable: "/fake/codex", timeoutMillis: 1000).diagnostic, "invalid_arguments")
        } finally { failureGeneratorRemove(duplicate.root) }

        let differentParent = failureGeneratorFixture("different-parent", "rules")
        try {
            let other = Path(differentParent.root).join("other")
            Directory.create(other, recursive: true)
            let args = ["--request", differentParent.request, "--output", other.join("response.json").toString()]
            @Expect(executeTeacherFailureAssetProviderGenerator(args, executor: FailureGeneratorFakeExecutor(),
                codexExecutable: "/fake/codex", timeoutMillis: 1000).diagnostic, "adapter_contract_invalid")
        } finally { failureGeneratorRemove(differentParent.root) }
    }
}

private class FailureGeneratorFixture {
    public let root: String
    public let request: String
    public let output: String
    public let args: Array<String>
    public init(root: String, request: String, output: String, args: Array<String>) {
        this.root = root; this.request = request; this.output = output; this.args = args
    }
}

private func failureGeneratorFixture(name: String, lane: String,
    failureHash!: String = String(Array<Rune>(64, repeat: r'a'))): FailureGeneratorFixture {
    let rawRoot = "/tmp/teacher-failure-provider-${name}-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
    Directory.create(Path(rawRoot), recursive: true)
    let root = canonicalize(Path(rawRoot)).toString()
    let request = Path(root).join("request.json").toString()
    let output = Path(root).join("response.json").toString()
    let value = if (failureHash == "bad") {
        "{\"schemaVersion\":\"teacher-failure-asset-generation-request-v1\",\"failureEvidenceHash\":\"bad\",\"classificationEvidenceHash\":\"${String(Array<Rune>(64, repeat: r'b'))}\",\"lane\":\"${lane}\",\"gapDescription\":\"Reusable Unicode边界🙂 gap\"}"
    } else {
        renderTeacherFailureAssetGenerationRequest(TeacherFailureAssetGenerationRequest(failureHash,
            String(Array<Rune>(64, repeat: r'b')), lane, "Reusable Unicode边界🙂 gap"))
    }
    File.writeTo(Path(request), (value + "\n").toArray())
    FailureGeneratorFixture(root, request, output, ["--request", request, "--output", output])
}

private func failureGeneratorTestRequestLane(prompt: String): String {
    for (lane in ["knowledge", "skill", "rules"]) {
        if (prompt.contains("Keep lane exactly ${lane}.")) { return lane }
    }
    ""
}

private func failureGeneratorTestResponse(lane: String): String {
    let title = "Reusable ${lane} guidance"
    let content = "General 中文🙂 ${lane} guidance"
    let trigger = "When the reusable gap is observed"
    let scope = "Cangjie engineering"
    "{\"schemaVersion\":\"teacher-failure-asset-generation-response-v1\",\"lane\":\"${lane}\",\"title\":\"${title}\",\"content\":\"${content}\",\"trigger\":\"${trigger}\",\"scope\":\"${scope}\",\"priority\":100}"
}

private func failureGeneratorRemove(root: String): Unit {
    try { remove(Path(root), recursive: true) } catch (_: Exception) {}
}
