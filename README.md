# ClingySyncKit

**Production dependency of Clingy** — the tracker sync layer. Live Clingy
consumes this as a remote SPM (pinned `upToNextMajor` from 0.1.0) and syncs
~40 tracker types through it against `clingy2_api`. It is not a prototype,
not a harness, not a WIP. Do not discard; see `STATUS.md` for the full
status/history record.

## What it provides

| File | Role |
|---|---|
| `EnvelopeClient.swift` | Generic typed-envelope RPC client over HTTP (`{type, data}` → typed response or structured `EnvelopeError`). App-agnostic; auth via injected token provider. |
| `SyncTransport.swift` | Narrow transport protocol + `EnvelopeSyncTransport` (the real impl over `EnvelopeClient`). |
| `Messages.swift` | The `logs.*` wire DTOs, matching clingy2_api's envelope `data` shapes exactly. Payloads ride inline as JSON (via `JSONValue`), not base64 blobs. |
| `LocalStore.swift` | The reconciler's local-persistence contract (`LogRecord` + `LocalStore`). Each app implements it over its own models. |
| `TrackerSync.swift` | The offline-first reconciler: push dirty → pull delta by `server_seq` cursor, LWW, tombstones. |
| `Envelope.swift` / `JSONValue.swift` | Wire envelope types, error vocabulary, RFC3339-tolerant coders. |

## Reference vs. production pieces

`SwiftDataStore.swift` (`SwiftDataLocalStore`, `WeightEntry`, `SyncCursor`)
is the **reference/test implementation** of `LocalStore` — a stand-in data
layer used by the test suite. Clingy does not use it; Clingy provides its own
`ClingyTrackerSyncStore` (+ one mapper per synced type) over its real
`@Model`s. Reading `WeightEntry` as "toy model, therefore toy package" is the
classic misread — the toy is the fixture, not the product.

Note: live Clingy currently inlines the push/pull loop (its sync driver is
`@MainActor`; `TrackerSync` is nonisolated pending the v6 pass below) while
using the kit's client, transport, DTOs, and store contract.

## Hard-won rules

- A synced `@Model` must NOT name a field `deleted` — it collides with
  `NSManagedObject.isDeleted` under SwiftData and silently fails to persist.
  Use `tombstoned`. (Found by this package's test harness; keep the name.)

## Language mode (known debt)

Targets are pinned `.swiftLanguageMode(.v5)` under the 6.0 toolchain. The
consumer (Clingy) is Swift 6 strict and hand-carries the isolation guarantees
at the boundary. The planned v6 pass — `@Sendable` token provider, an
isolation-agnostic (`async throws`) `LocalStore` contract, zero `@unchecked`
— is scoped in `STATUS.md` §3–4 and ships as a breaking 0.2.0.

## Testing

```sh
swift test          # reconciler suite — no server needed (FakeSyncTransport)
```

`IntegrationTests.swift` runs real-wire against a locally running
`clingy2_api` (see the test file for gating).

## Platforms

macOS 14+ (so `swift test` works) and iOS 17+ (SwiftData floor; the consumer
target). Zero dependencies.
