import Foundation

/// The offline-first reconciler: push local changes, then pull the server
/// delta. Generic over SyncTransport + LocalStore so it's reused unchanged by
/// the dummy harness and by Clingy.
///
/// Push-then-pull: our dirty edits become the server's latest (a fresh
/// server_seq), then the pull reflects them; remote edits resolve last-write-
/// wins by server_seq. Running timers (end == nil) are simply never marked
/// dirty by the store, so they stay local until committed.
public final class TrackerSync {
    private let transport: SyncTransport
    private let store: LocalStore

    public init(transport: SyncTransport, store: LocalStore) {
        self.transport = transport
        self.store = store
    }

    /// One full sync cycle for a subject.
    public func sync(subjectID: UUID) async throws {
        try await push(subjectID: subjectID)
        try await pull(subjectID: subjectID)
    }

    func push(subjectID: UUID) async throws {
        let dirty = try store.pendingPush(subjectID: subjectID)
        guard !dirty.isEmpty else { return }
        let items = dirty.map {
            UpsertItem(clientId: $0.clientID, type: $0.type, schemaVersion: $0.schemaVersion,
                       occurredAt: $0.occurredAt, payload: $0.payload, deleted: $0.deleted)
        }
        let res = try await transport.upsert(UpsertReq(subjectId: subjectID, logs: items))
        for r in res.results {
            try store.markSynced(clientID: r.clientId, subjectID: subjectID, serverSeq: r.serverSeq)
        }
    }

    func pull(subjectID: UUID) async throws {
        let since = try store.pullCursor(subjectID: subjectID)
        let res = try await transport.pull(PullReq(subjectId: subjectID, since: since))
        for row in res.logs {
            try store.applyRemote(row)
        }
        try store.setPullCursor(subjectID: subjectID, res.cursor)
    }
}
