# PRD Amendments

[docs/PRD.md](./PRD.md) is preserved as received (Draft v1, 2026-08-04). Where the
build deliberately departs from it, the departure is recorded here rather than by
editing the spec — so the original reasoning stays legible and the deltas stay
reviewable.

**Read this alongside the PRD. Where they conflict, this file wins.**

---

## A1 — No backend. The app is fully on-device.

**Supersedes:** §6 (architecture), §8 (Postgres schema), §11 (TLS, device token),
and the backend half of §5.

**Decision (2026-08-04):** There is no FastAPI/Postgres/Redis backend. Storage is
SwiftData, backup is CloudKit, and Claude is called directly from the app.

**Rationale:** The backend's primary job in the PRD was keeping the Anthropic API key
off the device (§6, §11). That constraint is load-bearing for a distributed app; for
a single-user app that is never shipped to anyone else, it buys little. The threat
model collapses from "the key is in every App Store binary" to "someone extracts the
key from my own phone."

Every other decision the backend supported survives the move — only the substrate
changes:

| Decision | Intent | On-device form |
|---|---|---|
| D1 | Historical scores reproducible | Versioned plan records in SwiftData |
| D2 | One set of stored numbers | Computed at ingestion, stored, read everywhere |
| D3 | Scorer and chat can't diverge | One context builder in `MaximizeCore` |
| D6 | Chat survives reinstall | SwiftData + CloudKit |
| D7 | HR series as a blob | Unchanged |
| D8 | Immutable auto-score | Unchanged |

**What this buys:** deletes an entire stack (FastAPI, Postgres, Redis, Alembic,
docker-compose, deployment) and removes the network from the read path, so §11's
offline requirement is satisfied by construction rather than by feature work. It also
moves the numerically critical logic — metrics, classification, scoring, tallies —
into a pure Swift package that CI fully verifies.

**What it costs:** see A5.

## A2 — FR-0.4 (background `URLSession` upload) is removed.

