package cangjie_teacher

import std.collection.*
import std.env.getVariables
import std.fs.*
import std.io.StringReader
import std.process.*
import std.sort.*
import std.time.*
import std.core.StringBuilder
import stdx.crypto.digest.SHA256
import stdx.encoding.json.*

private let STUDENT_VALIDATION_RESPONSE_MAX_BYTES: Int64 = 1048576

public class TeacherValidationIdentity {
    public let provider: String
    public let modelVersion: String
    public let claudeCodeVersion: String
    public let runtimeExecutableHash: String
    public let completionControlHash: String
    public let providerPromptCapabilityHash: String
    public let identityHash: String
    public init(provider: String, modelVersion: String, claudeCodeVersion: String,
        runtimeExecutableHash: String, completionControlHash: String,
        providerPromptCapabilityHash: String, identityHash: String) {
        this.provider = provider; this.modelVersion = modelVersion
        this.claudeCodeVersion = claudeCodeVersion
        this.runtimeExecutableHash = runtimeExecutableHash
        this.completionControlHash = completionControlHash
        this.providerPromptCapabilityHash = providerPromptCapabilityHash
        this.identityHash = identityHash
    }
}

public class TeacherStudentCompletionControl {
    public let certificationTransport: String
    public let generationProtocol: String
    public let samplesPerCase: Int64
    public let outputSchemaHash: String
    public let samplingCapabilityHash: String
    public let effectivePromptByteBudget: Int64
    public let transportRetryBudget: Int64
    public let modelTimeoutSeconds: Int64
    public let runtimeConfigHash: String
    public let completionCommandHash: String
    public init(certificationTransport: String, generationProtocol: String, samplesPerCase: Int64,
        outputSchemaHash: String, samplingCapabilityHash: String, effectivePromptByteBudget: Int64,
        transportRetryBudget: Int64, modelTimeoutSeconds: Int64, runtimeConfigHash: String,
        completionCommandHash: String) {
        this.certificationTransport = certificationTransport
        this.generationProtocol = generationProtocol; this.samplesPerCase = samplesPerCase
        this.outputSchemaHash = outputSchemaHash; this.samplingCapabilityHash = samplingCapabilityHash
        this.effectivePromptByteBudget = effectivePromptByteBudget
        this.transportRetryBudget = transportRetryBudget; this.modelTimeoutSeconds = modelTimeoutSeconds
        this.runtimeConfigHash = runtimeConfigHash; this.completionCommandHash = completionCommandHash
    }
}

public func renderTeacherStudentCompletionControl(value: TeacherStudentCompletionControl): String {
    if (!teacherValidationLabel(value.certificationTransport) ||
        value.generationProtocol != "completion-only-v1" || value.samplesPerCase != 1 ||
        !teacherValidationHash(value.outputSchemaHash) ||
        !teacherValidationHash(value.samplingCapabilityHash) ||
        value.effectivePromptByteBudget < 1 || value.transportRetryBudget != 0 ||
        value.modelTimeoutSeconds < 1 || value.modelTimeoutSeconds > 3600 ||
        !teacherValidationHash(value.runtimeConfigHash) ||
        !teacherValidationHash(value.completionCommandHash)) {
        throw IllegalArgumentException("student_completion_control_invalid")
    }
    "{\"schemaVersion\":\"ckb-student-completion-control-v1\"," +
        "\"certificationTransport\":\"${value.certificationTransport}\"," +
        "\"generationProtocol\":\"${value.generationProtocol}\",\"samplesPerCase\":${value.samplesPerCase}," +
        "\"outputSchemaHash\":\"${value.outputSchemaHash}\"," +
        "\"samplingCapabilityHash\":\"${value.samplingCapabilityHash}\"," +
        "\"effectivePromptByteBudget\":${value.effectivePromptByteBudget}," +
        "\"transportRetryBudget\":${value.transportRetryBudget}," +
        "\"modelTimeoutSeconds\":${value.modelTimeoutSeconds}," +
        "\"runtimeConfigHash\":\"${value.runtimeConfigHash}\"," +
        "\"completionCommandHash\":\"${value.completionCommandHash}\"}\n"
}

private func teacherValidationInt(value: JsonObject, name: String): Int64 {
    match (value.get(name)) { case Some(v) => v.asInt().getValue(); case None => Int64(-1) }
}

public func parseTeacherStudentCompletionControl(raw: String): TeacherStudentCompletionControl {
    try {
        let object = JsonValue.fromStr(raw).asObject()
        if (object.getFields().size != 11 || teacherValidationString(object, "schemaVersion") !=
            "ckb-student-completion-control-v1") {
            throw IllegalArgumentException("student_completion_control_invalid")
        }
        let value = TeacherStudentCompletionControl(
            teacherValidationString(object, "certificationTransport"),
            teacherValidationString(object, "generationProtocol"),
            teacherValidationInt(object, "samplesPerCase"),
            teacherValidationString(object, "outputSchemaHash"),
            teacherValidationString(object, "samplingCapabilityHash"),
            teacherValidationInt(object, "effectivePromptByteBudget"),
            teacherValidationInt(object, "transportRetryBudget"),
            teacherValidationInt(object, "modelTimeoutSeconds"),
            teacherValidationString(object, "runtimeConfigHash"),
            teacherValidationString(object, "completionCommandHash"))
        if (raw != renderTeacherStudentCompletionControl(value)) {
            throw IllegalArgumentException("student_completion_control_invalid")
        }
        value
    } catch (e: IllegalArgumentException) { throw e }
    catch (_: Exception) { throw IllegalArgumentException("student_completion_control_invalid") }
}

private func teacherStudentShellQuote(value: String): String {
    "'" + value.replace("'", "'\\''") + "'"
}

private func teacherStudentSandboxLiteral(value: String): String {
    value.replace("\\", "\\\\").replace("\"", "\\\"")
}

private func teacherStudentSandboxMetadataAncestors(value: String): String {
    var current = Path(value).parent
    var out = ""
    while (current.toString() != "/" && current.toString() != "." &&
        !current.toString().isEmpty()) {
        out = " (literal \"${teacherStudentSandboxLiteral(current.toString())}\")" + out
        current = current.parent
    }
    out
}

