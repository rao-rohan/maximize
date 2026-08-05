---
name: orchestrate
description: Run the overseer loop that turns a product idea into merged, reviewed code — write a spec or PRD, review it to a product and state-of-the-art UI standard, decompose it into parallel engineering tickets, assign each to a difficulty-appropriate model tier, dispatch them as subagents, review, and merge on green. Use this whenever the ask is bigger than one ticket: a new feature area, a pivot, "build out X", "let's finish the PRD", "spec this and then build it", "split this up and parallelize", "keep building until it's done", or any request to plan-then-execute across multiple agents. Also use it when picking which model tier a piece of work deserves, when deciding what can run in parallel, or when a batch of agent PRs needs shepherding to merge.
---

# The overseer loop

You are not the implementer. You are the person who decides *what gets built, in what
order, by whom, and whether it is good enough to merge*. Implementation is delegated;
judgement is not.

The loop has five stages and it cycles. Most requests drop you somewhere in the middle
of it rather than at the start — find the stage you are actually in and resume there.

```
    ┌─ 1. SPEC ──→ 2. REVIEW ──→ 3. DECOMPOSE ──→ 4. DISPATCH ──→ 5. LAND ─┐
    └──────────────────────── new work discovered ─────────────────────────┘
```

The single most important property of the loop is that **the board is the memory**. A
tracker file — `PROJECT_TRACKER.md` or whatever the project calls it — holds every
ticket, its status, its dependencies, its tier, and the reasoning behind it. Context
windows end. Agents finish and vanish. The board is what survives, so it is updated as
part of the work, not after it.

---

## 1. Spec

Before decomposing anything, there must be a document that says what is being built and
why. If the user handed you a PRD, that is it. If they handed you three sentences of
direction, **a spec is the first ticket**, and it is its own agent's job.

A spec ticket is worth its own agent because writing it well requires reading the whole
codebase, and that is exactly the work you do not want to spend your own context on.
Tier it Opus — a bad spec multiplies into a dozen bad tickets.

What to put in the brief for a spec agent:

- The user's direction **in their own words**, quoted. Paraphrase loses the constraint.
- What is already settled and is not theirs to re-open. Spec agents love to redesign the
  thing you asked them to specify. Name the decisions that are closed.
- The deliverable, concretely: a document at a named path, plus any amendments to
  existing docs, plus a **proposed ticket breakdown with the files each ticket touches**.
- An explicit "you are writing a proposal, not code" — otherwise you get both, and the
  code was written without review.
- Permission to disagree. A spec agent that finds the request incoherent should say so
  in the document rather than quietly building the incoherent thing.

**Relay clarifications to a running spec agent rather than restarting it.** If the user
refines the ask mid-flight, send the running agent a message; it keeps its context. Do
not spawn a second agent on the refined brief — you will get two specs that disagree.

**Renumber on landing.** A spec agent proposes ticket IDs, and while it was running you
almost certainly allocated some of those IDs to other work. Check for collisions before
committing its breakdown, and say in the document that you renumbered.

---

## 2. Review to standard

A spec that has not been reviewed is a first draft. Two reviews matter and they are
different jobs:

**Product review** — does this solve the user's actual problem, is anything load-bearing
missing, does it contradict a decision already made? You do this yourself. You have the
conversation history; a fresh agent does not.

**Design review** — is the UI at the standard of a current, well-made app? Dispatch this
as its own agent with its own ticket, and be specific about the bar. "Modernize it" gets
you nothing. Name the platform's current idioms, the accessibility floor, and the
project's own design tokens, and ask for findings with file:line, each one classified as
**defect** (it is wrong) or **taste** (it is defensible but could be better). The
distinction is what lets you triage.

A design review's findings become tickets like anything else. Do not let the agent fix
them in the same pass — a review that also rewrites is a review nobody can check.

**Verify a contrast or accessibility claim yourself before filing it.** These are cheap
to compute and agents get them wrong in both directions. A finding that survives your own
arithmetic is worth a ticket; one that does not wastes an agent.

---

## 3. Decompose

This is where the loop is won or lost, and it is the stage that most rewards slowing
down.

**A ticket is one logical change with a testable outcome.** If you cannot write its
acceptance criteria in three bullets, it is two tickets.

**Name the files each ticket touches.** This is not bureaucracy — it is the only way to
see collisions before two agents produce conflicting diffs of the same file. Write them
into the board. When two tickets share a file, either sequence them or merge them.

**Check that something calls what you are building.** The most expensive decomposition
error is a chain of tickets that each pass their tests and together do nothing, because
nothing ever invokes the first one. Before dispatching a wave, trace one path from a user
action to the new code. If you cannot, the missing ticket is the one you just found.

**Prefer wide over deep.** Three independent tickets dispatched together land faster than
one ticket that does all three, and each is separately reviewable. The constraint is
dependencies and shared files, not your own comfort.

**Front-load the shared pieces.** If four tickets all need the same conversion, type, or
formatter, write it first — yourself if it is small — and dispatch the four against it.
Four agents inventing the same helper produces four subtly different helpers.

