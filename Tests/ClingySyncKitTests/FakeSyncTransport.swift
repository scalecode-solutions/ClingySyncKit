import Foundation
@testable import ClingySyncKit

/// In-memory stand-in for clingy2_api's logs.* semantics — single-owner (the
/// owner-isolation guarantee is proven server-side in slice 4). Mirrors:
/// upsert is idempotent on (subject, client) and stamps a fresh monotonic
/// server_seq; pull returns rows with server_seq > since (incl. tombstones)
/// ordered by seq, plus the new cursor.
final class FakeSyncTransport: SyncTransport, @unchecked Sendable {
    private var rows: [String: LogRow] = [:] // "subject/client" → row
    private var seq: Int64 = 0
    private let lock = NSLock()

    func upsert(_ req: UpsertReq) async throws -> UpsertRes {
        lock.lock(); defer { lock.unlock() }
        var results: [UpsertResult] = []
        for item in req.logs {
            seq += 1
            let key = "\(req.subjectId.uuidString)/\(item.clientId.uuidString)"
            rows[key] = LogRow(
                clientId: item.clientId, subjectId: req.subjectId, type: item.type,
                schemaVersion: item.schemaVersion, occurredAt: item.occurredAt, payload: item.payload,
                deletedAt: item.deleted ? Date() : nil, serverSeq: seq, updatedAt: Date()
            )
            results.append(UpsertResult(clientId: item.clientId, serverSeq: seq, updatedAt: Date()))
        }
        return UpsertRes(results: results, cursor: seq)
    }

    func pull(_ req: PullReq) async throws -> PullRes {
        lock.lock(); defer { lock.unlock() }
        var out = rows.values.filter { $0.subjectId == req.subjectId && $0.serverSeq > req.since }
        out.sort { $0.serverSeq < $1.serverSeq }
        return PullRes(logs: out, cursor: out.last?.serverSeq ?? req.since)
    }
}
