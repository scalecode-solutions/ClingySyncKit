# ClingySyncKit — Status, History, and V6 Migration Notes

Written: 2026-07-15 (deep-dive session; read-only investigation, no code changed).
Purpose: the package's comments froze at its birth and there is no README, which
has caused repeated misreads (an AI called it "a WIP, maybe discard it"). This
doc is the corrective record until the comments/README are properly updated.

---

## TL;DR

**ClingySyncKit is NOT a WIP.** It is a shipped, tagged (v0.1.0), production
dependency of live Clingy — the tracker sync layer, syncing ~40 tracker types.
Discarding it would sever sync in a shipping app. What *is* stale is its
self-description: the "proving harness / dummy client" narration in the
comments describes its June 1 origin, not its current role.

---

## 1. The v5/v6 confusion, explained

`Package.swift` is `swift-tools-version: 6.0` but pins both targets to
`.swiftLanguageMode(.v5)` with the note:

> `// proving harness; tighten to v6 concurrency at Clingy integration`

- **Why it happened**: the package was born (commit `5a419fb`, 2026-06-01) as a
  macOS-only, `swift test`-able proving harness against clingy2_api. v5 mode
  made everything compile without solving the actor-isolation design questions.
- **The note is a broken promise**: "at Clingy integration" — the integration
  HAS happened (Clingy consumes it as a remote SPM,
  `github.com/scalecode-solutions/ClingySyncKit`, pinned upToNextMajor from
  0.1.0, resolved to `7033ccc`). The tightening never did.
- **Why it compiles anyway**: language mode is per-module. Clingy builds
  `SWIFT_VERSION = 6.0` and its own code is checked strictly; the kit's
  internals are checked at v5 leniency; `@unchecked Sendable` silences the
  boundary. Clingy's wrapper hand-carries the isolation guarantees the kit
  never declares (`@MainActor Clingy2Sync`, explicitly-`@Sendable` token
  closure, `@unchecked Sendable` on `ClingyTrackerSyncStore`).
- **Prior art**: Travis already called out this exact pattern on 2026-06-14
  (mvServer session `4b56050a`): *"the AI sneaks in swift5 even when swift6 is
  sitting right there... 'we will knock it out during integration' lol"* — the
  assistant conceded the comment is "load-bearing tech debt." That exchange is
  why PulseKit and TraxKit were scaffolded `.swiftLanguageMode(.v6)`, zero
  `@unchecked`, from line one.

## 2. The active cost of the v5 debt

`Clingy2Sync.swift:13-15` (live Clingy): *"We inline the kit's push-then-pull
(its `TrackerSync` is nonisolated and would touch the context off-main) while
still using its store / transport / message types."*

Because the kit never declared isolation, Clingy could not use `TrackerSync`
and reimplemented the reconciler loop inline. **The kit's flagship class is
dead code to its only consumer** — purely because of the deferred v6 work.
What Clingy actually consumes: the DTOs (`Messages.swift`), `EnvelopeClient`,
`EnvelopeSyncTransport`, and the `LocalStore` contract (`LogRecord`/`LogRow`).

## 3. V6 migration plan (assessed 2026-07-15, not yet executed)

Effort: ~1 hour package-side; a focused half-day end-to-end including the
Clingy bump and verification. ~450 lines source + ~240 tests.

Package-side:

| File | Change |
|---|---|
| `Package.swift:13,18` | `.v5` → `.v6` |
| `EnvelopeClient.swift` | `tokenProvider` → `@Sendable () -> String?`; drop `@unchecked` (all stored props then Sendable `let`s). Source-compatible: Clingy already passes a `@Sendable` closure. |
| `LocalStore.swift` | **See §4 — do NOT pin `@MainActor`.** Make the methods `async throws` (isolation-agnostic contract). |
| `TrackerSync.swift` | Needs no isolation of its own once the store contract is async — it just awaits. |
| `SwiftDataStore.swift` | `@MainActor` on `SwiftDataLocalStore` (reference/test impl; holds a bare `ModelContext`). |
| `Envelope.swift` | add `Sendable` to `EnvelopeError` (public, cross-module). |
| `Messages.swift` / `JSONValue.swift` / `SyncTransport.swift` | already clean (Sendable structs / internal value enum). |
| Tests | `FakeSyncTransport` → actor (its protocol methods are already async; kills the `@unchecked`). Test classes `@MainActor`. |

Consumer-side:
- `@MainActor`-or-async protocol change is API-breaking → tag **0.2.0**; the
  0.x `upToNextMajor` pin admits it. Clingy is the sole consumer; coordinated
  two-repo bump.
- `ClingyTrackerSyncStore` conforms to the async contract and drops its
  `@unchecked Sendable`.
- Optional, SEPARATE change (do not bundle): un-inline Clingy2Sync's push/pull
  back onto the kit's `TrackerSync`. Clingy's inline loop has diverged
  (multi-journey iteration, phase timing, hash-scan dirty detection) — own
  change, own verification.