public func teacherStudentSandboxProfile(runRoot: String, runtime: String): String {
    let root = teacherStudentSandboxLiteral(runRoot)
    let executable = teacherStudentSandboxLiteral(runtime)
    let metadata = teacherStudentSandboxMetadataAncestors(runRoot) +
        teacherStudentSandboxMetadataAncestors(runtime)
    "(version 1)\n(import \"system.sb\")\n(deny default)\n" +
        "(allow process*)\n(allow sysctl-read)\n(allow mach-lookup)\n(allow network*)\n" +
        "(allow file-read-metadata${metadata} (subpath \"${root}\") (literal \"${executable}\") " +
        "(literal \"/dev\") (literal \"/dev/fd\") (literal \"/dev/fd/0\") " +
        "(literal \"/dev/stdin\"))\n" +
        "(allow file-read* (subpath \"${root}\") (literal \"${executable}\") " +
        "(literal \"/dev/fd/0\") (literal \"/dev/stdin\"))\n" +
        "(allow file-write* (subpath \"${root}\"))\n"
}

// The hash and the launched command share this builder; placeholder paths reproduce CKB bytes.
public func teacherStudentCompletionOutputSchema(): String {
    "{\"type\":\"object\",\"additionalProperties\":false," +
        "\"required\":[\"solution_cj\"],\"properties\":{\"solution_cj\":{\"type\":\"string\"}}}"
}

public func teacherStudentCompletionCommand(groupRoot: String, runtimeHome: String,
    profile: String, runtime: String, model: String, transcript: String, stderr: String): String {
    let schema = teacherStudentCompletionOutputSchema()
    let command = "session_id=$(uuidgen | tr '[:upper:]' '[:lower:]'); printf '%s' \"$session_id\" > " +
        teacherStudentShellQuote("${groupRoot}/session-id.attempt-1.txt") + "; HOME=" +
        teacherStudentShellQuote(runtimeHome) + " PATH=" + teacherStudentShellQuote("${runtimeHome}/bin") +
        ":\"$PATH\" TMPDIR=" + teacherStudentShellQuote("${runtimeHome}/tmp") +
        " CLAUDE_CODE_TMPDIR=" + teacherStudentShellQuote("${runtimeHome}/tmp") +
        " CLAUDE_TMPDIR=" + teacherStudentShellQuote("${runtimeHome}/tmp") +
        " XDG_CONFIG_HOME=" + teacherStudentShellQuote("${runtimeHome}/xdg-config") +
        " XDG_CACHE_HOME=" + teacherStudentShellQuote("${runtimeHome}/xdg-cache") +
        " CLAUDE_CONFIG_DIR=" + teacherStudentShellQuote("${runtimeHome}/claude-config") +
        " ANTHROPIC_AUTH_TOKEN=\"$GLM_API_KEY\" ANTHROPIC_BASE_URL=\"$GLM_BASE_URL\"" +
        " ANTHROPIC_MODEL=" + teacherStudentShellQuote(model) +
        " ANTHROPIC_MAX_RETRIES=0 CLAUDE_CODE_MAX_RETRIES=0 sandbox-exec -f " +
        teacherStudentShellQuote(profile) + " " + teacherStudentShellQuote(runtime) +
        " -p --bare --tools '' --disable-slash-commands --setting-sources '' --max-turns 1" +
        " --verbose --no-session-persistence --session-id \"$session_id\" --model " +
        teacherStudentShellQuote(model) + " --output-format json --strict-mcp-config --mcp-config " +
        teacherStudentShellQuote("${runtimeHome}/mcp-config.json") + " --json-schema " +
        teacherStudentShellQuote(schema) + " --dangerously-skip-permissions < " +
        teacherStudentShellQuote("${runtimeHome}/prompt.final.md") + " > " +
        teacherStudentShellQuote(transcript) + " 2> " + teacherStudentShellQuote(stderr)
    command
}

// Byte-for-byte semantic counterpart of CKB ckbStudentCompletionCommandHash.
public func teacherStudentCompletionCommandHash(model: String): String {
    let command = teacherStudentCompletionCommand("/CKB/GROUP", "/CKB/HOME",
        "/CKB/PROFILE", "/CKB/RUNTIME", model, "/CKB/TRANSCRIPT", "/CKB/STDERR")
    "sha256:${teacherStableHash(command)}"
}

private func teacherValidationIdentityEvidence(value: TeacherValidationIdentity): String {
    "{\"schemaVersion\":\"ckb-student-validation-provider-identity-v1\",\"provider\":\"${value.provider}\"," +
        "\"model\":\"${value.modelVersion}\",\"claudeCodeVersion\":\"${value.claudeCodeVersion}\"," +
        "\"runtimeExecutableHash\":\"${value.runtimeExecutableHash}\"," +
        "\"completionControlHash\":\"${value.completionControlHash}\"," +
        "\"providerPromptCapabilityHash\":\"${value.providerPromptCapabilityHash}\"}\n"
}

private func teacherValidationHash(value: String): Bool {
    let runes = value.toRuneArray()
    if (!value.startsWith("sha256:") || runes.size != 71) { return false }
    for (rune in runes[7..]) {
        if (!((rune >= r'0' && rune <= r'9') || (rune >= r'a' && rune <= r'f'))) { return false }
    }
    true
}

private func teacherValidationLabel(value: String): Bool {
    if (value.isEmpty() || value.toRuneArray().size > 128) { return false }
    for (rune in value.toRuneArray()) {
        if (!((rune >= r'a' && rune <= r'z') || (rune >= r'A' && rune <= r'Z') ||
            (rune >= r'0' && rune <= r'9') || rune == r'.' || rune == r'-' || rune == r'_' ||
            rune == r'/' || rune == r'+')) { return false }
    }
    true
}

