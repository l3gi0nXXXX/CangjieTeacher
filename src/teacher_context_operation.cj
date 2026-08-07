package cangjie_teacher

import std.collection.*
import std.sort.*

public class TeacherContextBaseAssetIdentity {
    public let assetId: String
    public let hash: String
    public let content: String
    public let priority: Int64
    public init(assetId: String, hash: String, content!: String = "", priority!: Int64 = 0) {
        this.assetId = assetId; this.hash = hash; this.content = content; this.priority = priority
    }
}

public func applyTeacherContextAssetOperation(baseAssets: Array<TeacherContextBaseAssetIdentity>,
    operation: TeacherContextAssetOperation, content: String, priority!: Int64 = 0): Array<TeacherContextBaseAssetIdentity> {
    _ = buildTeacherContextAssetOperation(operation.assetRole, operation.assetId,
        operation.operation, operation.expectedOldHash, operation.newHash, baseAssets)
    if (content.isEmpty()) { throw IllegalArgumentException("candidate_lane_hash_mismatch") }
    let out = ArrayList<TeacherContextBaseAssetIdentity>()
    for (asset in baseAssets) {
        if (asset.assetId != operation.assetId) { out.add(asset) }
    }
    out.add(TeacherContextBaseAssetIdentity(operation.assetId, operation.newHash,
        content: content, priority: priority))
    let ids = out.toArray().map({asset: TeacherContextBaseAssetIdentity => asset.assetId}); sort(ids)
    let sorted = ArrayList<TeacherContextBaseAssetIdentity>()
    for (id in ids) { for (asset in out) { if (asset.assetId == id) { sorted.add(asset); break } } }
    sorted.toArray()
}

public func teacherContextAssetProjection(assetRole: String,
    assets: Array<TeacherContextBaseAssetIdentity>): String {
    if (!["rules", "skills"].contains(assetRole)) { throw IllegalArgumentException("candidate_lane_hash_mismatch") }
    var out = if (assetRole == "rules") { "# Student Rules\n" } else { "" }
    if (assetRole == "rules") {
        var priority: Int64 = 1000
        while (priority >= 0) {
            let ids = ArrayList<String>()
            for (asset in assets) {
                if (asset.priority < 0 || asset.priority > 1000) {
                    throw IllegalArgumentException("candidate_base_composite_mismatch")
                }
                if (asset.priority == priority) { ids.add(asset.assetId) }
            }
            let sortedIds = ids.toArray(); sort(sortedIds)
            for (id in sortedIds) { for (asset in assets) { if (asset.assetId == id) {
                if (asset.content.isEmpty()) { throw IllegalArgumentException("candidate_base_composite_mismatch") }
                out += asset.content; break
            } } }
            priority -= 1
        }
    } else {
        let ids = assets.map({asset: TeacherContextBaseAssetIdentity => asset.assetId}); sort(ids)
        for (id in ids) {
            for (asset in assets) {
                if (asset.assetId == id) {
                    if (asset.content.isEmpty()) { throw IllegalArgumentException("candidate_base_composite_mismatch") }
                    out += asset.content; break
                }
            }
        }
    }
    out
}

public class TeacherContextAssetOperation {
    public let assetRole: String
    public let assetId: String
    public let operation: String
    public let expectedOldHash: String
    public let newHash: String
    public init(assetRole: String, assetId: String, operation: String,
        expectedOldHash: String, newHash: String) {
        this.assetRole = assetRole; this.assetId = assetId; this.operation = operation
        this.expectedOldHash = expectedOldHash; this.newHash = newHash
    }
}

private func teacherOperationHash(value: String): Bool {
    if (!value.startsWith("sha256:") || value.toRuneArray().size != 71) { return false }
    for (rune in value.toRuneArray()[7..]) {
        if (!((rune >= r'0' && rune <= r'9') || (rune >= r'a' && rune <= r'f'))) { return false }
    }
    true
}

public func buildTeacherContextAssetOperation(assetRole: String, assetId: String,
    requestedOperation: String, expectedOldHash: String, newHash: String,
    baseAssets: Array<TeacherContextBaseAssetIdentity>): TeacherContextAssetOperation {
    if (!["rules", "skills"].contains(assetRole) || !teacherArtifactSafeComponent(assetId) ||
        !["add", "replace"].contains(requestedOperation) || !teacherOperationHash(newHash)) {
        throw IllegalArgumentException("candidate_operation_invalid")
    }
    var found = ""
    for (base in baseAssets) {
        if (!teacherArtifactSafeComponent(base.assetId) || !teacherOperationHash(base.hash)) {
            throw IllegalArgumentException("candidate_base_composite_mismatch")
        }
        if (base.assetId == assetId) {
            if (!found.isEmpty()) { throw IllegalArgumentException("candidate_base_composite_mismatch") }
            found = base.hash
        }
    }
    if (requestedOperation == "add") {
        if (!expectedOldHash.isEmpty() || !found.isEmpty()) {
            throw IllegalArgumentException("candidate_operation_invalid")
        }
    } else if (found.isEmpty() || expectedOldHash != found) {
        throw IllegalArgumentException("candidate_replace_hash_mismatch")
    }
    TeacherContextAssetOperation(assetRole, assetId, requestedOperation, expectedOldHash, newHash)
}

public func renderTeacherContextAssetOperation(value: TeacherContextAssetOperation): String {
    if (!["rules", "skills"].contains(value.assetRole) ||
        !teacherArtifactSafeComponent(value.assetId) || !["add", "replace"].contains(value.operation) ||
        !teacherOperationHash(value.newHash) ||
        (value.operation == "add" && !value.expectedOldHash.isEmpty()) ||
        (value.operation == "replace" && !teacherOperationHash(value.expectedOldHash))) {
        throw IllegalArgumentException("candidate_operation_invalid")
    }
    "{\"schemaVersion\":\"teacher-context-asset-operation-v1\",\"assetRole\":\"${value.assetRole}\"," +
        "\"assetId\":\"${value.assetId}\",\"operation\":\"${value.operation}\"," +
        "\"expectedOldHash\":\"${value.expectedOldHash}\",\"newHash\":\"${value.newHash}\"}"
}
