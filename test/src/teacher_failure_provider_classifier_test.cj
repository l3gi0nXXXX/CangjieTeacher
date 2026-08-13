package cangjie_teacher_test

import std.fs.*
import std.time.*
import std.unittest.testmacro.*
import cangjie_teacher.*

private class FailureProviderFake <: TeacherCommandExecutor {
    let mode: String
    let classification: String
    public var observedArgs: Array<String> = Array<String>()
    public init(mode!: String = "ok", classification!: String = failureRulesJson()) {
        this.mode = mode; this.classification = classification
    }
    public func execute(spec: TeacherCommandSpec): TeacherProcessResult {
        observedArgs = spec.args
        if (mode == "timeout") { return TeacherProcessResult(124, "", timedOut: true) }
        if (mode == "nonzero") { return TeacherProcessResult(9, "provider secret must not propagate") }
        if (mode == "large_output") {
            let builder = StringBuilder()
            for (_ in 0..1048577) { builder.append(r'x') }
            return TeacherProcessResult(0, builder.toString())
        }
        if (spec.executable.contains("codex")) {
            var path = ""
            for (i in 0..spec.args.size) {
                if (spec.args[i] == "--output-last-message" && i + 1 < spec.args.size) { path = spec.args[i + 1] }
            }
            if (mode == "invalid_utf8") { File.writeTo(Path(path), [UInt8(0xff), UInt8(0xfe)]) }
            else { _ = teacherAtomicWrite(path, if (mode == "malformed") { "{" } else { classification }) }
            return TeacherProcessResult(0, "ignored")
        }
        let structured = if (mode == "malformed") { "{" } else { classification }
        if (mode == "invalid_utf8") { return TeacherProcessResult(0, "invalid_response_encoding") }
        let terminal = "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false," +
            "\"modelUsage\":{\"GLM-5.2\":{}},\"structured_output\":${structured}}"
        if (mode.startsWith("verbose")) {
            let initModel = if (mode == "verbose_wrong_model") { "wrong-model" } else { "GLM-5.2" }
            let initEvent = "{\"type\":\"system\",\"subtype\":\"init\",\"model\":\"${initModel}\"}"
            if (mode == "verbose_missing_init") {
                return TeacherProcessResult(0, "[{\"type\":\"assistant\"},${terminal}]")
            }
            if (mode == "verbose_duplicate_result") {
                return TeacherProcessResult(0, "[${initEvent},${terminal},${terminal}]")
            }
            return TeacherProcessResult(0,
                "[${initEvent},{\"type\":\"assistant\"},${terminal}]")
        }
        TeacherProcessResult(0, terminal)
    }
}

private func failureRulesJson(): String {
    "{\"gapKind\":\"rules_gap\",\"knowledgeEligible\":false,\"skillEligible\":false," +
        "\"rulesEligible\":true,\"classificationReasonCode\":\"missing_global_invariant\"}"
}
private func failureInfrastructureJson(): String {
    "{\"gapKind\":\"infrastructure_failure\",\"knowledgeEligible\":false,\"skillEligible\":false," +
        "\"rulesEligible\":false,\"classificationReasonCode\":\"infrastructure_only\"}"
}
private func failureLargeRequest(): String {
    let builder = StringBuilder()
    for (_ in 0..262145) { builder.append(r'x') }
    builder.toString()
}
private func failureRequest(): String {
    renderTeacherFailureAssetClassifierRequest(TeacherFailureAssetClassifierRequest(
        "f08453591302a46c4acc04c43d9bdf456679fae27b354bbca7ebecb194c1e773",
        "provider timeout with public trace 中文🙂", "generation did not produce a completion",
        "Cangjie 1.0 public documentation"))
}
private func failureRoot(tag: String): String {
    "/tmp/teacher-failure-provider-${tag}-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
}
private func prepareFailureRoot(tag: String): (String, String, String) {
    let root = failureRoot(tag); Directory.create(Path(root), recursive: true)
    let canonical = canonicalize(Path(root)).toString()
    let request = "${canonical}/request.json"; let output = "${canonical}/response.json"
    _ = teacherAtomicWrite(request, failureRequest() + "\n")
    (canonical, request, output)
}