public func sealTeacherValidationIdentity(provider: String, modelVersion: String,
    claudeCodeVersion: String, runtimeExecutableHash: String, completionControlHash: String,
    providerPromptCapabilityHash: String): TeacherValidationIdentity {
    let provisional = TeacherValidationIdentity(provider, modelVersion, claudeCodeVersion,
        runtimeExecutableHash, completionControlHash, providerPromptCapabilityHash, "")
    if (!teacherValidationLabel(provider) || !teacherValidationLabel(modelVersion) ||
        !teacherValidationLabel(claudeCodeVersion) || !teacherValidationHash(runtimeExecutableHash) ||
        !teacherValidationHash(completionControlHash) ||
        !teacherValidationHash(providerPromptCapabilityHash)) {
        throw IllegalArgumentException("student_validation_identity_invalid")
    }
    TeacherValidationIdentity(provider, modelVersion, claudeCodeVersion, runtimeExecutableHash,
        completionControlHash, providerPromptCapabilityHash,
        "sha256:${teacherStableHash(teacherValidationIdentityEvidence(provisional))}")
}

public func renderTeacherValidationIdentity(value: TeacherValidationIdentity): String {
    let sealed = sealTeacherValidationIdentity(value.provider, value.modelVersion,
        value.claudeCodeVersion, value.runtimeExecutableHash, value.completionControlHash,
        value.providerPromptCapabilityHash)
    if (value.identityHash != sealed.identityHash) {
        throw IllegalArgumentException("student_validation_identity_invalid")
    }
    teacherValidationIdentityEvidence(value)
}

private func teacherValidationString(value: JsonObject, name: String): String {
    match (value.get(name)) { case Some(v) => v.asString().getValue(); case None => "" }
}

public func parseTeacherValidationIdentity(raw: String): TeacherValidationIdentity {
    try {
        let object = JsonValue.fromStr(raw).asObject()
        if (object.getFields().size != 7 || teacherValidationString(object, "schemaVersion") !=
            "ckb-student-validation-provider-identity-v1") {
            throw IllegalArgumentException("student_validation_identity_invalid")
        }
        let value = TeacherValidationIdentity(teacherValidationString(object, "provider"),
            teacherValidationString(object, "model"),
            teacherValidationString(object, "claudeCodeVersion"),
            teacherValidationString(object, "runtimeExecutableHash"),
            teacherValidationString(object, "completionControlHash"),
            teacherValidationString(object, "providerPromptCapabilityHash"), "")
        let sealed = sealTeacherValidationIdentity(value.provider, value.modelVersion,
            value.claudeCodeVersion, value.runtimeExecutableHash, value.completionControlHash,
            value.providerPromptCapabilityHash)
        if (raw != renderTeacherValidationIdentity(sealed)) {
            throw IllegalArgumentException("student_validation_identity_invalid")
        }
        sealed
    } catch (e: IllegalArgumentException) { throw e }
    catch (_: Exception) { throw IllegalArgumentException("student_validation_identity_invalid") }
}

public class TeacherAssetValidationTarget {
    public let lane: String
    public let candidateVisibleProjection: String
    public let candidateProjectionHash: String
    public let baseCompositeHash: String
    public let identity: TeacherValidationIdentity
    public init(lane: String, candidateVisibleProjection: String, candidateProjectionHash: String,
        baseCompositeHash: String, identity: TeacherValidationIdentity) {
        this.lane = lane; this.candidateVisibleProjection = candidateVisibleProjection
        this.candidateProjectionHash = candidateProjectionHash
        this.baseCompositeHash = baseCompositeHash; this.identity = identity
    }
}

public func buildTeacherAssetValidationTarget(lane: String, candidateVisibleProjection: String,
    baseCompositeHash: String, identity: TeacherValidationIdentity): TeacherAssetValidationTarget {
    if (!["rules", "skills"].contains(lane) || candidateVisibleProjection.isEmpty() ||
        candidateVisibleProjection.toArray().size > 32768 ||
        !(baseCompositeHash == "none" || teacherValidationHash(baseCompositeHash))) {
        throw IllegalArgumentException("candidate_test_evidence_invalid")
    }
    _ = renderTeacherValidationIdentity(identity)
    TeacherAssetValidationTarget(lane, candidateVisibleProjection,
        "sha256:${teacherStableHash(candidateVisibleProjection)}", baseCompositeHash, identity)
}

public class TeacherAssetFixture {
    public let fixtureId: String
    public let kind: String
    public let sourceClass: String
    public let content: String
    public let expectedEvidence: String
    public init(fixtureId: String, kind: String, sourceClass: String, content: String,
        expectedEvidence: String) {
        this.fixtureId = fixtureId; this.kind = kind; this.sourceClass = sourceClass
        this.content = content; this.expectedEvidence = expectedEvidence
    }
}

public class TeacherAssetFixtureExecution {
    public let fixture: TeacherAssetFixture
    public let fixtureHash: String
    public let executorKind: String
    public let providerIdentityHash: String
    public let modelVersion: String
    public let actualEvidence: String
    public let transcriptHash: String
    public let exitCode: Int64
    public let passed: Bool
    public let transcript: String
    public init(fixture: TeacherAssetFixture, fixtureHash: String, executorKind: String,
        providerIdentityHash: String, modelVersion: String, actualEvidence: String,
        transcriptHash: String, exitCode: Int64, passed: Bool, transcript!: String = "") {
        this.fixture = fixture; this.fixtureHash = fixtureHash; this.executorKind = executorKind
        this.providerIdentityHash = providerIdentityHash; this.modelVersion = modelVersion
        this.actualEvidence = actualEvidence; this.transcriptHash = transcriptHash
        this.exitCode = exitCode; this.passed = passed; this.transcript = transcript
    }
}

public interface TeacherAssetFixtureExecutor {
    func executorKind(): String
    func providerIdentityHash(): String
    func modelVersion(): String
    func validationIdentity(): TeacherValidationIdentity
    func execute(target: TeacherAssetValidationTarget,
        fixture: TeacherAssetFixture): (Int64, String, String)
}

public class FakeTeacherAssetFixtureExecutor <: TeacherAssetFixtureExecutor {
    private let identity = sealTeacherValidationIdentity("scaffold", "fake-scaffold-v1", "scaffold",
        "sha256:${teacherStableHash("fake-contract-runtime")}",
        "sha256:${teacherStableHash("fake-contract-control")}",
        "sha256:${teacherStableHash("fake-contract-prompt")}")
    public func executorKind(): String { "fake_contract" }
    public func providerIdentityHash(): String { "sha256:${teacherStableHash("fake-contract-provider")}" }
    public func modelVersion(): String { "fake-scaffold-v1" }
    public func validationIdentity(): TeacherValidationIdentity { identity }
    public func execute(target: TeacherAssetValidationTarget,
        fixture: TeacherAssetFixture): (Int64, String, String) {
        (0, fixture.expectedEvidence, "fake execution completed for ${fixture.kind}")
    }
}