### Tiering

Tier by **how many decisions the ticket contains**, not by how many lines it produces.

| Tier | Give it work that... | Signals |
|---|---|---|
| **Haiku** | has one obvious correct answer and no design latitude | wiring a value through, a rename, a settings toggle, mechanical follow-up |
| **Sonnet** | is a well-specified change in a pattern the codebase already demonstrates | a new view following existing views, a repository method, a test suite over defined behaviour |
| **Opus** | requires resolving a tension, designing an interface others depend on, or reasoning about correctness that tests cannot fully capture | specs, security-sensitive work, the first instance of a pattern, anything touching a locked architectural decision |

Two adjustments worth making deliberately:

- **Re-tier upward when a ticket turns out to be load-bearing.** A ticket that looked
  small but defines a type six others import is Opus work regardless of its size.
- **Cost is a real constraint and the user's call.** If they set a budget, respect it —
  and note that effort level is a lever separate from tier.

---

## 4. Dispatch

Send as many agents as are genuinely independent, in the same turn. Independence means:
no dependency between them, and no shared file.

**Give every agent its own worktree.** Parallel agents sharing one checkout is not a
slow-burn problem, it is immediate corruption: each one runs `git checkout -b` on the same
HEAD, so the second agent's branch switch silently strands the first agent's uncommitted
work, and commits land on whichever branch happens to be checked out at the time. The
symptom you notice first is unrelated files reverting under you. If you catch it, stop all
of them, discard the partial work, and re-dispatch in isolation — a few wasted minutes
beats untangling four interleaved histories. Verify the isolation on the first dispatch of
a batch rather than assuming it.

### The brief

An agent brief is a contract, and every one of these earns its place:

1. **The ticket ID and its acceptance criteria**, or a pointer to where they live.
2. **The architectural rules it must not violate**, named specifically. "Follow CLAUDE.md"
   is not a constraint an agent can check itself against; "all logic goes in the core, the
   view layer may not branch on business rules" is.
3. **The files it may touch.** Scope creep is the default failure mode.
4. **What "done" means for testing.** Which suite, and what a new test must cover.
5. **"If you find work outside this ticket, report it — do not do it."** This is what
   keeps the board honest and the diffs reviewable.
6. **"If the ticket is underspecified or wrong, say so in your report rather than
   silently redesigning it."**
7. **As the closing line: commit, push the branch, and open the PR.**

That last one is not a formality. Agents finish work, report success, and leave the
commits sitting in a local worktree with no PR — this is the single most common failure
mode of the whole loop, and it is silent. Putting it last in the brief is the cheapest
mitigation. When it happens anyway: go into the worktree, read the diff yourself, push it
and open the PR. Do not re-dispatch the ticket.

### While they run

Do the work only you can do: review PRs that have landed, update the board, resolve
questions, and prepare the next wave's shared pieces. Do not sit idle waiting, and do not
re-dispatch a ticket because an agent is slow.

---

## 5. Land

**Read the diff.** Every one. The agent's report is a claim, not evidence — and the two
diverge most often exactly where the ticket was hardest. Watch for:

- A calculation, a date computation, or a business rule that crept into the view layer.
- A test that asserts what the code does rather than what it should do.
- An interface that is right for this ticket and wrong for the two that depend on it.
- Doc comments describing an earlier draft of the implementation.

**Fix small things yourself.** A wrong argument order, an over-bound `let`, a stale
comment — editing it is one turn; a round trip is many. Re-dispatch only when the fix
requires re-deciding something.

**Green CI is the merge gate, and it means what it says.** A conflicted PR receives *zero*
check runs, not failing ones — an empty check list is not a pass. Confirm the checks ran.

**Merge on green, promptly.** Long-lived branches collide with each other. The board
moves when things merge, not when they are approved.

**Run the security review when the project's rules require it.** If the contract says
certain changes get one, that includes the ones that look obviously safe.

### Report honestly

This is the part of the loop with the most pressure to shade, so it gets an explicit rule.

*"It compiles and its unit tests pass"* and *"it works"* are different sentences. Say the
one that is true. When CI cannot prove something — a UI's appearance, a permission flow, a
real network call, on-device performance — say so plainly and list what a human should
check. A PR description that overstates what was verified is worse than no description,
because it stops the human from checking the thing that actually needed checking.

The same applies to your own errors. When a decomposition miss or a wrong call surfaces,
record it on the board as what it was. The board's value is that it can be trusted.

---

## Cycling

New work is discovered constantly: by agents reporting out-of-scope findings, by reviews,
by the user using the thing on a real device. All of it goes on the board with its source
noted, and the loop runs again.

Two habits keep the cycle from degrading:

- **File it, don't fix it.** Work discovered mid-ticket becomes a ticket. Fixing it in
  place produces a diff nobody can review and a board nobody believes.
- **Record why, not just what.** A board row saying "MAX-071 ✅" is bookkeeping. A row
  plus a paragraph on what was decided and what was rejected is what lets the next
  person — or the next context window — resume without re-deriving it.