@Test
public class TeacherFailureProviderClassifierTest {
    @TestCase public func claudeAdapterUsesTenMinuteBudgetAndPersistsTimeoutDiagnostic(): Unit {
        @Expect(FAILURE_CLAUDE_CLASSIFIER_TIMEOUT_MILLIS, 600000)
        let fixture = prepareFailureRoot("claude-timeout-sidecar")
        try {
            @Expect(runTeacherFailureClaudeClassifier(
                ["--request", fixture[1], "--output", fixture[2]],
                executor: FailureProviderFake(mode: "timeout"),
                claudeExecutable: "/fake/claude"), 1)
            @Expect(teacherReadUtf8File("${fixture[0]}/classifier-diagnostic.json"),
                "{\"schemaVersion\":\"cangjie-teacher-classifier-diagnostic-v1\",\"diagnostic\":\"classifier_timeout\"}\n")
            @Expect(exists(Path(fixture[2])), false)
        } finally { try { remove(Path(fixture[0]), recursive: true) } catch (_: Exception) {} }
    }

    @TestCase public func claudeAdapterUsesFrozenSingleTurnStructuredOutputProfile(): Unit {
        let fixture = prepareFailureRoot("claude-profile")
        let provider = FailureProviderFake()
        try {
            @Expect(executeTeacherFailureClaudeClassifier(
                ["--request", fixture[1], "--output", fixture[2]],
                executor: provider, claudeExecutable: "/fake/claude",
                timeoutMillis: 1000).ok, true)
            for (value in ["--bare", "--tools", "--disable-slash-commands",
                "--setting-sources", "--max-turns", "1", "--verbose",
                "--no-session-persistence", "--output-format", "json",
                "--strict-mcp-config", "--json-schema",
                "--dangerously-skip-permissions"]) {
                @Expect(provider.observedArgs.contains(value), true)
            }
            @Expect(provider.observedArgs.contains("--effort"), false)
            let prompt = provider.observedArgs[1]
            for (mapping in ["knowledge_gap/missing_versioned_fact",
                "procedure_gap/missing_reusable_procedure", "rules_gap/missing_global_invariant",
                "combined gap and multiple_reusable_gaps", "infrastructure_failure/infrastructure_only"]) {
                @Expect(prompt.contains(mapping), true)
            }
        } finally { try { remove(Path(fixture[0]), recursive: true) } catch (_: Exception) {} }
    }

    @TestCase public func claudeAdapterAcceptsVerboseJsonArrayWithBoundInitAndTerminal(): Unit {
        let fixture = prepareFailureRoot("claude-verbose-array")
        try {
            let result = executeTeacherFailureClaudeClassifier(
                ["--request", fixture[1], "--output", fixture[2]],
                executor: FailureProviderFake(mode: "verbose"), claudeExecutable: "/fake/claude",
                timeoutMillis: 1000)
            @Expect(result.ok, true)
            @Expect(result.diagnostic, "ok")
            @Expect(parseTeacherFailureAssetClassifierResponse(
                teacherReadUtf8File(fixture[2]).trimAscii()).gapKind, "rules_gap")
        } finally { try { remove(Path(fixture[0]), recursive: true) } catch (_: Exception) {} }
    }

    @TestCase public func claudeVerboseJsonArrayFailsClosedWithoutUniqueBoundEvidence(): Unit {
        for ((mode, expected) in [
            ("verbose_wrong_model", "observed_model_mismatch"),
            ("verbose_missing_init", "missing_init"),
            ("verbose_duplicate_result", "missing_or_duplicate_terminal_result")
        ]) {
            let fixture = prepareFailureRoot("claude-${mode}")
            try {
                let result = executeTeacherFailureClaudeClassifier(
                    ["--request", fixture[1], "--output", fixture[2]],
                    executor: FailureProviderFake(mode: mode), claudeExecutable: "/fake/claude",
                    timeoutMillis: 1000)
                @Expect(result.ok, false)
                @Expect(result.diagnostic, expected)
                @Expect(exists(Path(fixture[2])), false)
            } finally { try { remove(Path(fixture[0]), recursive: true) } catch (_: Exception) {} }
        }
    }