private func teacherStudentProcessSafe(value: String, limit: Int64): Bool {
    if (value.isEmpty() || value.toArray().size > limit) { return false }
    let lower = value.toAsciiLower()
    for (marker in ["cj-humaneval-", "hidden_test", "reference solution", "/users/",
        "/home/", "/private/", "authorization", "token=", "password="]) {
        if (lower.contains(marker)) { return false }
    }
    true
}

private func teacherStudentEscape(value: String): String {
    value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
        .replace("\r", "\\r").replace("\t", "\\t")
}

private func teacherStudentPrompt(fixture: TeacherAssetFixture,
    target: TeacherAssetValidationTarget): String {
    if (!teacherStudentProcessSafe(target.candidateVisibleProjection, 32768) ||
        !teacherStudentProcessSafe(fixture.content, 8192)) {
        throw IllegalArgumentException("candidate_test_evidence_invalid")
    }
    "Use only the supplied candidate context to complete this independent non-HumanEval fixture. " +
        "Do not use tools, settings, hidden tests, reference solutions, or user configuration. " +
        "Return exactly one JSON object with only the string field actualEvidence. " +
        "Set actualEvidence to only the exact evidence token requested by input; do not add explanations, " +
        "punctuation, prefixes, or suffixes. Request: " +
        "{\"schemaVersion\":\"teacher-student-non-humaneval-request-v1\"," +
        "\"fixtureId\":\"${fixture.fixtureId}\",\"fixtureHash\":\"${teacherAssetFixtureHash(fixture)}\"," +
        "\"lane\":\"${target.lane}\",\"candidateVisibleHash\":\"${target.candidateProjectionHash}\"," +
        "\"candidateVisibleProjection\":\"${teacherStudentEscape(target.candidateVisibleProjection)}\"," +
        "\"baseCompositeHash\":\"${target.baseCompositeHash}\"," +
        "\"validationIdentityHash\":\"${target.identity.identityHash}\"," +
        "\"input\":\"${teacherStudentEscape(fixture.content)}\"}"
}

private func teacherStudentExecutableSafe(value: String): Bool {
    let path = Path(value)
    if (!path.isAbsolute() || !exists(path) || value.contains("\n") || value.contains("\r") ||
        value.split("/").contains("..")) { return false }
    try {
        !FileInfo(path).isSymbolicLink() && FileInfo(path).isRegular() &&
            canonicalize(path).toString() == value
    } catch (_: Exception) { false }
}

public func teacherValidationExecutableHash(value: String): String {
    let digest = SHA256()
    try { digest.write(File.readFrom(Path(value))) }
    catch (_: Exception) { throw IllegalArgumentException("student_validation_identity_invalid") }
    let out = StringBuilder()
    for (byte in digest.finish()) {
        let hi = byte / UInt8(16); let lo = byte % UInt8(16)
        out.append(if (hi < UInt8(10)) { "${hi}" } else {
            ["a", "b", "c", "d", "e", "f"][Int64(hi - UInt8(10))]
        })
        out.append(if (lo < UInt8(10)) { "${lo}" } else {
            ["a", "b", "c", "d", "e", "f"][Int64(lo - UInt8(10))]
        })
    }
    "sha256:${out.toString()}"
}

public class TeacherStudentRuntimeSpec {
    public let executable: String; public let args: Array<String>; public let cwd: String
    public let env: Array<(String, String)>; public let timeoutMillis: Int64
    public init(executable: String, args: Array<String>, cwd: String,
        env: Array<(String, String)>, timeoutMillis: Int64) {
        this.executable = executable; this.args = args; this.cwd = cwd
        this.env = env; this.timeoutMillis = timeoutMillis
    }
}

public class TeacherStudentRuntimeResult {
    public let exitCode: Int64; public let stdout: String; public let stderr: String
    public let timedOut: Bool
    public init(exitCode: Int64, stdout: String, stderr: String, timedOut!: Bool = false) {
        this.exitCode = exitCode; this.stdout = stdout; this.stderr = stderr; this.timedOut = timedOut
    }
}

public interface TeacherStudentRuntimeExecutor {
    func execute(spec: TeacherStudentRuntimeSpec): TeacherStudentRuntimeResult
}

// Dedicated capture keeps provider stderr out of the strict stdout JSON protocol.
public class NativeTeacherStudentRuntimeExecutor <: TeacherStudentRuntimeExecutor {
    public func execute(spec: TeacherStudentRuntimeSpec): TeacherStudentRuntimeResult {
        let environment = HashMap<String, String>()
        for ((key, value) in getVariables()) { environment[key] = value }
        for (entry in spec.env) { environment[entry[0]] = entry[1] }
        try {
            let process = launch(spec.executable, spec.args, stdOut: ProcessRedirect.Pipe,
                stdErr: ProcessRedirect.Pipe, workingDirectory: Some(Path(spec.cwd)),
                environment: Some(environment))
            let stdout = spawn { try { StringReader(process.stdOutPipe).readToEnd() }
                catch (_: Exception) { "invalid_response_encoding" } }
            let stderr = spawn { try { StringReader(process.stdErrPipe).readToEnd() }
                catch (_: Exception) { "invalid_response_encoding" } }
            try {
                let code = process.wait(timeout: Some(Duration.millisecond * spec.timeoutMillis))
                TeacherStudentRuntimeResult(code, stdout.get(), stderr.get())
            } catch (_: TimeoutException) {
                try { process.terminate(force: true) } catch (_: Exception) {}
                try { _ = stdout.get(); _ = stderr.get() } catch (_: Exception) {}
                TeacherStudentRuntimeResult(124, "", "", timedOut: true)
            }
        } catch (_: Exception) { TeacherStudentRuntimeResult(127, "", "") }
    }
}