There is no server to upload to. Ingestion writes straight to the local store. The
reliability requirement it served (§11, "at-least-once delivery, idempotent
ingestion") still holds and is satisfied by dedupe on `workoutUUID` at write time.

## A3 — Device-token auth is removed.

**Supersedes:** §3 non-goals ("auth is a device token, nothing more") and §11.
Nothing to authenticate to. The only credential in the system is the Anthropic API
key (A5).

## A4 — Redis caching is removed.

**Supersedes:** §8 ("cache in Redis if needed"). Tallies are computed on read from
the local store; at single-user volume this is trivially fast. If it ever isn't,
cache in memory.

## A5 — The Anthropic API key lives in Keychain, on-device.

**Supersedes:** §6 ("The Anthropic API key never touches the device") and §11.

Accepted consequence of A1. Bounded by two conditions:

1. The app is single-user and is **never distributed**.
2. **Tripwire:** if condition 1 ever stops holding, the key must move behind a server
   *before* the app ships. This is a release blocker, not a follow-up.

## A6 — §14.1 resolved: rest-day conversion is **automatic**.

**Resolves:** the open sub-decision in §14.1, which the PRD left to the owner.

The system spends the weekly rest-day budget automatically on the least-costly missed
days, rather than requiring the user to tap a red day. Chosen for consistency with the
north star ("never hand-type a workout log row again" — §2); a manual conversion tap
is exactly the kind of bookkeeping the product exists to remove.

**Known trade-off, from the PRD's own analysis:** automatic conversion will sometimes
forgive a day the user would rather see as a miss, because "that was a real rest day"
is a judgment the system cannot reliably infer. If the calendar starts reading as too
generous, the fix is to revisit the selection heuristic — or fall back to manual — not
to widen the budget.

## A7 — §14.2 resolved: the accent is the violet **`#8E7CFF`** (dark) / **`#5B3FE8`** (light).

**Resolves:** the open sub-decision in §14.2, which the PRD left to the owner and
marked non-blocking.

**Decision (2026-08-05, MAX-084):** ratify the values MAX-040 committed as a working
default. In full, all four appearances:

| | Standard | Increase Contrast |
|---|---|---|
| Dark | `#8E7CFF` | `#B3A6FF` |
| Light | `#5B3FE8` | `#3B22C4` |

No code changes: the values are already in
`Sources/MaximizeCore/Accessibility/DesignPalette.swift`. What changes is their
status — they were "a defensible default, not a decision" (`ColorTokens.swift`), and
they are now the decision. Re-theming stays a one-line edit if the owner disagrees.

**Why this one.** The accent has to survive three collisions the PRD sets up, and
violet is the only region of the wheel far from all three at once: it is not
Robinhood's green (`#00C805`, named in the PRD), it is not any of the three score
bands, and it is not the untinted iOS system blue that users read as "no design was
applied here".

**It measures well in every appearance**, which matters more than it might sound,
because the accent is about to move from two call sites to every tab label, picker
segment and button title in the app (design review §3.1). Those are *text*, so 4.5:1
is the bar, not 3:1:

| Pair | Dark | Light | Dark, IC | Light, IC |
|---|---|---|---|---|
| accent on `surface` | 6.06:1 | 6.32:1 | 9.82:1 | 9.49:1 |
| accent on `surfaceElevated` | 5.56:1 | 5.81:1 | 7.90:1 | 8.14:1 |
| accent on `surfaceInset` | 5.05:1 | 5.32:1 | 7.01:1 | 7.22:1 |
| `textOnSaturatedFill` on accent | 6.06:1 | 6.32:1 | 9.18:1 | 9.49:1 |

Every figure clears AA for normal text against every surface level in both
appearances, and clears AAA (7:1) under Increase Contrast. `WCAGContrastTests` pins
the 6.06:1 figure and asserts the AA floor for the rest, so this table is checked on
every commit rather than trusted.

(The design review's appendix records 9.18:1 for dark Increase Contrast. That figure
pairs the Increase Contrast accent with the *standard* dark surface; against the
Increase Contrast surface — pure black — it is 9.82:1. Both clear AAA; the row above
is the pairing that actually renders.)

**Alternatives measured and rejected**, dark value against `surface`:

| Candidate | On `surface` | Against `scoreEffective` | Why not |
|---|---|---|---|
| Cyan `#32D6E0` | 11.07:1 | **1.14:1** | Sits at the same luminance as "this run went well", on screens that show both |
| Teal `#2FD4C4` | 10.60:1 | **1.09:1** | Same collision, worse |
| Electric blue `#4D9BFF` | 6.97:1 | 1.39:1 | Reads as system blue at a glance — the failure mode the brief names |
| Magenta `#FF4FD8` | 6.89:1 | 1.41:1 | Clears the bands, but is louder than a colour used "sparingly" (FR-4.3) should be |
| Lime `#C6F24E` | 15.17:1 | 1.56:1 | Same hue family as `scoreEffective`; also very loud |

The cyan and teal numbers are the interesting ones: both have excellent contrast
against the background and would still have been wrong, because contrast against the
*surface* is not the only constraint an accent has to meet.

**The one real argument against violet-on-near-black** is that it is a recognisable
current palette and a discerning viewer may find it familiar rather than distinctive.
Against that: this app is single-user and is never distributed (A5, A8), so "reads as
someone else's brand" costs nothing.

**What this does not settle.** The accent still reaches almost nothing the system
draws — `.tint()` is called nowhere in `App/` — so ratifying the value does not by
itself make the app look accented. That is a separate ticket (design review §3.1).

## A8 — CloudKit backup is deferred. D6 is downgraded to on-device durability.

**Amends A1**, which named CloudKit as the backup half of the on-device architecture.

The app is signed with a free Apple Developer personal team, and free provisioning does
not grant the iCloud container or CloudKit service entitlements. Requesting them made
the device build unsignable — and the device build is the only build that can exercise
zero-touch capture at all, since the Simulator cannot run HealthKit background delivery.
Given the choice between the backup path and the product's central claim, the central
claim wins.

**What this costs, stated plainly.** D6 says chat threads are persisted and survive
reinstall. They now survive *relaunch*, not reinstall: delete the app and the history
goes with it, and a second device starts empty. Nothing else regresses — capture,
scoring, metrics, chat and every screen are local and unaffected.

**Why the schema does not change.** MAX-020 built every model to CloudKit's
restrictions: no `@Attribute(.unique)`, no non-optional property without a default, no
required relationships. Those constraints are now unenforced by anything, and they stay
anyway. They cost nothing to keep and they are what makes re-enabling mirroring a
two-line change — the entitlements block in `project.yml` and `makeOnDisk`'s
`cloudKitDatabase` default — rather than a migration of an already-populated store.
Removing them would be spending real future work to buy nothing today.

**The trap this closed on the way past.** `makeOnDisk` defaulted to
`cloudKitDatabase: .automatic`, and against a build with no iCloud entitlement that is
not a harmless no-op: container creation fails, `PersistenceComposition.store` becomes
nil, and the app runs with no storage — capturing nothing while appearing to work,
because every failure on that path is already designed to be survivable. The default is
now `.none`.

**Tripwire, in the same spirit as A5's:** if this app is ever distributed, or if a
second device is ever expected to see the same history, CloudKit is not optional and
D6 is not satisfied. Do not let "it has worked fine for months" stand in for backup —
it has worked fine because there is only one device and nobody has reinstalled.

---

## Requirements unaffected

Everything in §7 (features), §9 (metric definitions), §10 (scoring logic), §13 (risks)
stands as written. The scoring rubric, the derived-metric definitions, and the design
direction in §7.4 are unchanged by the move on-device.