    @TestCase public func codexAndClaudeSealCanonicalRulesAndInfrastructure(): Unit {
        let a = prepareFailureRoot("valid-codex")
        let b = prepareFailureRoot("valid-claude")
        try {
            let codex = executeTeacherFailureCodexClassifier(["--request", a[1], "--output", a[2]],
                executor: FailureProviderFake(), codexExecutable: "/fake/codex", timeoutMillis: 1000)
            @Expect(codex.ok, true); @Expect(codex.diagnostic, "ok")
            let codexRaw = teacherReadUtf8File(a[2]).trimAscii()
            let codexParsed = parseTeacherFailureAssetClassifierResponse(codexRaw)
            @Expect(codexParsed.gapKind, "rules_gap")
            @Expect(codexRaw, renderTeacherFailureAssetClassifierResponse(codexParsed))

            let claude = executeTeacherFailureClaudeClassifier(["--output", b[2], "--request", b[1]],
                executor: FailureProviderFake(classification: failureInfrastructureJson()),
                claudeExecutable: "/fake/claude", timeoutMillis: 1000)
            @Expect(claude.ok, true); @Expect(claude.diagnostic, "ok")
            let claudeRaw = teacherReadUtf8File(b[2]).trimAscii()
            let claudeParsed = parseTeacherFailureAssetClassifierResponse(claudeRaw)
            @Expect(claudeParsed.gapKind, "infrastructure_failure")
            @Expect(claudeRaw, renderTeacherFailureAssetClassifierResponse(claudeParsed))
        } finally {
            try { remove(Path(a[0]), recursive: true) } catch (_: Exception) {}
            try { remove(Path(b[0]), recursive: true) } catch (_: Exception) {}
        }
    }

    @TestCase public func argumentsRejectMissingDuplicateUnknownAndRelativePaths(): Unit {
        let fixture = prepareFailureRoot("arguments")
        try {
            for (args in [
                ["--request", fixture[1]],
                ["--request", fixture[1], "--request", fixture[1]],
                ["--request", fixture[1], "--unknown", fixture[2]],
                ["--request", "request.json", "--output", "response.json"]
            ]) {
                @Expect(executeTeacherFailureCodexClassifier(args, executor: FailureProviderFake(),
                    codexExecutable: "/fake/codex", timeoutMillis: 1000).ok, false)
                @Expect(executeTeacherFailureClaudeClassifier(args, executor: FailureProviderFake(),
                    claudeExecutable: "/fake/claude", timeoutMillis: 1000).ok, false)
            }
            let outside = "${fixture[0]}-outside.json"
            @Expect(executeTeacherFailureCodexClassifier(["--request", fixture[1], "--output", outside],
                executor: FailureProviderFake(), codexExecutable: "/fake/codex", timeoutMillis: 1000).diagnostic,
                "adapter_path_invalid")
            @Expect(executeTeacherFailureClaudeClassifier(["--request", fixture[1], "--output", outside],
                executor: FailureProviderFake(), claudeExecutable: "/fake/claude", timeoutMillis: 1000).diagnostic,
                "adapter_path_invalid")
        } finally { try { remove(Path(fixture[0]), recursive: true) } catch (_: Exception) {} }
    }

    @TestCase public func providersFailClosedForTransportAndEncodingErrors(): Unit {
        for (provider in ["codex", "claude"]) {
            for (mode in ["timeout", "nonzero", "malformed", "invalid_utf8"]) {
                let fixture = prepareFailureRoot("${provider}-${mode}")
                try {
                    let result = if (provider == "codex") {
                        executeTeacherFailureCodexClassifier(["--request", fixture[1], "--output", fixture[2]],
                            executor: FailureProviderFake(mode: mode), codexExecutable: "/fake/codex", timeoutMillis: 1000)
                    } else {
                        executeTeacherFailureClaudeClassifier(["--request", fixture[1], "--output", fixture[2]],
                            executor: FailureProviderFake(mode: mode), claudeExecutable: "/fake/claude", timeoutMillis: 1000)
                    }
                    @Expect(result.ok, false)
                    @Expect(exists(Path(fixture[2])), false)
                } finally { try { remove(Path(fixture[0]), recursive: true) } catch (_: Exception) {} }
            }
        }
    }

    @TestCase public func claudeVerboseOutputRetainsControlledOneMegabyteLimit(): Unit {
        let fixture = prepareFailureRoot("claude-large-output")
        try {
            let result = executeTeacherFailureClaudeClassifier(
                ["--request", fixture[1], "--output", fixture[2]],
                executor: FailureProviderFake(mode: "large_output"), claudeExecutable: "/fake/claude",
                timeoutMillis: 1000)
            @Expect(result.ok, false)
            @Expect(result.diagnostic, "classifier_output_too_large")
            @Expect(exists(Path(fixture[2])), false)
        } finally { try { remove(Path(fixture[0]), recursive: true) } catch (_: Exception) {} }
    }

