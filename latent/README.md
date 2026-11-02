# Latent

**Codename.** An iPhone RAW camera with one opinionated, film-derived look, applied
after capture and kept non-destructive. It is a genre peer of Chromagraph Camera (Rian
Johnson / Steve Yedlin / Eric Cameron, Oct 2026), **not a clone of it**. We cannot clone
it anyway: its value is Yedlin's colour science, which is not published. Ours is our own.

The name comes from the *latent image*: the exposed but undeveloped picture on film.
It suits the product's core interaction, where you shoot now and see the rendered image
afterwards. Before anything is distributed, check the name for trademarks and existing
App Store collisions. That check has not been done.

## Status

**Planning only.** There is no code here yet. Read these in order:

| Doc | What it is |
|---|---|
| [docs/RESEARCH.md](./docs/RESEARCH.md) | Public facts about Chromagraph, preserved as received, with sourced claims kept apart from inference |
| [docs/PRD.md](./docs/PRD.md) | What we are building, the decisions it locks, and what it explicitly does not do |
| [docs/BUILD-PLAN.md](./docs/BUILD-PLAN.md) | Phased tickets (LAT-xxx), agent tiers, what CI can and cannot prove |
| [CLAUDE.md](./CLAUDE.md) | Conventions for work in this folder, and where they differ from Maximize's |

## Why it lives inside the Maximize repo, and why that is temporary

Maximize and Latent share an owner, a toolchain (XcodeGen, iOS 26 SDK, free
provisioning) and an architecture rule: thin shell, fat core. Starting here makes it
cheap to reuse the CI patterns and the conventions.

The argument against this is strong and is recorded here deliberately. **These are two
unrelated products.** Maximize's CI, tracker, PRD amendments and design rules all
assume one app. A second `Package.swift` and a second app target in the same repo will
eventually confuse path-scoped CI, agents reading the root `CLAUDE.md`, and anyone
doing `git log`. LAT-002 decides whether to extract this folder into its own repo
before any code lands. The recommendation is to extract it.
