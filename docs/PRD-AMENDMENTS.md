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

## A7 — §14.2 (accent color) still open.

Non-blocking, as the PRD notes. MAX-040 (design system) will define it as a single
token so changing it later is a one-line edit.

---

## Requirements unaffected

Everything in §7 (features), §9 (metric definitions), §10 (scoring logic), §13 (risks)
stands as written. The scoring rubric, the derived-metric definitions, and the design
direction in §7.4 are unchanged by the move on-device.