    @TestCase public func requestEncodingSizeSecretAndCaseLeakageFailClosed(): Unit {
        for ((tag, body, expected) in [
            ("secret", failureRequest().replace("provider timeout", "token=secret"), "request_contract_invalid"),
            ("case", failureRequest().replace("provider timeout", "CJ-HUMANEVAL-077"), "request_contract_invalid"),
            ("large", failureLargeRequest(), "request_too_large")
        ]) {
            let fixture = prepareFailureRoot("request-${tag}")
            try {
                _ = teacherAtomicWrite(fixture[1], body)
                @Expect(executeTeacherFailureCodexClassifier(["--request", fixture[1], "--output", fixture[2]],
                    executor: FailureProviderFake(), codexExecutable: "/fake/codex", timeoutMillis: 1000).diagnostic,
                    expected)
                @Expect(executeTeacherFailureClaudeClassifier(["--request", fixture[1], "--output", fixture[2]],
                    executor: FailureProviderFake(), claudeExecutable: "/fake/claude", timeoutMillis: 1000).diagnostic,
                    expected)
            } finally { try { remove(Path(fixture[0]), recursive: true) } catch (_: Exception) {} }
        }
        let invalid = prepareFailureRoot("request-encoding")
        try {
            File.writeTo(Path(invalid[1]), [UInt8(0xff), UInt8(0xfe)])
            @Expect(executeTeacherFailureCodexClassifier(["--request", invalid[1], "--output", invalid[2]],
                executor: FailureProviderFake(), codexExecutable: "/fake/codex", timeoutMillis: 1000).diagnostic,
                "invalid_request_encoding")
            @Expect(executeTeacherFailureClaudeClassifier(["--request", invalid[1], "--output", invalid[2]],
                executor: FailureProviderFake(), claudeExecutable: "/fake/claude", timeoutMillis: 1000).diagnostic,
                "invalid_request_encoding")
        } finally { try { remove(Path(invalid[0]), recursive: true) } catch (_: Exception) {} }
    }

    @TestCase public func forbiddenAndNonCanonicalResponsesAreRejected(): Unit {
        for (bad in [
            "{\"gapKind\":\"rules_gap\",\"knowledgeEligible\":false,\"skillEligible\":false,\"rulesEligible\":true,\"classificationReasonCode\":\"token=secret\"}",
            "{\"gapKind\":\"rules_gap\",\"knowledgeEligible\":false,\"skillEligible\":false,\"rulesEligible\":true,\"classificationReasonCode\":\"/home/private\"}",
            "{\"gapKind\":\"rules_gap\",\"knowledgeEligible\":false,\"skillEligible\":false,\"rulesEligible\":true,\"classificationReasonCode\":\"Authorization header\"}",
            "{\"gapKind\":\"rules_gap\",\"knowledgeEligible\":false,\"skillEligible\":false,\"rulesEligible\":true,\"classificationReasonCode\":\"api_key value\"}",
            "{\"gapKind\":\"rules_gap\",\"knowledgeEligible\":false,\"skillEligible\":false,\"rulesEligible\":true,\"classificationReasonCode\":\"hidden-test detail\"}",
            "{\"gapKind\":\"rules_gap\",\"knowledgeEligible\":false,\"skillEligible\":false,\"rulesEligible\":true,\"classificationReasonCode\":\"reference solution detail\"}",
            "{\"gapKind\":\"rules_gap\",\"knowledgeEligible\":false,\"skillEligible\":false,\"rulesEligible\":false,\"classificationReasonCode\":\"missing_global_invariant\"}"
        ]) {
            let a = prepareFailureRoot("bad-codex")
            let b = prepareFailureRoot("bad-claude")
            try {
                @Expect(executeTeacherFailureCodexClassifier(["--request", a[1], "--output", a[2]],
                    executor: FailureProviderFake(classification: bad), codexExecutable: "/fake/codex",
                    timeoutMillis: 1000).ok, false)
                @Expect(executeTeacherFailureClaudeClassifier(["--request", b[1], "--output", b[2]],
                    executor: FailureProviderFake(classification: bad), claudeExecutable: "/fake/claude",
                    timeoutMillis: 1000).ok, false)
            } finally {
                try { remove(Path(a[0]), recursive: true) } catch (_: Exception) {}
                try { remove(Path(b[0]), recursive: true) } catch (_: Exception) {}
            }
        }
    }
}
