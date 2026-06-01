import Foundation

/// The reconciler's dependency on the network — narrow + concrete so it's
/// trivially fakeable in tests. The real impl wraps the generic EnvelopeClient.
public protocol SyncTransport: Sendable {
    func upsert(_ req: UpsertReq) async throws -> UpsertRes
    func pull(_ req: PullReq) async throws -> PullRes
}

/// SyncTransport backed by the typed-envelope EnvelopeClient.
public struct EnvelopeSyncTransport: SyncTransport {
    let client: EnvelopeClient
    public init(client: EnvelopeClient) { self.client = client }

    public func upsert(_ req: UpsertReq) async throws -> UpsertRes {
        try await client.send("logs.upsert", req)
    }
    public func pull(_ req: PullReq) async throws -> PullRes {
        try await client.send("logs.pull", req)
    }
}
