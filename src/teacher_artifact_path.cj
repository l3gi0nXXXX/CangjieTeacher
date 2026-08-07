package cangjie_teacher

import std.fs.*

public func teacherArtifactSafeComponent(value: String): Bool {
    let runes = value.toRuneArray()
    if (runes.isEmpty() || runes.size > 96 || value == "." || value == "..") { return false }
    for (rune in runes) {
        if (!((rune >= r'a' && rune <= r'z') || (rune >= r'0' && rune <= r'9') ||
            rune == r'-' || rune == r'_')) { return false }
    }
    !value.contains("..")
}

public func teacherCanonicalArtifactRoot(path: String): String {
    let root = Path(path)
    if (!root.isAbsolute() || !exists(root)) { throw IllegalArgumentException("artifact_root_invalid") }
    try {
        if (FileInfo(root).isSymbolicLink() || !FileInfo(root).isDirectory()) {
            throw IllegalArgumentException("artifact_root_invalid")
        }
        canonicalize(root).toString().trimEnd('/')
    } catch (e: IllegalArgumentException) { throw e }
    catch (_: Exception) { throw IllegalArgumentException("artifact_root_invalid") }
}

private func teacherArtifactParentIsRoot(root: String, child: String): Bool {
    let parent = try { canonicalize(Path(child).parent).toString().trimEnd('/') }
    catch (_: Exception) { return false }
    parent == root
}

private func teacherArtifactDirectChild(root: String, child: String): Bool {
    teacherArtifactParentIsRoot(root, child) && teacherArtifactSafeComponent(Path(child).fileName)
}

public func teacherResolveArtifactInput(allowedRoot: String, path: String,
    directory!: Bool = false): String {
    let root = teacherCanonicalArtifactRoot(allowedRoot)
    let lexicalRoot = Path(allowedRoot).toString().trimEnd('/')
    let input = Path(path)
    if (!input.isAbsolute() || !path.startsWith(lexicalRoot + "/")) {
        throw IllegalArgumentException("artifact_input_invalid")
    }
    try {
        // Inspect the caller's original path one segment at a time before
        // canonicalization so an intermediate symlink cannot disappear.
        var current = Path(lexicalRoot)
        let relative = path.toRuneArray()[lexicalRoot.toRuneArray().size + 1..]
        for (component in String(relative).split("/")) {
            if (component.isEmpty() || component == "." || component == ".." || component.contains("\\")) {
                throw IllegalArgumentException("artifact_input_invalid")
            }
            current = current.join(component)
            if (!exists(current) || FileInfo(current).isSymbolicLink()) {
                throw IllegalArgumentException("artifact_input_invalid")
            }
        }
        let canonical = canonicalize(input).toString()
        if (!canonical.startsWith(root + "/") ||
            (directory && !FileInfo(input).isDirectory()) ||
            (!directory && !FileInfo(input).isRegular())) {
            throw IllegalArgumentException("artifact_input_invalid")
        }
        canonical
    } catch (e: IllegalArgumentException) { throw e }
    catch (_: Exception) { throw IllegalArgumentException("artifact_input_invalid") }
}

public func teacherCreateArtifactOutputRoot(allowedRoot: String, outputRoot: String): String {
    let root = teacherCanonicalArtifactRoot(allowedRoot)
    let output = Path(outputRoot)
    if (!output.isAbsolute() || exists(output) || !teacherArtifactDirectChild(root, outputRoot)) {
        throw IllegalArgumentException("artifact_output_invalid")
    }
    try { Directory.create(output, recursive: false) }
    catch (_: Exception) { throw IllegalArgumentException("artifact_output_invalid") }
    let canonical = try { canonicalize(output).toString() }
    catch (_: Exception) { throw IllegalArgumentException("artifact_output_invalid") }
    if (!teacherArtifactDirectChild(root, canonical)) { throw IllegalArgumentException("artifact_output_invalid") }
    canonical
}

public func teacherArtifactStagePath(outputRoot: String, candidateSetId: String,
    nonce: String): String {
    let root = teacherCanonicalArtifactRoot(outputRoot)
    if (!teacherArtifactSafeComponent(candidateSetId) || !teacherArtifactSafeComponent(nonce)) {
        throw IllegalArgumentException("candidate_set_id_invalid")
    }
    root + "/.stage-${candidateSetId}-${nonce}"
}

public func teacherRemoveCreatedArtifactStage(outputRoot: String, stage: String): Unit {
    let root = teacherCanonicalArtifactRoot(outputRoot)
    let value = Path(stage)
    if (!exists(value)) { return }
    if (!value.isAbsolute() || !teacherArtifactParentIsRoot(root, stage) ||
        !value.fileName.startsWith(".stage-") || FileInfo(value).isSymbolicLink()) {
        throw IllegalArgumentException("artifact_stage_invalid")
    }
    remove(value, recursive: true)
}
