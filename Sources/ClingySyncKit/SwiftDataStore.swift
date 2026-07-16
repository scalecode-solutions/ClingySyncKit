import Foundation
import SwiftData

/// A stand-in synced model — the reference/test data layer (used by this
/// package's test suite; production Clingy uses its own store). Mirrors the
/// *shape* of a Clingy tracker entity: a stable client UUID, subject scoping,
/// the domain fields, a soft-delete flag, the synced server_seq, and a `dirty`
/// flag for push tracking. Clingy's real @Models carry the same shape.
///
/// NB: the soft-delete flag is `tombstoned`, not `deleted` — `deleted` collides
/// with NSManagedObject's `isDeleted` under SwiftData and silently fails to
/// persist. (Learned the hard way; keep this name.)
@Model
public final class WeightEntry {
    @Attribute(.unique) public var clientID: UUID
    public var subjectID: UUID
    public var weightLbs: Double
    public var note: String?
    public var occurredAt: Date
    public var tombstoned: Bool
    public var serverSeq: Int64?
    public var dirty: Bool

    public init(clientID: UUID = UUID(), subjectID: UUID, weightLbs: Double, note: String? = nil,
                occurredAt: Date = .now, tombstoned: Bool = false, serverSeq: Int64? = nil, dirty: Bool = true) {
        self.clientID = clientID
        self.subjectID = subjectID
        self.weightLbs = weightLbs
        self.note = note
        self.occurredAt = occurredAt
        self.tombstoned = tombstoned
        self.serverSeq = serverSeq
        self.dirty = dirty
    }
}

/// Per-subject pull cursor (max server_seq applied).
@Model
public final class SyncCursor {
    @Attribute(.unique) public var subjectID: UUID
    public var seq: Int64
    public init(subjectID: UUID, seq: Int64) { self.subjectID = subjectID; self.seq = seq }
}

/// The Weight payload shape (the type-specific JSON the server schema-validates).
struct WeightPayload: Codable {
    var weightLbs: Double
    var note: String?
}

/// SwiftData-backed LocalStore. The type-aware mapping (WeightEntry ↔ "weight"
/// payload) lives here, per the per-app store contract; the reconciler stays
/// generic.
public final class SwiftDataLocalStore: LocalStore {
    private let context: ModelContext
    public init(context: ModelContext) { self.context = context }

    public func pendingPush(subjectID: UUID) throws -> [LogRecord] {
        try allEntities()
            .filter { $0.subjectID == subjectID && $0.dirty }
            .map { e in
                let payload = try JSONEncoder().encode(WeightPayload(weightLbs: e.weightLbs, note: e.note))
                return LogRecord(clientID: e.clientID, subjectID: e.subjectID, type: "weight",
                                 schemaVersion: 1, occurredAt: e.occurredAt, payload: payload,
                                 deleted: e.tombstoned, serverSeq: e.serverSeq)
            }
    }

    public func markSynced(clientID: UUID, subjectID: UUID, serverSeq: Int64) throws {
        guard let e = try entity(clientID) else { return }
        e.dirty = false
        e.serverSeq = serverSeq
        try context.save()
    }

    public func applyRemote(_ row: LogRow) throws {
        let existing = try entity(row.clientId)
        if row.deletedAt != nil { // tombstone
            if let e = existing { context.delete(e); try context.save() }
            return
        }
        if let e = existing, let s = e.serverSeq, row.serverSeq <= s {
            return // stale — local already at or ahead of this version
        }
        let p = try JSONDecoder().decode(WeightPayload.self, from: row.payload)
        if let e = existing {
            e.weightLbs = p.weightLbs
            e.note = p.note
            e.occurredAt = row.occurredAt
            e.serverSeq = row.serverSeq
            e.tombstoned = false
            e.dirty = false
        } else {
            context.insert(WeightEntry(clientID: row.clientId, subjectID: row.subjectId,
                                       weightLbs: p.weightLbs, note: p.note, occurredAt: row.occurredAt,
                                       tombstoned: false, serverSeq: row.serverSeq, dirty: false))
        }
        try context.save()
    }

    public func pullCursor(subjectID: UUID) throws -> Int64 {
        try allCursors().first(where: { $0.subjectID == subjectID })?.seq ?? 0
    }

    public func setPullCursor(subjectID: UUID, _ seq: Int64) throws {
        if let c = try allCursors().first(where: { $0.subjectID == subjectID }) {
            c.seq = seq
        } else {
            context.insert(SyncCursor(subjectID: subjectID, seq: seq))
        }
        try context.save()
    }

    /// Inspection helper (live, non-tombstoned weights for a subject) — used by
    /// tests and useful to callers.
    public func liveWeights(subjectID: UUID) throws -> [WeightEntry] {
        try allEntities().filter { $0.subjectID == subjectID && !$0.tombstoned }
    }

    // Harness-scale: fetch-all + filter in Swift (avoids #Predicate UUID quirks).
    private func allEntities() throws -> [WeightEntry] { try context.fetch(FetchDescriptor<WeightEntry>()) }
    private func allCursors() throws -> [SyncCursor] { try context.fetch(FetchDescriptor<SyncCursor>()) }
    private func entity(_ clientID: UUID) throws -> WeightEntry? {
        try allEntities().first(where: { $0.clientID == clientID })
    }
}
