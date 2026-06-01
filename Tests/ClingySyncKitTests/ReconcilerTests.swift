import XCTest
import SwiftData
@testable import ClingySyncKit

final class ReconcilerTests: XCTestCase {

    /// A fresh in-memory device: SwiftData container + store + reconciler sharing
    /// the given transport (so multiple devices share one "server").
    private func makeDevice(_ transport: SyncTransport) throws -> (TrackerSync, SwiftDataLocalStore, ModelContext) {
        let container = try ModelContainer(
            for: WeightEntry.self, SyncCursor.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = ModelContext(container)
        let store = SwiftDataLocalStore(context: ctx)
        return (TrackerSync(transport: transport, store: store), store, ctx)
    }

    /// The full client-side proof: two devices sharing one server converge
    /// through create → edit → delete.
    func testTwoDeviceConvergence() async throws {
        let server = FakeSyncTransport()
        let (syncA, storeA, ctxA) = try makeDevice(server)
        let (syncB, storeB, _) = try makeDevice(server)
        let subject = UUID()
        let c1 = UUID()

        // A creates a weight, syncs; B syncs and converges.
        ctxA.insert(WeightEntry(clientID: c1, subjectID: subject, weightLbs: 150, note: "am"))
        try ctxA.save()
        try await syncA.sync(subjectID: subject)
        try await syncB.sync(subjectID: subject)

        let bWeights = try storeB.liveWeights(subjectID: subject)
        XCTAssertEqual(bWeights.count, 1)
        XCTAssertEqual(bWeights.first?.weightLbs, 150)
        XCTAssertEqual(bWeights.first?.note, "am")

        // A edits → converges to B.
        let aEntity = try storeA.liveWeights(subjectID: subject).first!
        aEntity.weightLbs = 152
        aEntity.dirty = true
        try ctxA.save()
        try await syncA.sync(subjectID: subject)
        try await syncB.sync(subjectID: subject)
        XCTAssertEqual(try storeB.liveWeights(subjectID: subject).first?.weightLbs, 152)

        // A deletes → tombstone converges; both go to zero.
        let aEntity2 = try storeA.liveWeights(subjectID: subject).first!
        aEntity2.tombstoned = true
        aEntity2.dirty = true
        try ctxA.save()
        try await syncA.sync(subjectID: subject)
        try await syncB.sync(subjectID: subject)
        XCTAssertEqual(try storeA.liveWeights(subjectID: subject).count, 0)
        XCTAssertEqual(try storeB.liveWeights(subjectID: subject).count, 0)
    }

    /// Re-syncing with nothing dirty is a no-op (no dupes), and the pull cursor
    /// advances so a second pull returns nothing new.
    func testIdempotentResync() async throws {
        let server = FakeSyncTransport()
        let (syncA, storeA, ctxA) = try makeDevice(server)
        let subject = UUID()

        ctxA.insert(WeightEntry(subjectID: subject, weightLbs: 140))
        try ctxA.save()
        try await syncA.sync(subjectID: subject)
        let cursor1 = try storeA.pullCursor(subjectID: subject)
        XCTAssertGreaterThan(cursor1, 0)

        // Second sync: nothing dirty, nothing new — no duplicates, cursor stable.
        try await syncA.sync(subjectID: subject)
        XCTAssertEqual(try storeA.liveWeights(subjectID: subject).count, 1)
        XCTAssertEqual(try storeA.pullCursor(subjectID: subject), cursor1)
    }

    /// Offline edits accumulate and reconcile on the next sync.
    func testOfflineThenSync() async throws {
        let server = FakeSyncTransport()
        let (syncA, storeA, ctxA) = try makeDevice(server)
        let (syncB, storeB, _) = try makeDevice(server)
        let subject = UUID()

        // Two creates while "offline" (no sync yet).
        ctxA.insert(WeightEntry(subjectID: subject, weightLbs: 160))
        ctxA.insert(WeightEntry(subjectID: subject, weightLbs: 161))
        try ctxA.save()

        // Reconnect: one sync pushes both; B converges to both.
        try await syncA.sync(subjectID: subject)
        try await syncB.sync(subjectID: subject)
        XCTAssertEqual(try storeB.liveWeights(subjectID: subject).count, 2)
    }
}
