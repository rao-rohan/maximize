# Maximize — Project Tracker

**Last updated:** 2026-08-04
**Spec:** [docs/PRD.md](./docs/PRD.md) + [docs/PRD-AMENDMENTS.md](./docs/PRD-AMENDMENTS.md) (amendments win)
**Architecture:** Fully on-device. No backend.
**Pipeline status:** 🟢 CI green — `swift build` + `swift test` verified running on macOS

---

## How this document works

Single source of truth for what is left to build. Committed to the repo and updated in
the same PR as the work it describes — a ticket's status changing is part of the diff.

Every ticket traces to a PRD requirement. When the spec changes, this document is
re-derived and the delta called out explicitly rather than quietly merged.

The overseer owns decomposition, agent assignment, review, and integration. Subagents
get one scoped ticket with acceptance criteria — never an open-ended goal.

## Agent tiering policy

| Tier | Use for | Examples here |
|---|---|---|
| **Haiku** | Mechanical, fully specified, low blast radius. The answer is known; it needs typing. | Summary tiles, interval selector, settings screen, fixtures |
| **Sonnet** | Standard feature work against a clear spec. Judgment within known patterns. | A screen, a chart, an adapter, a test suite |
| **Opus** | Architecture, numerically subtle, or expensive to get wrong. | Domain types, plan versioning, derived metrics, classification, scorer, streaming, drift overlay, HealthKit background delivery |

Escalation rule: a Haiku/Sonnet ticket that turns out to need a design decision gets
reported back, not decided unilaterally. The overseer re-tiers it.

## Ticket lifecycle

`Backlog` → `Ready` → `In progress` → `In review` → `Merged`

**Ready** = acceptance criteria written and dependencies merged. **In review** = CI green
and a code review has run. Definition of done lives in [CLAUDE.md](./CLAUDE.md).

---

## Board

Status key: ✅ merged · 🔲 ready · ⬜ blocked on dependencies

### Phase 0 — Foundation

| ID | Ticket | Spec | Tier | Status | Depends on |
|---|---|---|---|---|---|
| MAX-001 | Repo conventions, `.gitignore`, `CLAUDE.md` | — | — | ✅ | — |
| MAX-002 | `MaximizeCore` package skeleton + smoke test | — | — | ✅ | — |
| MAX-003 | CI: build, test, architecture guard | — | — | ✅ | — |
| MAX-004 | Project tracker | — | — | ✅ | — |
| MAX-005 | Vendor PRD, record amendments, revise conventions for on-device | A1–A7 | — | ✅ | — |
| MAX-006 | App shell: XcodeGen spec, iOS 26 SDK, simulator build in CI | §7.4 | Sonnet | 🔲 | MAX-005 |

Phase 0 was done directly by the overseer — delegating a `.gitignore` costs more than
it saves.

### Phase 1 — Domain core

**All of this lives in `MaximizeCore` as pure Swift, and CI verifies every line of it.**
This is the payoff from going on-device: the logic most expensive to get wrong is now
the logic most thoroughly tested. Nothing here touches a framework, a database, or a
network.

| ID | Ticket | Spec | Tier | Status | Depends on |
|---|---|---|---|---|---|
| MAX-010 | Domain value types: Workout, HR series, route, Plan, PlanDay, Score, Annotation | §8 | **Opus** | 🔲 | — |
| MAX-011 | Versioned plan + `PlanDay` calendar resolution | D1, §8 | **Opus** | ⬜ | MAX-010 |
| MAX-012 | Derived metrics: time-above-cap, HR drift, avg cadence, grade-adjusted pace, zone splits | §9, D2 | **Opus** | ⬜ | MAX-010 |
| MAX-013 | Workout classification (easy / hard / long / other) from type + HR profile | §10.2 | **Opus** | ⬜ | MAX-012 |
| MAX-014 | Context builder — the single assembler of what Claude sees | D3 | **Opus** | ⬜ | MAX-011, MAX-013 |
| MAX-015 | Scoring rubric application + effective threshold + rationale contract | §10, D1 | **Opus** | ⬜ | MAX-014 |
| MAX-016 | Rest-day budget: automatic conversion of missed days | D9, A6 | Sonnet | ⬜ | MAX-011 |
| MAX-017 | Tallies: workout-days, effective-days, avg score, streak, current week | FR-3.4, §8 | Sonnet | ⬜ | MAX-015, MAX-016 |

MAX-013 is Opus despite looking small: PRD §13 names plan/actual misclassification as
a risk that "poisons the score," and every downstream number inherits its mistakes.

### Phase 2 — Persistence & platform adapters

The seam between the pure core and iOS. Core defines value types and protocols; this
layer implements them and maps across the boundary.

