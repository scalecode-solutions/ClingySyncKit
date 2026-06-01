import XCTest
import SwiftData
import Foundation
import CryptoKit
@testable import ClingySyncKit

/// Real-wire integration: drives the EnvelopeClient against a *running*
/// clingy2_api. Skips unless both env vars are set:
///   CLINGY2_RPC_URL    e.g. http://localhost:6064/v1/rpc
///   CLINGY2_TOKEN_KEY  base64 of the server's AUTH_TOKEN_KEY (shared mode)
///
/// So `swift test` stays green standalone; this runs when orchestrated against
/// a local clingy2_api + Postgres.
final class IntegrationTests: XCTestCase {

    private struct Env {
        let url: URL
        let keyB64: String
    }

    private func env(_ t: XCTestCase) throws -> Env {
        guard let urlStr = ProcessInfo.processInfo.environment["CLINGY2_RPC_URL"],
              let url = URL(string: urlStr),
              let key = ProcessInfo.processInfo.environment["CLINGY2_TOKEN_KEY"], !key.isEmpty
        else {
            throw XCTSkip("CLINGY2_RPC_URL / CLINGY2_TOKEN_KEY unset — skipping real-wire integration")
        }
        return Env(url: url, keyB64: key)
    }

    /// Mint an mvServer-style HS256 JWT (uid claim) signed with the shared key.
    private func mintToken(uid: String, keyB64: String, exp: Date = Date().addingTimeInterval(3600)) -> String {
        func b64url(_ d: Data) -> String {
            d.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let key = Data(base64Encoded: keyB64) ?? Data()
        let header = Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8)
        let payload = Data("{\"uid\":\"\(uid)\",\"exp\":\(Int(exp.timeIntervalSince1970))}".utf8)
        let input = b64url(header) + "." + b64url(payload)
        let sig = HMAC<SHA256>.authenticationCode(for: Data(input.utf8), using: SymmetricKey(data: key))
        return input + "." + b64url(Data(sig))
    }

    private func client(_ e: Env, token: String?) -> EnvelopeClient {
        EnvelopeClient(endpoint: e.url, tokenProvider: { token })
    }

    private func makeDevice(_ e: Env, token: String) throws -> (TrackerSync, SwiftDataLocalStore, ModelContext) {
        let container = try ModelContainer(
            for: WeightEntry.self, SyncCursor.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = ModelContext(container)
        let store = SwiftDataLocalStore(context: ctx)
        let transport = EnvelopeSyncTransport(client: client(e, token: token))
        return (TrackerSync(transport: transport, store: store), store, ctx)
    }

    // The envelope round-trips over the real wire (ping = no auth; whoami = auth).
    func testRealEnvelope_PingAndWhoami() async throws {
        let e = try env(self)
        let uid = UUID()
        let token = mintToken(uid: uid.uuidString, keyB64: e.keyB64)

        struct PingReq: Encodable { let echo: String }
        struct PingRes: Decodable { let pong: Bool; let echo: String }
        let ping: PingRes = try await client(e, token: nil).send("ping", PingReq(echo: "wire"))
        XCTAssertTrue(ping.pong)
        XCTAssertEqual(ping.echo, "wire")

        struct Empty: Encodable {}
        struct Who: Decodable { let userId: String }
        let who: Who = try await client(e, token: token).send("whoami", Empty())
        // Go's uuid.String() is lowercase; Swift's UUID.uuidString is uppercase.
        // UUIDs are case-insensitive — compare as UUIDs, not raw strings.
        XCTAssertEqual(UUID(uuidString: who.userId), uid)
    }

    // Two clients of one owner converge through the real server: create → delete.
    func testRealSync_TwoClientsConverge() async throws {
        let e = try env(self)
        let token = mintToken(uid: UUID().uuidString, keyB64: e.keyB64)
        let (syncA, _, ctxA) = try makeDevice(e, token: token)
        let (syncB, storeB, ctxB) = try makeDevice(e, token: token)
        let subject = UUID()
        let c1 = UUID()

        ctxA.insert(WeightEntry(clientID: c1, subjectID: subject, weightLbs: 158, note: "wire"))
        try ctxA.save()
        try await syncA.sync(subjectID: subject)
        try await syncB.sync(subjectID: subject)

        let bw = try storeB.liveWeights(subjectID: subject)
        XCTAssertEqual(bw.count, 1)
        XCTAssertEqual(bw.first?.weightLbs, 158)

        // delete → tombstone converges through the real server.
        let e2 = try XCTUnwrap(try storeB.liveWeights(subjectID: subject).first)
        e2.tombstoned = true
        e2.dirty = true
        try ctxB.save()
        // delete originates on B this time (proves either side can mutate).
        try await syncB.sync(subjectID: subject)
        try await syncA.sync(subjectID: subject)
        XCTAssertEqual(try storeB.liveWeights(subjectID: subject).count, 0)
    }
}
