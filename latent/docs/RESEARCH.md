# Research — Chromagraph Camera (as received, 2026-11-02)

> **Provenance.** The research below was supplied by the owner on 2026-11-02 and is
> preserved here as received. The agent writing this file could **not** check it against
> the cited sources, because x.com and the news sites are outside this session's network
> allowlist. The one claim it did check independently is the launch-post timestamp, which
> it decoded from the X post ID (see *Annotations*). Treat everything else as secondary
> sourcing.

## The central caveat

Almost everything public about Chromagraph is a feature list. Its value is Steve
Yedlin's proprietary colour maths, which is not published. A PRD built from the feature
list describes a fairly ordinary RAW camera with a fixed look. Whether a peer app is any
good depends on image science we would have to build ourselves, not on the product spec.

## Origin and positioning (sourced)

- **Team:** Rian Johnson, with his longtime cinematographer Steve Yedlin, ASC, and
  programmer Eric Cameron. They brought the image processing from their films to iPhone
  stills. The App Store lists the developer as Chromatic Applications LLC.
- **Why it exists:** Johnson takes a lot of phone pictures and wanted it for himself.
  The team released it afterwards.
- **Pitch:** "It shoots RAW, bypasses the iPhone's look processing and instead uses the
  same image processing we use on our movies."
- **Philosophy:** Yedlin calls the look "opinionated". He told Wired it is not meant to
  replace Apple's Camera: "It's just this curated app that takes the pictures the way we
  like."
- **Timing:** Announced on X on Oct 28, 2026. It had been in the App Store since Oct 20,
  so it soft-launched first.

## Functional behaviour (sourced)

1. **Capture:** Reads sensor RAW and replaces Apple's processing with its own algorithm.
   It is not a filter on a finished photo.
2. **Delayed look:** You frame and shoot, then see the rendered result in the in-app
   gallery, like a film camera. **The viewfinder does not preview the final look.**
3. **Look components:** Tonality, chromaticity, grain, halation.
4. **Grading controls:** Colour, exposure, grain and halation. The adjustments are large
   but stay inside the core look. There are no presets and no LUT picker, deliberately.
5. **Non-destructive gallery:** The gallery keeps full-quality scene-linear originals,
   and the look and edits are applied non-destructively (Newsshooter).
6. **Export:** Smaller files to share or save to Photos. A Preferences option
   auto-exports every photo as a JPEG or HEIC with the look applied. **Gap:** the
   listing says nothing about exporting the RAW files.

## Non-functional and business details (sourced)

- $12.99 US / €14.99 in some EU countries. No subscription, no in-app purchases.
- The App Store privacy label says the app collects no data. It has no backend,
  accounts or analytics.
- Requires iOS 17+. The interface is English only.
- Version 1.1.3 reportedly added support for the "iPhone Duo". **Unverified, low
  confidence.** The agent writing this file does not know of a device by that name.
- iPad and Watch support has been claimed by one aggregator. Probably boilerplate.
- **No Android, deliberately.** Johnson: "there's no way with our small team we could
  dial it in for every device."
- Stills only for now. Video may come later, likely on newer iPhones only.
- Traction: No. 1 in Photo & Video (US). The X post shows about 12.5M views. That demand
  comes from Johnson's audience, not the feature set. **It is not a demand signal for a
  peer app.**

## Not public (owner's inference, moderate confidence)

- **Which RAW path:** Bayer RAW or Apple ProRAW. Not disclosed. This is the most
  important technical decision. See PRD decision **L-D1**.
- **Probable pipeline:** demosaic to scene-linear (e.g. `CIRAWFilter`), then a per-camera
  input transform, then tone and chroma rendering, then grain and halation on the GPU,
  then sRGB / Display P3 JPEG or HEIC.
- **Undocumented:** viewfinder controls, capture latency, storage management, edit
  storage format.

## Annotations by the planning agent

- **Launch timestamp, checked independently.** X post IDs are Snowflake IDs. Decoding
  `2115436064458621189` (`(id >> 22) + 1288834974657` ms since epoch) gives
  **2026-10-28 13:30:35 UTC**, which matches the claimed announcement date. Confidence:
  high.
- **The moat is probably narrower than "per-sensor calibration".** Apple's DNGs carry
  per-device `ColorMatrix` / `ForwardMatrix` tags, and `CIRAWFilter` uses them. So a
  colorimetrically reasonable scene-linear image is close to free on every supported
  iPhone. Per-device work refines this (chart-fit correction, noise profiling); it does
  not start from nothing. The part that cannot be bought is **taste**: the specific
  tone scale and chroma rendering Yedlin prefers. Confidence: moderate.
- **Yedlin's *philosophy* is public, even if his maths is not.** His essays and demos on
  yedlin.net (the "Display Prep Demo" and "On Color Science") argue that a film-like
  image comes from emulating film's image-forming behaviour in a controlled digital
  pipeline, not from a texture overlay. That supports the architecture in the PRD. It
  does not give us his look. Confidence that these pages exist: moderate-high. They were
  not fetched in this session.
- **Open prior art exists for the tone/chroma layer.** Examples are AgX (Blender's
  default view transform since 4.0), OpenDRT (Jed Smith), the ACES output transforms,
  and ACES 1.3's Reference Gamut Compression. Use them for study and benchmarking.
  **Check each licence before borrowing code or constants.** Kodak's published
  motion-picture film datasheets give characteristic curves and spectral sensitivities,
  which are useful targets for the tone scale.