| ID | Ticket | Spec | Tier | Status | Depends on |
|---|---|---|---|---|---|
| MAX-020 | SwiftData models + mapping to/from core types + repository implementations | §8, A1 | **Opus** | ⬜ | MAX-006, MAX-010 |
| MAX-021 | CloudKit sync so history survives reinstall | D6, A1 | Sonnet | ⬜ | MAX-020 |
| MAX-022 | Keychain-backed Anthropic key storage + settings entry point | A5, §11 | Sonnet 🔒 | ⬜ | MAX-006 |
| MAX-023 | Claude client: scoring call | §10, §11 | Sonnet 🔒 | ⬜ | MAX-022, MAX-015 |
| MAX-024 | Claude client: streaming chat transport | D10, FR-2.4 | **Opus** | ⬜ | MAX-022, MAX-014 |

🔒 = requires `/security-review` before merge.

### Phase 3 — Ingestion (zero-touch capture)

Mostly *not* CI-verifiable — HealthKit needs a device. Mitigation: anchor management,
dedupe, and payload assembly live in `MaximizeCore` behind protocols and are unit
tested; the HealthKit adapter stays a thin, decision-free shim. Per direction, we do
not block on device runs — but every PR here states plainly what a human must tap.

| ID | Ticket | Spec | Tier | Status | Depends on |
|---|---|---|---|---|---|
| MAX-030 | `HKObserverQuery` + background delivery + entitlement | FR-0.1 | **Opus** | ⬜ | MAX-006 |
| MAX-031 | Anchored incremental fetch with persisted anchor | FR-0.2 | Sonnet | ⬜ | MAX-030 |
| MAX-032 | Full-fidelity extraction: HR series, route, cadence, energy; indoor runs first-class | FR-0.3, FR-0.6 | Sonnet | ⬜ | MAX-031 |
| MAX-033 | Ingestion pipeline: dedupe on `workoutUUID`, compute + store derived metrics, trigger scoring | FR-0.5, D2, A2 | **Opus** | ⬜ | MAX-032, MAX-020, MAX-023 |

### Phase 4 — Design system & detail view

| ID | Ticket | Spec | Tier | Status | Depends on |
|---|---|---|---|---|---|
| MAX-040 | Design system: dark-first tokens, score bands, accent, Liquid Glass on chrome only, flat content surfaces | FR-4.1–4.4, A7 | **Opus** | ⬜ | MAX-006 |
| MAX-041 | Detail view: plan-verdict header | FR-1.1 | Sonnet | ⬜ | MAX-020, MAX-040 |
| MAX-042 | HR curve with cap line + time-above-cap shading | FR-1.2 | Sonnet | ⬜ | MAX-040, MAX-012 |
| MAX-043 | Cadence vs target band | FR-1.3 | Sonnet | ⬜ | MAX-042 |
| MAX-044 | Route map — outdoor only, omitted cleanly for treadmill | FR-1.4 | Sonnet | ⬜ | MAX-040 |
| MAX-045 | Splits + summary tiles | FR-1.5 | Haiku | ⬜ | MAX-040 |

FR-1.5 is explicitly "thin — displayed because cheap, not lovingly built." Tiered
Haiku to keep it that way.

### Phase 5 — Contextual chat

| ID | Ticket | Spec | Tier | Status | Depends on |
|---|---|---|---|---|---|
| MAX-050 | Per-workout thread persistence | D6, FR-2.3 | Sonnet | ⬜ | MAX-020 |
| MAX-051 | Chat UI with token-streaming reveal | FR-2.1–2.4, D10 | Sonnet | ⬜ | MAX-024, MAX-041, MAX-050 |

### Phase 6 — Dashboard

| ID | Ticket | Spec | Tier | Status | Depends on |
|---|---|---|---|---|---|
| MAX-060 | Interval selector: week / month / custom | FR-3.1 | Haiku | ⬜ | MAX-020 |
| MAX-061 | Score-colored calendar, type glyph, auto-converted rest days | FR-3.2, D4, D9, A6 | Sonnet | ⬜ | MAX-017, MAX-060, MAX-040 |
| MAX-062 | **Cross-run HR-drift overlay** on %-elapsed axis | FR-3.3, D5 | **Opus** | ⬜ | MAX-060, MAX-040, MAX-012 |
| MAX-063 | Summary tiles: mileage vs arc, effective days, streak, avg score | FR-3.4 | Haiku | ⬜ | MAX-017, MAX-060 |
| MAX-064 | Settings: rest-days-per-week, display/accessibility prefs | §8 | Haiku | ⬜ | MAX-020 |

### Phase 7 — Hardening

