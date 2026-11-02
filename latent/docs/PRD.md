# PRD — Latent: an opinionated RAW camera for iPhone

**Owner:** Rohan
**Status:** Draft v1 (for review)
**Last updated:** 2026-11-02
**Background:** [RESEARCH.md](./RESEARCH.md) · **Look targets:** [LOOK-BRIEF.md](./LOOK-BRIEF.md)
**Target device:** iPhone 16 Pro

---

## 1. Problem statement

The iPhone's default pipeline is Smart HDR, Deep Fusion, semantic segmentation, local
tone mapping and aggressive sharpening. It is optimised to make every region of every
frame legible. The result looks flat, over-lit and over-sharpened, and it looks the same
in every photo. Its "photographic styles" adjust that look; they do not leave it.

Existing RAW apps (Halide, ProCamera, Lightroom Mobile and others) give you the RAW
file and leave the rendering to you, through presets, LUTs and an editor. That means
every photo becomes an editing task. Chromagraph's insight is that most people do not
want *a* look editor. They want *one good look*, applied by default, with a few
controls that cannot break it.

**Latent is that product, with our own look.** It shoots RAW, skips Apple's look
processing, renders through a film-derived pipeline we design and control, and stays
non-destructive end to end.

## 2. The honest risk, stated first

The product is only as good as its look, and the look is image science we have to
build. Everything else in this document is routine iOS engineering. Two consequences:

1. **The look is the critical path, not the UI.** Phase 1 of the build plan is colour
   science and a desktop look-development loop, before the camera UI is polished.
2. **Success is a blind preference test, not a feature checklist.** If the owner does
   not prefer Latent's render over Apple Camera's in a blind A/B on a fixed scene set,
   the product has failed, however complete it is.

## 3. North star and success metrics

**North star:** The owner reaches for Latent instead of Apple Camera by default.

| Metric | Target | How it is measured |
|---|---|---|
| Blind preference vs Apple Camera (HEIC, default settings) | ≥ 70% of 50 fixed scenes | LAT-052 A/B harness. Same scene, both apps, randomised presentation |
| Chart accuracy, scene-linear stage (before the look) | mean ΔE2000 ≤ 2.0, max ≤ 5.0 on 24-patch chart, D65-ish light | LAT-050 calibration session |
| Shutter → review thumbnail visible, p50 | < 1.0 s | On-device signpost, LAT-041 |
| Shutter → full-resolution render cached, p50 | < 4 s | On-device signpost, LAT-031 |
| Render determinism (L4) | Same inputs → max ΔE2000 < 0.5 across runs and app versions with the same `LookVersion` | Fixture test |
| CPU reference vs GPU parity (L5) | mean ΔE2000 < 0.5, 99.9th percentile < 2.0 on fixtures | LAT-032 |

The latency targets are **estimates, not measurements** (confidence: low). LAT-010
measures the real capture and decode costs on the owner's device, and these numbers get
revised then.

## 4. Goals and non-goals

### Goals (v1)
1. **RAW capture that bypasses Apple's look processing.**
2. **One house look** made of four components: tone scale, chroma rendering, halation,
   grain.
3. **A handful of bounded grading controls:** exposure, white balance (temperature and
   tint), colour (saturation, and possibly one warmth/coolness axis), grain amount and
   size, halation amount. Every slider's range is clamped so it cannot leave the look.
4. **A non-destructive library.** Originals are immutable, edits are parameter records,
   and renders are a regenerable cache.
5. **Export:** a rendered HEIC/JPEG to Photos, manually or automatically, **plus
   optional original-DNG export**, which is the gap Chromagraph leaves open.
6. **Look versioning (L2).** Improving the look never silently changes old photos.

### Non-goals (v1)
- **Presets, LUT import, or multiple looks.** The restriction is the product.
- **A live final-look viewfinder.** See decision L-D3.
- Video. Possibly never. Apple Log + ProRes is a different product.
- iPad, Watch, Mac, Android.
- Any network feature: cloud sync, sharing, accounts, analytics.
- Local adjustments (masks, brushes, healing), cropping beyond aspect, perspective.
- Multi-frame computational tricks (HDR merges, night mode stacking).
- Supporting every iPhone. **v1 supports the owner's device only** (L-D5).

## 5. Users and distribution

