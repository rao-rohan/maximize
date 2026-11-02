# Latent — Build Plan

**Last updated:** 2026-11-02
**Spec:** [PRD.md](./PRD.md)
**Status:** Planning. Nothing is built yet.

Tiering follows Maximize's policy (see the root `PROJECT_TRACKER.md`). Sonnet does
standard feature work against a clear spec. Opus does anything numerically subtle or
expensive to get wrong. The Haiku tier stays empty, for the same reason: no ticket is
verified locally, because agent containers have no Swift toolchain. "Owner" marks work
that needs the physical phone, a colour chart, or taste.

Status key: ✅ merged · 🔲 ready · ⬜ blocked on dependencies

## Phase 0 — Foundation

| ID | Ticket | Tier | Status | Depends on |
|---|---|---|---|---|
| LAT-001 | Folder, README, conventions, research, PRD, build plan | — | ✅ (this change) | — |
| LAT-002 | **Repo home:** stays in `latent/`, and the owner extracts it later. Until then, Latent CI jobs must be path-filtered to `latent/**` | Owner | ✅ decided | — |
| LAT-003 | `LatentCore` package skeleton + path-filtered CI job (`latent/**`) + import guard (no AVFoundation/CoreImage/Metal/UIKit/SwiftUI/Photos) | Sonnet | 🔲 | LAT-002 |
| LAT-004 | App shell: XcodeGen spec, iOS 26, camera/Photos usage strings, simulator build in CI | Sonnet | ⬜ | LAT-003 |

## Phase 1 — Spikes that de-risk the PRD (device and owner)

Spikes answer questions. They do not produce shippable code. Each one ends in a short
written finding committed to `latent/docs/findings/`.

| ID | Question | Tier | Depends on |
|---|---|---|---|
| LAT-010 | On the owner's iPhone 16 Pro (main, ultra wide, 5× tele): which lenses offer Bayer RAW and ProRAW, at what resolutions? DNG sizes? Shutter-to-file latency? Noise at ISO 100/800/3200 for each path? (Decides L-D1 for real.) | Owner + Sonnet | LAT-004 |
| LAT-011 | Is `CIRAWFilter` with `boostAmount = 0` actually scene-linear? Shoot a grey step chart at bracketed exposures and check that a doubling of exposure gives a doubling of output, ±2%. **If this fails, L-D2 is re-opened.** | Opus | LAT-010 |
| LAT-012 | Can CI run Core Image Metal kernels? GitHub-hosted macOS runners have limited or no Metal (confidence: low). Test `CIContext` with `.useSoftwareRenderer`. The result decides whether LAT-032 runs in CI or is a device-only check. | Sonnet | LAT-003 |

## Phase 2 — Colour science core (`LatentCore`, CI-verified)

This is the critical path. Every ticket here is pure Swift with unit tests against known
values from published references (CIE, CAT16 test vectors, ACES RGC reference values).

| ID | Ticket | Tier | Depends on |
|---|---|---|---|
| LAT-020 | Colour types: linear RGB in a named space, XYZ, Lab, 3×3 matrices. Rec.2020 ↔ XYZ ↔ Display P3. CAT16 adaptation. Values typed per space, so a P3 value cannot be passed where a Rec.2020 one is expected | Opus | LAT-003 |
| LAT-021 | ΔE2000, tested against the Sharma et al. (2005) test data set | Opus | LAT-020 |
| LAT-022 | Tone scale: parametric log-space filmic curve (toe, mid-grey anchor, shoulder), monotonic by construction (property test), plus the per-channel ↔ norm blend | Opus | LAT-020 |
| LAT-023 | Chroma: hue-dependent saturation, gamut compression (RGC-style), display gamut mapping. Property: no output outside display gamut, and neutrals stay neutral | Opus | LAT-020 |
| LAT-024 | Halation model: threshold, multi-Gaussian kernel defined relative to the diagonal, tint, energy-conserving add-back | Opus | LAT-020 |
| LAT-025 | Grain model: seeded PRNG, correlated noise, luminance-dependent amplitude, size relative to the image. Test: the same seed gives identical output, and grain statistics are invariant across output sizes ±10% | Opus | LAT-020 |
| LAT-026 | `LookVersion` + `Edit` value types, clamping ranges, Codable round-trip, versioning rules (L2/L3) | Opus | — |
| LAT-027 | **CPU reference renderer:** Float buffer in, Float buffer out, composing 020–026. Slow and exact. It is the definition of correct (L5) | Opus | 021–026 |
| LAT-028 | Chart solver: fit a 3×3 input correction minimising mean ΔE2000 over 24 patches | Opus | LAT-021 |