Verification path: `swift test` (macOS) → `IntegrationTests` against running
clingy2_api → local-package override into Clingy, iOS sim build under strict
v6 both sides → live sync smoke → tag 0.2.0, restore remote pin.

## 4. Correction: the contract must be isolation-AGNOSTIC, not @MainActor

An earlier pass in this session recommended annotating `LocalStore` and
`TrackerSync` `@MainActor` ("the settled lesson"). **That was wrong** — it
conflicts with the cleanroom plan's final form
(`Clingy/Documentation/archive/2026-06/cleanroom-overhaul-plan.md` §5.2):

> "**`@ModelActor` engine** off the main actor (sync + photo blob I/O)" —
> gated on proving `@Query` refreshes from background saves on device.

Pinning the kit's protocol to `@MainActor` would bake into the API contract
the exact thing twin Phase 4 plans to undo, forcing a second breaking bump.
Instead: `async throws` methods on `LocalStore`, so a `@MainActor` class
(today) and a `@ModelActor` engine (Phase 4) both conform naturally.
The "main-actor store, NOT background ModelActor" lesson remains true for the
*current* engine and for PulseKit — it describes today's proven configuration,
not the contract's ceiling.

## 5. Boot-delay side quest (2026-07-15 console log reading)

A cold-launch sim log showed five main-actor watchdog trips (288/500/745/325/
344ms) and `pendingPush ... took=254ms dirty=0`. Before re-opening the stall
hunt, note the June resolution (cleanroom-overhaul-plan.md:240-252 + the
launch-post-splash-stall-investigation doc):

- **lldb attachment inflates main-actor work ~6x.** Untethered device traces:
  cold launch fully interactive in ~1.3s with ZERO gaps; pendingPush **33ms**
  (the 208-254ms figures are debugger artifacts).
- ModelActor slice → twin Phase 4, "zero live urgency."
- The cheapest remaining boot lever needs no isolation work at all: §5.2
  **trigger policy** — defer first sync until first interactive frame,
  debounce foreground re-syncs. The coalescer (isSyncing) landed; the
  defer-past-first-frame part has not.

## 6. The three-layer model (why "WIP" keeps getting misdiagnosed)

| Layer | What it is | Status |
|---|---|---|
| 1. The artifact | ClingySyncKit v0.1.0: envelope client, DTOs, LocalStore contract, reconciler | **Done, shipping, load-bearing** |
| 2. The kit's roadmap | v0.2 wishlist: `logs.head`, `logs.sync`, `files.list` filter (three-repo train, cleanroom §5.1); the v6 flip; doc fixes | Planned, not started |
| 3. The consumer's engine | Clingy-side final form: `@ModelActor` engine, history-based dirty detection, pass cancellation, trigger policy (cleanroom §5.2, staged via the Clingy-tester twin) | Twin-phase roadmap, deliberately unhurried |

"Has planned next versions" ≠ "work in progress." By the discard-the-WIP
logic, live Clingy itself would be discardable — it's the primary subject of
the same roadmap. The kit is a finished dependency the plan builds ON, with a
wishlist attached.

## 7. Cheap inoculation (recommended, not yet done)

- Add a README: "production dependency of Clingy (tracker sync layer);
  `SwiftDataLocalStore`/`WeightEntry` are the reference/test store, Clingy
  provides `ClingyTrackerSyncStore` over its real @Models."
- Reword the stale birth-narration comments: `Package.swift:13`,
  `TrackerSync.swift:5`, `LocalStore.swift:22`, `SwiftDataStore.swift:4`.
- Any AI suggesting cleanup of "unused packages" must grep the consumer's
  pbxproj/Package.resolved first.

## References

- Kit commits: `5a419fb` (package + harness, 2026-06-01), `d2f7daa`
  (real-wire integration tests), `7033ccc` (iOS 17 platform, = tag 0.1.0).
- Clingy pin: `Clingy.xcodeproj/project.pbxproj` XCRemoteSwiftPackageReference,
  upToNextMajorVersion from 0.1.0; Package.resolved at `7033ccc`.
- Consumer wrapper: `Clingy/Services/Sync/Clingy2Sync.swift`,
  `ClingyTrackerSyncStore.swift` (+ ~40 mappers).
- Cleanroom plan: `Clingy/Documentation/archive/2026-06/cleanroom-overhaul-plan.md`
  (status header: ACTIVE ROADMAP; twin = Clingy-tester).
- Stall investigation: `Clingy/Documentation/archive/2026-06/launch-post-splash-stall-investigation.md`.
- The 2026-06-14 "AI sneaks in swift5" exchange: smc session
  `4b56050a-8198-42db-a069-a55a14b10cc1` (~lines 1002-1016).
- The `tombstoned`-not-`deleted` SwiftData collision lesson:
  `SwiftDataStore.swift:9-11` — keep that name.