private func teacherStudentClaudeTerminal(raw: String): JsonObject {
    let value = JsonValue.fromStr(raw)
    try { return value.asObject() } catch (_: Exception) {}
    let items = try { value.asArray().getItems() }
        catch (_: Exception) { throw IllegalArgumentException("candidate_test_evidence_invalid") }
    var terminal: Option<JsonObject> = None
    for (index in 0..items.size) {
        let item = try { items[index].asObject() }
            catch (_: Exception) { throw IllegalArgumentException("candidate_test_evidence_invalid") }
        if (teacherValidationString(item, "type") != "result") { continue }
        match (terminal) {
            case Some(_) => throw IllegalArgumentException("candidate_test_evidence_invalid")
            case None => ()
        }
        if (index != items.size - 1) {
            throw IllegalArgumentException("candidate_test_evidence_invalid")
        }
        terminal = Some<JsonObject>(item)
    }
    match (terminal) {
        case Some(item) => item
        case None => throw IllegalArgumentException("candidate_test_evidence_invalid")
    }
}

private func teacherStudentClaudeSolution(raw: String, model: String): String {
    try {
        let terminal = teacherStudentClaudeTerminal(raw)
        if (teacherValidationString(terminal, "type") != "result" ||
            teacherValidationString(terminal, "subtype") != "success") {
            throw IllegalArgumentException("candidate_test_evidence_invalid")
        }
        let isError = match (terminal.get("is_error")) {
            case Some(value) => value.asBool().getValue()
            case None => true
        }
        if (isError) { throw IllegalArgumentException("candidate_test_evidence_invalid") }
        let usage = terminal.get("modelUsage").getOrThrow().asObject()
        let observedModel = match (usage.get(model)) { case Some(_) => true; case None => false }
        if (usage.getFields().size != 1 || !observedModel) {
            throw IllegalArgumentException("student_validation_identity_mismatch")
        }
        let structured = terminal.get("structured_output").getOrThrow().asObject()
        if (structured.getFields().size != 1) {
            throw IllegalArgumentException("candidate_test_evidence_invalid")
        }
        let solution = teacherValidationString(structured, "solution_cj")
        let actualEvidence = if (solution.startsWith("{")) {
            let evidence = JsonValue.fromStr(solution).asObject()
            if (evidence.getFields().size != 1) {
                throw IllegalArgumentException("candidate_test_evidence_invalid")
            }
            teacherValidationString(evidence, "actualEvidence")
        } else { solution }
        if (!teacherStudentProcessSafe(actualEvidence, 8192)) {
            throw IllegalArgumentException("candidate_test_evidence_invalid")
        }
        actualEvidence
    } catch (e: IllegalArgumentException) { throw e }
    catch (_: Exception) { throw IllegalArgumentException("malformed_json") }
}

private func teacherStudentVerifierEvidence(fixture: TeacherAssetFixture,
    target: TeacherAssetValidationTarget, actual: String, exitCode: Int64): String {
    let fields = [teacherAssetFixtureHash(fixture), target.candidateProjectionHash,
        fixture.expectedEvidence, actual, exitCode.toString()]
    let canonical = teacherJoin(fields.map(
        {value: String => "${value.toArray().size}:${value}"}), "")
    "sha256:${teacherStableHash(canonical)}"
}

