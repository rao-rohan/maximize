# Latent — conventions for this folder

The root [`CLAUDE.md`](../CLAUDE.md) applies here **except where this file says
otherwise**. The root file describes Maximize. Its HealthKit, Claude-prompt, D1/D2/D3/D8
and score-band rules are about that app and do not apply to Latent. The rules carried
over are the ones about *how* we build: thin shell and fat core, definition of done,
honest reporting of what CI can and cannot prove, colour from tokens, accessibility as
part of the ticket, and no secrets in the repo.

## Latent's own invariants

These are load-bearing, in the same way Maximize's D1/D8 are. Do not trade them away
for convenience.

- **L1: Originals are immutable.** The captured DNG is never rewritten, re-encoded, or
  "optimised". Everything else is derived from it and can be regenerated.
- **L2: The look is versioned data, not code.** Tone scale, chroma rendering, halation
  and grain parameters live in a versioned `LookVersion` record. Each photo records the
  look version it was graded under, so changing the look never silently changes an old
  photo. Re-rendering an old photo under a new look is an explicit, per-photo action.
- **L3: Edits are parameter deltas, not pixels.** A user's grade is a small value record
  layered on a `LookVersion`. Undo, reset and history are operations on that record.
- **L4: Rendering is deterministic.** The same DNG, `LookVersion`, edit and output size
  produce the same pixels to within a stated tolerance. Grain uses a seeded PRNG keyed
  to the photo's identity. Anything random that is not seeded is a bug.
- **L5: One renderer contract, two implementations.** A pure-Swift CPU reference
  renderer in `LatentCore` defines the maths. The GPU path (Core Image / Metal kernels)
  is an optimisation that must match the reference within a ΔE2000 budget on fixtures.
  If the two disagree, the reference is right by definition.

## Architecture specifics

- `LatentCore` must not import `SwiftUI`, `UIKit`, `AVFoundation`, `CoreImage`,
  `Metal`, or `Photos`. It holds the colour maths, look and edit models, the CPU
  reference renderer, calibration solvers, and library state machines. It must build
  and test on Linux.
- Decoding RAW, capture, GPU rendering and Photos export are adapters behind protocols
  defined in the core.
- A macOS command-line look-development tool (`latent-render`) uses the same core and
  renderer. Iterating on the look by sideloading a phone build is too slow to be a
  workflow.

## Privacy

Photos are personal data. They include location EXIF and faces. There is no network
code in this app: no analytics, no crash reporting that ships pixels or metadata, and no
cloud processing. Photos library access is **add-only** unless a ticket justifies more.

**This repository is public.** Never commit reference images, personal captures or DNGs
(`latent/.gitignore` enforces the common paths). A test fixture DNG is a deliberate
exception under `Tests/**/Fixtures/`. It must show no people, its location EXIF must be
stripped, and it must have been shot for the purpose.