Single user, owner-built, free provisioning, the same posture as Maximize. This matters
because it collapses three of Chromagraph's real costs: per-device calibration (one
device), localisation (English) and App Store review. **If this is ever distributed,
re-open:** name and trademark (README), device-coverage calibration, App Review
(camera and Photos usage strings), and pricing. Do not use the Chromagraph name, Yedlin's
name, or any claim of reproducing their look in anything public.

## 6. Locked decisions

### L-D1 — RAW path: Bayer RAW by default, ProRAW as an option
| | Bayer RAW | Apple ProRAW |
|---|---|---|
| What it is | Single-frame, mosaiced sensor data in a DNG | Linear, already-demosaiced DNG from Apple's **multi-frame fused** pipeline |
| Apple processing baked in | Essentially none | Multi-frame fusion and denoise. Local tone map is stored as metadata and can be disabled at decode |
| Low light | Noisy | Much cleaner |
| Resolution on 48 MP main sensors | 12 MP binned (moderate confidence) | 12 or 48 MP |
| Device support | Most modern iPhones, but lens availability varies | Pro models only (iPhone 12 Pro and later) |
| Size | ~15–25 MB at 12 MP (estimate) | ~25 MB at 12 MP, ~75 MB at 48 MP (Apple's published figures, moderate-high confidence) |

**On the target device, the iPhone 16 Pro**, the cameras are a 48 MP main (24 mm, f/1.78),
a 48 MP ultra wide (13 mm, f/2.2) and a 12 MP 5× telephoto (120 mm, f/2.8). Confidence:
high. ProRAW is available, at 48 MP on the main and ultra-wide (moderate-high confidence).
Which lenses expose Bayer RAW, and at what resolution, is **not known**, and LAT-010
answers it first. The expectation (moderate confidence) is 12 MP binned Bayer RAW on the
48 MP sensors.

**Decision: Bayer RAW is the default.** The product promise is "Apple's processing is
not in your picture", and only Bayer RAW keeps it fully. Our grain model gives us
cover: film-like grain tolerates and partly masks single-frame noise, which is a real
synergy and not an excuse. **ProRAW is a capture option** for low light and for 48 MP
when the device supports it. Both decode through the same pipeline. Each photo records
its source format so the renderer can adjust the noise-reduction and grain floor per
format. This is revisited after LAT-010 measures actual noise at ISO 800–3200 on the
owner's phone.

### L-D2 — Decode with `CIRAWFilter`; do not write a demosaicer
`CIRAWFilter` (iOS 15+) decodes both formats. It exposes `boostAmount` (set to 0 for a
scene-linear result), `localToneMapAmount` (0 to strip ProRAW's local tone map),
`baselineExposure`, `neutralTemperature`/`neutralTint`, the noise-reduction and
sharpness amounts, and a `linearSpaceFilter` hook that runs our kernels **in scene-linear
before** Apple's output stage. Output goes to a CIContext whose working colour space is
**extended linear Rec.2020**. LAT-011 verifies the linearity claim empirically on a grey
step chart, because the whole pipeline depends on it. A custom demosaicer (via LibRaw or
our own) is out of scope unless LAT-011 shows `CIRAWFilter` cannot give us a clean
linear signal.

### L-D3 — Viewfinder shows a neutral, honest preview, not the look
The live video feed is ISP-processed YUV, not RAW. Any "look" applied to it would be an
approximation that disagrees with the final render, and that mismatch would teach the
user to distrust the product. v1 shows a clean preview with exposure aids (histogram,
highlight clipping warning) and a **fast post-capture review**: a rendered proxy
thumbnail in under one second, in the corner, tappable. An "approximate look" preview
toggle is a v2 candidate, built only if the approximation's error is measured and small.

### L-D4 — Look versioning and edit model (implements L2/L3)
- `LookVersion { id, createdAt, toneScale, chroma, halation, grain, displayTransform }`
  is immutable and stored as data, the way Maximize's plans are versioned.
- `Photo { id, capturedAt, sourceFormat, dngPath, lookVersionID, edit, renderSeed }`
- `Edit { exposureEV, temperature, tint, saturation, grainAmount, grainSize,
  halationAmount }`. Each field is optional and clamped to the range its `LookVersion`
  declares.
- New captures use the current `LookVersion`. Old photos keep theirs until the user
  chooses to "update to current look". That is a visible per-photo action, and it is
  undoable because it only changes `lookVersionID`.

### L-D5 — One device, calibrated
v1 targets the owner's iPhone 16 Pro only, all lenses that support the chosen RAW path.
Device and lens are recorded per photo, so a future multi-device version can attach a
per-(device, lens) input correction without a migration.

### L-D6 — Storage follows the same CloudKit-compatible discipline as Maximize
SwiftData metadata uses no unique attributes, has defaults on every property, and has
optional relationships. Originals live as files in the app container with complete file
protection. A render cache sits in Caches and can be evicted. iCloud mirroring is
deferred, as it is in Maximize, for the same entitlement reason.

## 7. The rendering pipeline (our design)

Each stage is a pure function in `LatentCore` with a CPU reference implementation and a
Metal Core Image kernel (L5). The order matters and is justified per stage.

1. **Decode → scene-linear.** `CIRAWFilter` with boost 0, local tone map 0, minimal
   sharpening, and light chroma NR only. The working space is linear Rec.2020.
2. **Input correction (optional, per device and lens).** A 3×3 matrix fitted from chart
   captures by minimising ΔE2000 (LAT-050). The identity matrix is used until it is
   measured. It corrects any residual error in Apple's DNG calibration.
3. **Exposure and white balance.** Exposure is a scalar multiply in linear. White
   balance is a **chromatic adaptation transform (CAT16) in LMS**, not RGB channel gains,
   so neutrals adapt without skewing saturated colours. By default the adaptation is
   **partial**: the camera's auto-white-balance estimate is blended toward a fixed
   ~5500 K anchor by `adaptationStrength` (initially 0.5–0.6). That is how daylight film
   behaves, and it is why candlelight stays amber in the references (LOOK-BRIEF trait 8).
   The user's temperature and tint sliders act after this.
4. **Halation, in scene-linear, before tone.** Physically, halation is light passing
   through the emulsion, reflecting off the film base, and re-exposing mostly the red
   layer. So: isolate energy above a scene-linear threshold, blur it with a sum of
   Gaussians whose radius is a fraction of the image diagonal (resolution-independent),
   tint it toward red-orange, and add it back. Doing this before the tone scale is what
   makes highlights bloom naturally into the shoulder instead of looking pasted on.
5. **Tone scale.** A parametric filmic curve in log2 exposure space. It has a toe that
   reaches true black (no matte lift), a mid-grey anchor (to be tuned, placed low-key),
   and a long shoulder that approaches a **paper white below display white**: about
   L\* 88.5 (Y ≈ 0.73), tinted cream (b\* ≈ +12). The tint rises with luminance and is
   zero below mid-grey. These targets come from LOOK-BRIEF traits 1–4. **A key look decision is whether to apply it per channel or on
   a norm.** Per-channel tone mapping gives the classic film behaviour: highlights
   desaturate and some hues skew (oranges toward yellow, saturated blues toward cyan).
   Some of that is what makes film look like film, and some is ugly. Norm-based mapping
   preserves hue but looks "video". The plan is a hybrid: per-channel with a
   hue-preservation blend parameter, tuned in look development.
6. **Chroma rendering.** Hue-dependent saturation shaping (skin protected, foliage and
   sky shaped), then gamut compression in the style of ACES Reference Gamut Compression,
   so out-of-gamut scene colours roll off smoothly rather than clipping.
7. **Display transform.** Into Display P3 with the sRGB transfer function for SDR
   export. An HDR gain-map export (ISO 21496-1 / Apple adaptive HDR) is a v2 candidate.
8. **Grain, in display space, last.** Luminance-dependent amplitude (strongest in the
   midtones and weakest in deep shadow and clipped highlight, as on film), spatially
   correlated noise with a controllable grain size, and a seeded PRNG keyed to `Photo.id`
   (L4). **Grain size is defined relative to the image, not to pixels.** It is
   generated at output resolution, so a 2048 px export and a 12 MP export show the same
   grain character. If grain is generated at 12 MP and downsampled, it averages away.
   That is the most common way to get this wrong.

Sharpening: none, or a very light amount. Film is not crisp, and Apple's sharpening is
part of what we are leaving behind.

## 8. Capture UX

- **Shutter:** an on-screen button, the volume buttons (`AVCaptureEventInteraction`),
  and on iPhone 16+ the Camera Control (`AVCaptureControl` APIs, iOS 18+).
- **Controls, v1:** lens switch (only lenses that support the active RAW path), tap to
  focus and expose, EV compensation, AE/AF lock, and a RAW-path toggle (Bayer/ProRAW).
- **Controls, v1.1:** manual ISO and shutter speed, manual focus.
- **Aids:** a live luminance histogram and a highlight-clip warning computed from the
  preview stream. Grid optional.
- **Post-capture:** a rendered proxy thumbnail within 1 s (target) that opens the photo.
- **Lock Screen launch** (LockedCameraCapture, iOS 18+): v2.
- **Minimum OS: iOS 26**, matching Maximize. Chromagraph's iOS 17 floor exists for
  market reach, and that is not our constraint.

## 9. Library and editing UX

- A grid of rendered thumbnails (from the cache), newest first.
- The detail view shows the full render, an EXIF strip (lens, ISO, shutter, aperture,
  RAW path), and the look version, plus a "newer look available" affordance when
  applicable.
- **Grade panel:** the controls in §4 Goal 3. Each slider has a visible default tick, and
  double-tapping resets it. Every change re-renders a screen-sized proxy, targeting
  interactive frame rates. Full-resolution re-render happens on commit.
- A before/after hold shows the photo under the current `LookVersion` with an empty
  edit. **It never shows Apple's rendering**: we do not have it, and showing it would be
  a lie about what "before" means.
- Delete: removing a photo removes the DNG, the record and the cache. It asks for
  confirmation and cannot be undone.
- Storage screen: total originals size, cache size, and "clear cache".

## 10. Export

- **Manual export:** share sheet with HEIC or JPEG at full or long-edge-2048 size,
  rendered fresh (not from the cache) so grain is generated at output size (§7.8).
- **Auto-export (Preferences):** every capture is added to Photos as HEIC or JPEG once
  its full render finishes. Photos access is **add-only**.
- **Attach the original:** an option to add the DNG to the same Photos asset as its RAW
  alternate resource (`PHAssetCreationRequest` with `.photo` + `.alternatePhoto`),
  matching how Photos stores RAW+JPEG pairs. Confidence that this API pairing behaves as
  expected for third-party DNGs: moderate. LAT-033 verifies it on device.
- **Export DNG only:** through the share sheet / Files.
- **Metadata:** EXIF from the capture is preserved. Location is stripped by default on
  share-sheet export and kept on Photos export. That default is the user's choice in
  Preferences.

## 11. Architecture

```
latent/
  Package.swift                 LatentCore + latent-render CLI
  Sources/LatentCore/           colour maths, look/edit models, CPU reference renderer,
                                calibration solver, library state machine. Linux-testable.
  Sources/latent-render/        macOS CLI: render a folder of DNGs with a look JSON
  Tests/LatentCoreTests/
  App/                          SwiftUI shell + adapters (AVFoundation, CoreImage/Metal, Photos)
  project.yml                   XcodeGen
```

**Why the CLI matters.** Look development means rendering the same 50 DNGs hundreds of
times while tuning curves. Doing that through phone builds takes days per iteration. On
a Mac with the same core it takes seconds. This tool is part of the product, not
tooling overhead.

## 12. Privacy and security

There is no network code. The app requests camera access, and Photos access as add-only.
Location is captured only if the user grants it, and it goes only into EXIF. Originals
use `.complete` file protection. There is no secret to protect: this app has no API key,
unlike Maximize.

## 13. Resolved questions (2026-11-02)

1. **Target device:** iPhone 16 Pro (see L-D1, L-D5).
2. **Look references:** four images supplied, measured in [LOOK-BRIEF.md](./LOOK-BRIEF.md).
   Images are kept out of the repo, which is public.
3. **Repo home:** this stays in `latent/` for now. The owner will extract it. The
   planning agent could not create repositories in its session.

## 14. Open questions (owner)

1. **Full-resolution references.** Grain and halation cannot be measured from 652 px
   screenshots. Are there full-size originals?
2. **Coverage of the brief.** Three of the four references are warm or golden light.
   Are there references for overcast, night-urban and open-shade skin, or should
   LAT-051 extrapolate?
