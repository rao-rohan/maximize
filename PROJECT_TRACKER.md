# Maximize — Project Tracker

**Last updated:** 2026-08-04
**PRD status:** ⏳ Not yet received — feature tickets cannot be written until it lands.
**Pipeline status:** 🟡 CI authored, awaiting first green run.

---

## How this document works

This is the single source of truth for what is left to build. It is committed to the
repo and updated in the same PR as the work it describes — a ticket's status changing
is part of the diff, not an afterthought.

Every ticket traces back to a PRD requirement. When the PRD changes, this document is
re-derived from it and the delta is called out explicitly rather than quietly merged.

The overseer (Claude, this session) owns decomposition, agent assignment, review, and
integration. Subagents receive one scoped ticket with acceptance criteria — never an
open-ended goal.

## Agent tiering policy

Difficulty drives model choice. Over-provisioning is waste; under-provisioning shows
up as a bad architecture decision that is expensive to unwind three tickets later.

| Tier | Use for | Examples |
|---|---|---|
| **Haiku** | Mechanical, fully specified, low blast radius. The answer is known; it needs typing. | Boilerplate, DTO/model structs, test fixtures, doc updates, mechanical refactors |
| **Sonnet** | Standard feature work against a clear spec. Judgment needed, but within known patterns. | A screen, a service layer, a test suite, a well-understood integration |
| **Opus** | Architecture and anything expensive to get wrong. Decisions that later tickets build on. | Data model, persistence/sync, HealthKit boundary, AI/LLM integration, security-sensitive paths |

Escalation rule: if a Haiku or Sonnet ticket turns out to require a design decision,
the agent reports back rather than deciding. The overseer re-tiers it.

## Ticket lifecycle

`Backlog` → `Ready` → `In progress` → `In review` → `Merged`

- **Ready** means acceptance criteria are written and dependencies are merged.
- **In review** means CI is green and a code review has run.
- **Merged** means it is on `main`.

Definition of done lives in [CLAUDE.md](./CLAUDE.md) and applies to every ticket.

---

## Board

### Phase 0 — Foundation (no PRD dependency)

| ID | Ticket | Tier | Status | Notes |
|---|---|---|---|---|
| MAX-001 | Repo conventions, `.gitignore`, `CLAUDE.md` | — | ✅ Merged | Overseer, direct |
| MAX-002 | `MaximizeCore` package skeleton + smoke test | — | ✅ Merged | Overseer, direct |
| MAX-003 | CI: build, test, architecture guard | — | ✅ Merged | Overseer, direct |
| MAX-004 | This tracker | — | ✅ Merged | Overseer, direct |
| MAX-005 | iOS app shell via checked-in XcodeGen `project.yml` | Sonnet | 🔲 Ready | Text-based project spec so the Xcode project stays reviewable; adds simulator build to CI |

Phase 0 was done directly by the overseer rather than delegated — spawning an agent
to write a `.gitignore` costs more than it saves.

### Phase 1+ — Product

⏳ **Awaiting PRD.** No feature tickets exist yet. Writing them now would mean
inventing requirements, and inventing requirements is how a tracker becomes fiction.

On receipt of the PRD the overseer will produce: a requirement-to-ticket trace table,
a dependency-ordered board, tier assignments, and a proposed sequencing — delivered as
a PR for review before any feature code is written.

---

## Risks and open questions

| # | Item | Impact | Status |
|---|---|---|---|
| R1 | No Swift toolchain in the dev container; `download.swift.org` is blocked by network policy | Nothing compiles or tests locally — CI is the only gate | Accepted. Mitigated by fat-core architecture + CI on macOS runner |
| R2 | No device/simulator verification in the loop | UI, HealthKit permission flows, and on-device performance are unverified until a human checks | Accepted per direction (2026-08-04). PRs must list what needs device verification |
| R3 | Health/biometric data plus an AI backend raises privacy obligations | Could force rework late if decided late | **Open** — needs a PRD answer on what may leave the device |
| R4 | Backend scope unknown (solo app vs. app + server) | Materially changes the ticket graph | **Open** — needs a PRD answer |

## Decision log

| Date | Decision | Rationale |
|---|---|---|
| 2026-08-04 | Logic lives in `MaximizeCore`; app target is a thin shell | Only way to get meaningful automated verification without Xcode in the loop |
| 2026-08-04 | CI on `macos-15` runner is the merge gate | Compiles the real toolchain; strictly better than a Linux-only check |
| 2026-08-04 | Do not block development on local Xcode runs | Per direction — tests are the gate; device issues handled when they surface |
| 2026-08-04 | CI mechanically rejects `SwiftUI`/`UIKit`/`HealthKit` imports in the core | An architecture rule that isn't enforced is a suggestion |
