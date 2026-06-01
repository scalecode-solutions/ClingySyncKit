import Foundation

/// A device-local log, as the reconciler sees it (decoupled from any concrete
/// model). The LocalStore impl maps its own entities ↔ LogRecord.
public struct LogRecord: Sendable {
    public var clientID: UUID
    public var subjectID: UUID
    public var type: String
    public var schemaVersion: Int
    public var occurredAt: Date
    public var payload: Data
    public var deleted: Bool
    public var serverSeq: Int64?

    public init(clientID: UUID, subjectID: UUID, type: String, schemaVersion: Int, occurredAt: Date, payload: Data, deleted: Bool, serverSeq: Int64?) {
        self.clientID = clientID; self.subjectID = subjectID; self.type = type
        self.schemaVersion = schemaVersion; self.occurredAt = occurredAt; self.payload = payload
        self.deleted = deleted; self.serverSeq = serverSeq
    }
}

/// The reconciler's local-persistence seam. The dummy provides a SwiftData
/// impl over a stand-in model; Clingy provides one over its real @Models.
public protocol LocalStore: AnyObject {
    /// Records changed locally and not yet pushed (dirty).
    func pendingPush(subjectID: UUID) throws -> [LogRecord]
    /// Mark a pushed record clean and stamp the server-assigned seq.
    func markSynced(clientID: UUID, subjectID: UUID, serverSeq: Int64) throws
    /// Apply a pulled row: LWW upsert by serverSeq, or delete on a tombstone.
    func applyRemote(_ row: LogRow) throws
    /// The per-subject pull cursor (max server_seq applied).
    func pullCursor(subjectID: UUID) throws -> Int64
    func setPullCursor(subjectID: UUID, _ seq: Int64) throws
}