public class StudentCompletionNonHumanEvalExecutor <: TeacherAssetFixtureExecutor {
    private let runtimeExecutable: String
    private let workspaceRoot: String
    private let identity: TeacherValidationIdentity
    private let completionControlPath: String
    private let executor: TeacherStudentRuntimeExecutor
    private let timeoutMillis: Int64
    public init(runtimeExecutable: String, allowedRoot: String, workspaceRoot: String,
        completionControlPath: String,
        identity: TeacherValidationIdentity,
        executor!: TeacherStudentRuntimeExecutor = NativeTeacherStudentRuntimeExecutor(),
        timeoutMillis!: Int64 = 600000) {
        if (!teacherStudentExecutableSafe(runtimeExecutable) || timeoutMillis < 1 ||
            timeoutMillis > 3600000) {
            throw IllegalArgumentException("student_validation_identity_invalid")
        }
        if (teacherValidationExecutableHash(runtimeExecutable) != identity.runtimeExecutableHash) {
            throw IllegalArgumentException("student_validation_identity_mismatch")
        }
        this.runtimeExecutable = runtimeExecutable
        this.workspaceRoot = teacherResolveArtifactInput(allowedRoot, workspaceRoot, directory: true)
        this.completionControlPath = teacherResolveArtifactInput(allowedRoot, completionControlPath)
        let controlRaw = teacherReadUtf8File(this.completionControlPath)
        if (identity.completionControlHash != "sha256:${teacherStableHash(controlRaw)}") {
            throw IllegalArgumentException("student_validation_identity_mismatch")
        }
        let control = parseTeacherStudentCompletionControl(controlRaw)
        if (timeoutMillis != control.modelTimeoutSeconds * 1000) {
            throw IllegalArgumentException("student_completion_control_invalid")
        }
        if (control.outputSchemaHash !=
            "sha256:${teacherStableHash(teacherStudentCompletionOutputSchema())}" ||
            control.completionCommandHash != teacherStudentCompletionCommandHash(identity.modelVersion)) {
            throw IllegalArgumentException("student_validation_identity_mismatch")
        }
        _ = renderTeacherValidationIdentity(identity); this.identity = identity
        this.executor = executor
        this.timeoutMillis = control.modelTimeoutSeconds * 1000
    }
    public func executorKind(): String { "student_completion_non_humaneval" }
    public func providerIdentityHash(): String { identity.identityHash }
    public func modelVersion(): String { identity.modelVersion }
    public func validationIdentity(): TeacherValidationIdentity { identity }
    public func execute(target: TeacherAssetValidationTarget,
        fixture: TeacherAssetFixture): (Int64, String, String) {
        let controlRaw = teacherReadUtf8File(completionControlPath)
        if ("sha256:${teacherStableHash(controlRaw)}" != identity.completionControlHash) {
            throw IllegalArgumentException("student_validation_identity_mismatch")
        }
        let control = parseTeacherStudentCompletionControl(controlRaw)
        if (control.outputSchemaHash !=
            "sha256:${teacherStableHash(teacherStudentCompletionOutputSchema())}" ||
            control.completionCommandHash != teacherStudentCompletionCommandHash(identity.modelVersion) ||
            teacherValidationExecutableHash(runtimeExecutable) != identity.runtimeExecutableHash) {
            throw IllegalArgumentException("student_validation_identity_mismatch")
        }
        if (target.identity.identityHash != identity.identityHash ||
            target.identity.modelVersion != identity.modelVersion ||
            !teacherArtifactSafeComponent(fixture.fixtureId)) {
            throw IllegalArgumentException("student_validation_identity_mismatch")
        }
        let candidatePart = target.candidateProjectionHash.replace("sha256:", "")
        let runRoot = Path(workspaceRoot).join(candidatePart).join(target.lane).join(fixture.fixtureId)
        if (exists(runRoot)) { throw IllegalArgumentException("candidate_test_evidence_invalid") }
        Directory.create(runRoot, recursive: true)
        let prompt = teacherStudentPrompt(fixture, target)
        if (prompt.toArray().size > control.effectivePromptByteBudget) {
            throw IllegalArgumentException("candidate_test_evidence_invalid")
        }
        _ = teacherAtomicWrite(runRoot.join("prompt.final.md").toString(), prompt + "\n")
        _ = teacherAtomicWrite(runRoot.join("mcp-config.json").toString(), "{\"mcpServers\":{}}\n")
        for (name in ["bin", "tmp", "xdg-config", "xdg-cache", "claude-config"]) {
            Directory.create(runRoot.join(name), recursive: true)
        }
        let profile = runRoot.join("sandbox.sb").toString()
        let transcriptPath = runRoot.join("transcript.json").toString()
        let stderrPath = runRoot.join("stderr.log").toString()
        _ = teacherAtomicWrite(profile, teacherStudentSandboxProfile(runRoot.toString(),
            runtimeExecutable))
        let command = teacherStudentCompletionCommand(runRoot.toString(), runRoot.toString(),
            profile, runtimeExecutable, identity.modelVersion, transcriptPath, stderrPath)
        let result = executor.execute(TeacherStudentRuntimeSpec("/bin/zsh", ["-c", command],
            runRoot.toString(), [("HOME", runRoot.toString()),
                ("CANGJIE_TEACHER_VALIDATION_IDENTITY", identity.identityHash)], timeoutMillis))
        if (result.timedOut) { throw IllegalArgumentException("candidate_test_evidence_invalid") }
        if (result.exitCode != 0) {
            throw IllegalArgumentException("candidate_test_evidence_invalid")
        }
        let raw = if (!result.stdout.trimAscii().isEmpty()) { result.stdout.trimAscii() }
            else if (exists(Path(transcriptPath))) { teacherReadUtf8File(transcriptPath).trimAscii() }
            else { "" }
        if (raw == "invalid_response_encoding") { throw IllegalArgumentException("invalid_response_encoding") }
        if (raw.toArray().size > STUDENT_VALIDATION_RESPONSE_MAX_BYTES) {
            throw IllegalArgumentException("candidate_test_evidence_invalid")
        }
        try {
            let actual = teacherStudentClaudeSolution(raw, identity.modelVersion)
            let verifierHash = teacherStudentVerifierEvidence(fixture, target, actual, result.exitCode)
            let transcript = buildTeacherStudentValidationTranscript(fixture, target, actual,
                verifierHash, result.exitCode)
            (result.exitCode, actual, renderTeacherStudentValidationTranscript(transcript))
        } catch (e: IllegalArgumentException) { throw e }
        catch (_: Exception) { throw IllegalArgumentException("malformed_json") }
    }
}

public class TeacherStudentValidationTranscript {
    public let fixtureId: String
    public let lane: String
    public let candidateVisibleHash: String
    public let baseCompositeHash: String
    public let validationIdentityHash: String
    public let requestHash: String
    public let responseHash: String
    public let verifierEvidenceHash: String
    public let exitCode: Int64
    public init(fixtureId: String, lane: String, candidateVisibleHash: String,
        baseCompositeHash: String, validationIdentityHash: String, requestHash: String,
        responseHash: String, verifierEvidenceHash: String, exitCode: Int64) {
        this.fixtureId = fixtureId; this.lane = lane; this.candidateVisibleHash = candidateVisibleHash
        this.baseCompositeHash = baseCompositeHash; this.validationIdentityHash = validationIdentityHash
        this.requestHash = requestHash; this.responseHash = responseHash
        this.verifierEvidenceHash = verifierEvidenceHash; this.exitCode = exitCode
    }
}

private func teacherStudentValidationRequestHash(fixtureHash: String,
    target: TeacherAssetValidationTarget): String {
    let fields = [fixtureHash, target.lane, target.candidateProjectionHash,
        target.baseCompositeHash, target.identity.identityHash]
    let canonical = teacherJoin(fields.map(
        {value: String => "${value.toArray().size}:${value}"}), "")
    "sha256:${teacherStableHash(canonical)}"
}

private func teacherStudentValidationResponseHash(actualEvidence: String,
    verifierEvidenceHash: String, exitCode: Int64): String {
    let fields = [actualEvidence, verifierEvidenceHash, exitCode.toString()]
    let canonical = teacherJoin(fields.map(
        {value: String => "${value.toArray().size}:${value}"}), "")
    "sha256:${teacherStableHash(canonical)}"
}

public func buildTeacherStudentValidationTranscript(fixture: TeacherAssetFixture,
    target: TeacherAssetValidationTarget, actualEvidence: String,
    verifierEvidenceHash: String, exitCode: Int64): TeacherStudentValidationTranscript {
    if (!teacherValidationHash(verifierEvidenceHash)) {
        throw IllegalArgumentException("candidate_test_evidence_invalid")
    }
    let fixtureHash = teacherAssetFixtureHash(fixture)
    TeacherStudentValidationTranscript(fixture.fixtureId, target.lane,
        target.candidateProjectionHash, target.baseCompositeHash, target.identity.identityHash,
        teacherStudentValidationRequestHash(fixtureHash, target),
        teacherStudentValidationResponseHash(actualEvidence, verifierEvidenceHash, exitCode),
        verifierEvidenceHash, exitCode)
}