| ID | Ticket | Spec | Tier | Status | Depends on |
|---|---|---|---|---|---|
| MAX-070 | Accessibility: Reduce Transparency / Increase Contrast degrade to solid chrome | FR-4.5 | Sonnet | ⬜ | MAX-040 |
| MAX-071 | Scoring fixture suite: known-good runs → expected score bands | R7 | Sonnet | ⬜ | MAX-015 |
| MAX-072 | Security review: Keychain handling, data at rest, prompt minimization, distribution tripwire | §11, A5 | **Opus** 🔒 | ⬜ | MAX-023, MAX-024 |

### Deliberately not built

Live coaching · manual entry/editing · strength analysis · HealthKit writes · multi-user ·
nutrition · Claude on the dashboard tab · **any server component** (A1). PRD §3, §12.
Listed so nobody helpfully adds one.

---

## Sequencing

Critical path: **MAX-006 → MAX-010 → 011/012 → 013 → 014 → 015**. Scoring is the
product; every screen is a window onto it.

Two streams parallelize once MAX-006 and MAX-010 land: the pure core (Phase 1, no
device needed, fully testable) and the platform layer (Phase 2–3). Phase 1 should run
ahead — it has no external dependencies and it is where correctness is cheapest to
establish.

**MAX-062 (drift overlay) is the ticket that justifies the project** — PRD §13 says so
directly, and §5's "no other app can draw this" is the actual differentiator. It is
tiered Opus and must not be starved by polish on splits or the route map. PRD §13 names
scope discipline as the top execution risk, above any technical unknown.

## Open questions

| # | Question | Blocks | Status |
|---|---|---|---|
| Q1 | Accent color for the on-plan/effective state (PRD §14.2) | MAX-040 | Open, non-blocking — will land as a single token |
| Q2 | Do GitHub macOS runners offer Xcode 26 for the iOS 26 SDK / Liquid Glass? | MAX-006 | Overseer to verify at MAX-006 |

Resolved: backend architecture (→ A1, on-device) · existing-code question (greenfield) ·
rest-day conversion (→ A6, automatic).

## Risks

| # | Item | Impact | Status |
|---|---|---|---|
| R1 | No Swift toolchain in the dev container; `download.swift.org` blocked | CI is the only gate | Accepted — mitigated by fat-core architecture + macOS CI |
| R2 | No device/simulator in the loop | HealthKit flows, UI, on-device performance unverified until a human checks | Accepted per direction. PRs must list what needs device verification |
| R3 | Anthropic key on-device | Weakens PRD §6 | Accepted for single-user (A5). **Tripwire: blocks any distribution** |
| R5 | `com.apple.developer.healthkit.background-delivery` entitlement — PRD flags moderate confidence on the exact key | If wrong, the wake silently never happens and zero-touch capture dies | Open — MAX-030 verifies against Apple docs *first*, not last |
| R6 | Scoring correctness; auto-vs-manual divergence is the quality signal | Loop loses trust fast if scores disagree with judgment | D8 telemetry + MAX-071 fixtures; revisit rubric after real runs |
| R7 | Claude's *judgment* can't be unit-tested, only the rubric plumbing | Scoring regressions could pass CI green | MAX-071: fixture runs with known-good expected bands |
| R8 | Background-delivery wake windows are short; scoring makes a network call | Scoring may not finish in the wake window (PRD §2 p50 < 2 min) | MAX-033 to score lazily on first view if the wake budget is exceeded |

## Decision log

| Date | Decision | Rationale |
|---|---|---|
| 2026-08-04 | Logic lives in `MaximizeCore`; app target is a thin shell | Only way to get meaningful automated verification without Xcode in the loop |
| 2026-08-04 | CI on `macos-15` is the merge gate | Compiles the real toolchain; verified running tests, not a no-op check |
| 2026-08-04 | Do not block development on local Xcode runs | Per direction — tests are the gate; device issues handled when they surface |
| 2026-08-04 | CI mechanically rejects platform imports in the core | An architecture rule that isn't enforced is a suggestion |
| 2026-08-04 | `Package.resolved` is committed, not ignored | Ships an app, not a library — CI and dev machines must resolve identical versions |
| 2026-08-04 | **No backend; fully on-device** (A1) | Backend existed to keep the API key off-device; that buys little for a single-user app that is never distributed. Deletes a whole stack and makes the critical logic CI-testable |
| 2026-08-04 | API key in Keychain, with a distribution tripwire (A5) | Accepted cost of A1 — bounded by "never shipped to anyone else" |
| 2026-08-04 | Rest-day conversion is automatic (A6) | Consistent with the zero-touch north star; a conversion tap is the bookkeeping the product exists to remove |
| 2026-08-04 | PRD preserved verbatim; deltas recorded in a separate amendments file | Keeps the original reasoning legible and the deviations reviewable |