## Phase 3 — Look development loop (the product's real work)

| ID | Ticket | Tier | Depends on |
|---|---|---|---|
| LAT-030 | `latent-render` macOS CLI: DNG folder + look JSON → rendered PNG/HEIC folder + contact sheet, using `CIRAWFilter` decode and the CPU reference renderer | Sonnet | LAT-027 |
| LAT-050 | Calibration session: shoot the chart under daylight and tungsten for each lens, run LAT-028, commit the matrices as data | Owner + Opus | LAT-028, LAT-030 |
| LAT-051 | **Look development:** shoot 50 fixed reference scenes (skin, sky, foliage, neon, backlight, low light, mixed light), then iterate the `LookVersion` in the CLI until renders hit [LOOK-BRIEF.md](./LOOK-BRIEF.md)'s targets (paper white about L\* 88.5 and cream; neutral true-black shadows; partial white-balance adaptation; cyan-leaning deep skies; yellow-leaning muted greens). Output: `LookVersion` 1 | Owner + Opus | LAT-030, LAT-050 |
| LAT-052 | Blind A/B harness: pairs Apple Camera HEIC with Latent's render of the same scene, randomised order, records preference. **Gate:** ≥ 70% preference, or the look goes back to LAT-051 | Sonnet + Owner | LAT-051 |

**Nothing in Phase 4 should be polished until LAT-052 passes.** A beautiful camera UI on
a look the owner does not prefer is wasted work. Phase 4 can be scaffolded in parallel.

## Phase 4 — GPU renderer and app

| ID | Ticket | Tier | Depends on |
|---|---|---|---|
| LAT-031 | Metal Core Image kernels for stages 3–8, wired into `CIRAWFilter.linearSpaceFilter` where the stage is linear | Opus | LAT-027 |
| LAT-032 | CPU/GPU parity suite on fixture DNGs (mean ΔE < 0.5, p99.9 < 2.0). Runs in CI or on device, depending on LAT-012 | Opus | LAT-031, LAT-012 |
| LAT-033 | Export adapter: HEIC/JPEG in Display P3, EXIF passthrough, location policy, DNG as Photos alternate resource (verify on device), add-only Photos access | Sonnet | LAT-031 |
| LAT-040 | Capture adapter (AVFoundation): Bayer/ProRAW selection, lens switching, focus/exposure, volume and Camera Control shutter. Writes the DNG plus a `Photo` record | Opus | LAT-004, LAT-010 |
| LAT-041 | Viewfinder UI: neutral preview, histogram, clip warning, post-capture proxy thumbnail with a latency signpost | Sonnet | LAT-040 |
| LAT-042 | Library: SwiftData models (CloudKit-safe, L-D6), render cache with eviction, grid, detail view, delete | Sonnet | LAT-026, LAT-031 |
| LAT-043 | Grade panel: the bounded sliders, proxy re-render, reset ticks, before/after under an empty edit, "update to current look" | Sonnet | LAT-042 |
| LAT-044 | Preferences: auto-export format, attach DNG, location policy, default RAW path | Sonnet | LAT-033 |
| LAT-045 | Storage screen: originals and cache sizes, clear cache | Sonnet | LAT-042 |

## Phase 5 — Later, deliberately

- An approximate live look preview (L-D3 v2), only with a measured error budget.
- HDR gain-map export.
- Manual ISO, shutter and focus (v1.1).
- Lock Screen capture extension.
- Multi-device calibration, if distribution is ever on the table (that re-opens PRD §5).

## What CI can and cannot prove

**Can:** the colour maths is correct against published references. The renderer is
deterministic. The tone curve is monotonic. Gamut mapping stays in gamut. Grain is
resolution-invariant. Look and edit records round-trip. GPU matches CPU, *if* LAT-012
finds Metal is usable on the runner.

**Cannot:** that the look is good (LAT-052 is a human judgement), real RAW capture
behaviour, shutter latency, thermal behaviour during burst use, Photos pairing of
DNG+HEIC, Camera Control and volume-button capture, or how a render looks on an actual
P3 OLED panel. Every Phase 4 PR carries a **Needs device verification** section.

## Critical path

LAT-002 → 003 → 020 → (021–026 in parallel) → 027 → 030 → 050 → 051 → **052 gate** →
031 → 032 → polish of Phase 4.

The longest and least predictable segment is **LAT-051**. It is taste-bound iteration
with no fixed endpoint. The honest schedule statement is that everything before it
takes weeks of agent time, and LAT-051 takes as long as it takes.