public func renderTeacherStudentValidationTranscript(value: TeacherStudentValidationTranscript): String {
    if (!teacherArtifactSafeComponent(value.fixtureId) || !["rules", "skills"].contains(value.lane) ||
        !teacherValidationHash(value.candidateVisibleHash) ||
        !(value.baseCompositeHash == "none" || teacherValidationHash(value.baseCompositeHash)) ||
        !teacherValidationHash(value.validationIdentityHash) || !teacherValidationHash(value.requestHash) ||
        !teacherValidationHash(value.responseHash) || !teacherValidationHash(value.verifierEvidenceHash)) {
        throw IllegalArgumentException("candidate_test_evidence_invalid")
    }
    "{\"schemaVersion\":\"teacher-student-validation-transcript-v1\"," +
        "\"fixtureId\":\"${value.fixtureId}\",\"lane\":\"${value.lane}\"," +
        "\"candidateVisibleHash\":\"${value.candidateVisibleHash}\"," +
        "\"baseCompositeHash\":\"${value.baseCompositeHash}\"," +
        "\"validationIdentityHash\":\"${value.validationIdentityHash}\"," +
        "\"requestHash\":\"${value.requestHash}\",\"responseHash\":\"${value.responseHash}\"," +
        "\"verifierEvidenceHash\":\"${value.verifierEvidenceHash}\",\"exitCode\":${value.exitCode}}"
}

public func parseTeacherStudentValidationTranscript(raw: String): TeacherStudentValidationTranscript {
    try {
        let object = JsonValue.fromStr(raw).asObject()
        if (object.getFields().size != 10 || teacherValidationString(object, "schemaVersion") !=
            "teacher-student-validation-transcript-v1") {
            throw IllegalArgumentException("candidate_test_evidence_invalid")
        }
        let exitCode = match (object.get("exitCode")) {
            case Some(value) => value.asInt().getValue()
            case None => Int64(-1)
        }
        let value = TeacherStudentValidationTranscript(teacherValidationString(object, "fixtureId"),
            teacherValidationString(object, "lane"), teacherValidationString(object, "candidateVisibleHash"),
            teacherValidationString(object, "baseCompositeHash"),
            teacherValidationString(object, "validationIdentityHash"),
            teacherValidationString(object, "requestHash"), teacherValidationString(object, "responseHash"),
            teacherValidationString(object, "verifierEvidenceHash"), exitCode)
        if (raw != renderTeacherStudentValidationTranscript(value)) {
            throw IllegalArgumentException("candidate_test_evidence_invalid")
        }
        value
    } catch (e: IllegalArgumentException) { throw e }
    catch (_: Exception) { throw IllegalArgumentException("candidate_test_evidence_invalid") }
}

private func teacherValidateStudentTranscript(value: TeacherStudentValidationTranscript,
    fixture: TeacherAssetFixture, target: TeacherAssetValidationTarget,
    actualEvidence: String, exitCode: Int64): Unit {
    if (value.fixtureId != fixture.fixtureId || value.lane != target.lane ||
        value.candidateVisibleHash != target.candidateProjectionHash ||
        value.baseCompositeHash != target.baseCompositeHash ||
        value.validationIdentityHash != target.identity.identityHash ||
        value.requestHash != teacherStudentValidationRequestHash(teacherAssetFixtureHash(fixture), target) ||
        value.responseHash != teacherStudentValidationResponseHash(actualEvidence,
            value.verifierEvidenceHash, exitCode) || value.exitCode != exitCode) {
        throw IllegalArgumentException("candidate_test_evidence_invalid")
    }
}

// Transcript semantics normalize line endings and trailing line breaks without trimming spaces.
public func teacherTranscriptSemantic(value: String): String {
    let normalized = value.replace("\r\n", "\n").replace("\r", "\n")
    let runes = normalized.toRuneArray(); var end = runes.size
    while (end > 0 && runes[end - 1] == r'\n') { end -= 1 }
    if (end == 0) { "" } else { String(runes[..end]) }
}

private func teacherFixtureCanonical(value: TeacherAssetFixture): String {
    teacherJoin([value.fixtureId, value.kind, value.sourceClass, value.content,
        value.expectedEvidence].map({v: String => "${v.toArray().size}:${v}"}), "")
}

private func teacherFixtureSafe(value: String): Bool {
    let lower = value.toAsciiLower()
    !lower.contains("cj-humaneval-") && !lower.contains("hidden_test") &&
        !lower.contains("reference solution") && !lower.contains("/users/") &&
        !lower.contains("authorization") && !lower.contains("token=")
}

public func executeTeacherAssetFixtureBundle(fixtures: Array<TeacherAssetFixture>,
    executor: TeacherAssetFixtureExecutor, target: TeacherAssetValidationTarget): Array<TeacherAssetFixtureExecution> {
    if (fixtures.isEmpty() || !["fake_contract", "student_completion_non_humaneval"].contains(executor.executorKind())) {
        throw IllegalArgumentException("candidate_test_evidence_invalid")
    }
    if (target.candidateProjectionHash !=
        "sha256:${teacherStableHash(target.candidateVisibleProjection)}" ||
        target.lane == "scaffold" || !["rules", "skills"].contains(target.lane)) {
        throw IllegalArgumentException("candidate_test_evidence_invalid")
    }
    if (executor.executorKind() == "student_completion_non_humaneval") {
        if (target.identity.identityHash != executor.providerIdentityHash() ||
            target.identity.modelVersion != executor.modelVersion()) {
            throw IllegalArgumentException("student_validation_identity_mismatch")
        }
        _ = renderTeacherValidationIdentity(target.identity)
    }
    let ids = HashSet<String>(); let out = ArrayList<TeacherAssetFixtureExecution>()
    for (fixture in fixtures) {
        if (fixture.fixtureId.isEmpty() || ids.contains(fixture.fixtureId) ||
            !["unit", "positive", "negative", "boundary", "generalization"].contains(fixture.kind) ||
            !["official", "community", "non_humaneval_experiment"].contains(fixture.sourceClass) ||
            fixture.content.isEmpty() || fixture.expectedEvidence.isEmpty() ||
            !teacherFixtureSafe(fixture.content + fixture.expectedEvidence)) {
            throw IllegalArgumentException("candidate_test_evidence_invalid")
        }
        ids.add(fixture.fixtureId)
        let fixtureHash = "sha256:${teacherStableHash(teacherFixtureCanonical(fixture))}"
        let executed = executor.execute(target, fixture)
        if (executor.executorKind() == "student_completion_non_humaneval") {
            teacherValidateStudentTranscript(parseTeacherStudentValidationTranscript(
                teacherTranscriptSemantic(executed[2])), fixture, target, executed[1], executed[0])
        }
        let passed = executed[0] == 0 && executed[1] == fixture.expectedEvidence
        let transcript = teacherTranscriptSemantic(executed[2])
        let transcriptHash = "sha256:${teacherStableHash(transcript)}"
        out.add(TeacherAssetFixtureExecution(fixture, fixtureHash, executor.executorKind(),
            executor.providerIdentityHash(), executor.modelVersion(), executed[1], transcriptHash,
            executed[0], passed, transcript: transcript))
    }
    out.toArray()
}

// Compatibility is deliberately limited to scaffold executors. Production evidence must
// always supply the exact candidate projection through the overload above.
public func executeTeacherAssetFixtureBundle(fixtures: Array<TeacherAssetFixture>,
    executor: TeacherAssetFixtureExecutor): Array<TeacherAssetFixtureExecution> {
    if (executor.executorKind() != "fake_contract") {
        throw IllegalArgumentException("candidate_test_evidence_invalid")
    }
    let identity = executor.validationIdentity()
    _ = renderTeacherValidationIdentity(identity)
    let target = buildTeacherAssetValidationTarget("rules", "scaffold", "none", identity)
    executeTeacherAssetFixtureBundle(fixtures, executor, target)
}

public func teacherAssetFixtureHash(value: TeacherAssetFixture): String {
    "sha256:${teacherStableHash(teacherFixtureCanonical(value))}"
}

// Candidate writers and readers select repeated categories by the same stable fixture-id order.
public func teacherFirstEvidenceHashByFixtureId(
    entries: Array<(String, String, String)>, kind: String): String {
    let ids = ArrayList<String>()
    for (entry in entries) { if (entry[1] == kind) { ids.add(entry[0]) } }
    let sortedIds = ids.toArray(); sort(sortedIds)
    if (sortedIds.isEmpty()) { return "" }
    for (entry in entries) {
        if (entry[0] == sortedIds[0] && entry[1] == kind) { return entry[2] }
    }
    ""
}

public func renderTeacherAssetFixture(value: TeacherAssetFixture): String {
    let hash = teacherAssetFixtureHash(value)
    "{\"schemaVersion\":\"teacher-asset-fixture-v1\",\"fixtureId\":\"${teacherFixtureExecutionEscape(value.fixtureId)}\"," +
        "\"kind\":\"${value.kind}\",\"sourceClass\":\"${value.sourceClass}\"," +
        "\"content\":\"${teacherFixtureExecutionEscape(value.content)}\"," +
        "\"expectedEvidence\":\"${teacherFixtureExecutionEscape(value.expectedEvidence)}\"," +
        "\"fixtureHash\":\"${hash}\"}"
}

public func teacherAssetFixtureExecutionFiles(value: TeacherAssetFixtureExecution,
    prefix: String): Array<TeacherArtifactFile> {
    let transcript = teacherTranscriptSemantic(value.transcript)
    if (value.fixtureHash != teacherAssetFixtureHash(value.fixture) ||
        value.transcriptHash != "sha256:${teacherStableHash(transcript)}" ||
        value.fixture.expectedEvidence.contains("\r") || value.fixture.expectedEvidence.endsWith("\n") ||
        value.actualEvidence.contains("\r") || value.actualEvidence.endsWith("\n") ||
        value.passed != (value.exitCode == 0 && value.actualEvidence == value.fixture.expectedEvidence)) {
        throw IllegalArgumentException("candidate_test_evidence_invalid")
    }
    [
        TeacherArtifactFile("${prefix}/fixture.json", renderTeacherAssetFixture(value.fixture) + "\n"),
        TeacherArtifactFile("${prefix}/expected.txt", value.fixture.expectedEvidence + "\n"),
        TeacherArtifactFile("${prefix}/actual.txt", value.actualEvidence + "\n"),
        TeacherArtifactFile("${prefix}/transcript.txt", transcript + "\n"),
        TeacherArtifactFile("${prefix}/execution.json", renderTeacherAssetFixtureExecution(value) + "\n")
    ]
}

private func teacherFixtureExecutionEscape(value: String): String {
    value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
}

public func renderTeacherAssetFixtureExecution(value: TeacherAssetFixtureExecution): String {
    if (!value.fixtureHash.startsWith("sha256:") || !value.transcriptHash.startsWith("sha256:") ||
        value.transcriptHash != "sha256:${teacherStableHash(teacherTranscriptSemantic(value.transcript))}" ||
        !value.providerIdentityHash.startsWith("sha256:") ||
        !["fake_contract", "student_completion_non_humaneval"].contains(value.executorKind)) {
        throw IllegalArgumentException("candidate_test_evidence_invalid")
    }
    let expectedHash = "sha256:${teacherStableHash(value.fixture.expectedEvidence)}"
    let actualHash = "sha256:${teacherStableHash(value.actualEvidence)}"
    "{\"schemaVersion\":\"teacher-candidate-fixture-execution-v1\"," +
        "\"fixtureId\":\"${teacherFixtureExecutionEscape(value.fixture.fixtureId)}\"," +
        "\"kind\":\"${value.fixture.kind}\",\"sourceClass\":\"${value.fixture.sourceClass}\"," +
        "\"fixtureHash\":\"${value.fixtureHash}\",\"executorKind\":\"${value.executorKind}\"," +
        "\"providerIdentityHash\":\"${value.providerIdentityHash}\",\"modelVersion\":\"${value.modelVersion}\"," +
        "\"expectedEvidenceHash\":\"${expectedHash}\",\"actualEvidenceHash\":\"${actualHash}\"," +
        "\"transcriptHash\":\"${value.transcriptHash}\",\"exitCode\":${value.exitCode},\"passed\":${value.passed}}"
}
