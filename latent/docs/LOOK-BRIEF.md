# Look brief — LookVersion 1 targets

**Last updated:** 2026-11-02
**Input:** four reference images from the owner (2026-11-02)
**Feeds:** LAT-051 (look development) and LAT-052 (blind A/B gate)

> **The images are not in this repo, on purpose.** The repo is public, and the
> references may be third-party photographs. Keep them in `latent/look-reference/`,
> which is gitignored. Only measurements and descriptions are committed here.

## The references

| # | Scene | Light |
|---|---|---|
| R1 | Long outdoor dinner table, palms, adobe wall, green glassware | Low golden-hour sun, hard raking light |
| R2 | Beach club: striped umbrellas, people standing, yacht, deep blue sky | Clear midday sun |
| R3 | Interior living room, large window onto hillside town and sea | Daylight from the window, interior in partial shade |
| R4 | Dark dining room, candles on table, pendant lamp, doorway onto a garden | Mixed: tungsten and candle inside, daylight outside |

## How they were measured

The four files are 652 × 869 sRGB PNGs (the ICC profiles were checked and all say
sRGB), so they are screenshots or downsamples. They were converted to CIELAB (D65), and
per-image and per-region statistics were computed. The script lives in the session
scratchpad; LAT-051 should re-run it on full-resolution sources if they exist.

**What these files can tell us:** tone distribution, white and black points, the
colour of neutrals, and hue and chroma of named regions.
**What they cannot tell us:** grain and halation (downsampling destroys both) and the
original scene values. We see the output of an unknown pipeline, not its input. So
these are **target outputs**, not curve parameters.

## Measurements

### Global tone (L\*, 0–100)

| | p1 | p5 | p50 | p95 | p99 | % clipped (any channel ≥ 250) | % near-black (max channel ≤ 8) |
|---|---|---|---|---|---|---|---|
| R1 table | 1.2 | 2.4 | 25.1 | 71.9 | 80.3 | 0.01 | 2.8 |
| R2 beach | 2.4 | 5.2 | 51.1 | 87.8 | 88.5 | 0.00 | 0.05 |
| R3 window | 2.7 | 5.6 | 22.7 | 84.8 | 88.8 | 0.00 | 0.8 |
| R4 candles | 0.1 | 0.3 | 0.6 | 72.4 | 84.1 | 0.02 | 68.7 |

### Neutrals and named regions (CIELAB)

| Region | L\* | C\* | hue° | a\* | b\* |
|---|---|---|---|---|---|
| R2 clouds / whites | 83.6 | 13.3 | 91 | −0.4 | +13.2 |
| R3 clouds | 84.3 | 12.8 | 96 | −1.7 | +12.5 |
| Shadows, bottom 10%, all four images | — | 0.4–4.6 | — | ≈ 0 to +2 | ≈ −1 to +4 |
| R2 clear sky | 46.5 | 25.4 | 241 | −12.8 | −21.7 |
| R2 sea | 38.7 | 22.5 | 228 | −14.8 | −15.4 |
| R2 skin (sunlit; small sample) | 47.0 | 43.1 | 69 | +16.2 | +39.7 |
| R2 yellow shirt | 67.4 | 50.7 | 80 | +8.4 | +49.9 |
| R1 green glassware | 24.6 | 34.0 | 131 | −21.9 | +25.8 |
| R4 garden through doorway | 64.0 | 14.9 | 156 | −9.2 | +3.2 |
| R3 hillside view through window | 56.6 | 10.1 | 100 | −2.3 | +8.1 |
| R4 candle-lit tablecloth | 65.0 | 38.4 | 83 | +5.2 | +34.3 |

## What the numbers say (these become LookVersion 1's targets)

Each trait has a confidence level. "High" means all four images agree and the
measurement is unambiguous.

1. **Peak white sits at L\* ≈ 88–89, and nothing clips.** In both daylight scenes with
   clouds and sky (R2, R3), the 99th percentile stops at 88.5–88.8 and clipping is
   0.00%. That is a deliberate *paper white* below display white, like a print, plus a
   shoulder that approaches it asymptotically. Apple's pipeline puts clouds at or near
   L\* 100. **This is probably the single biggest visual difference from an iPhone
   photo.** Target: display peak Y ≈ 0.73 (L\* ≈ 88.5). Confidence: high.
2. **Whites are cream, not neutral: b\* ≈ +12 to +13, a\* ≈ 0.** This holds in both
   R2 (midday) and R3 (daylight interior). Midday clouds should be close to neutral, so
   this is the look, not the light. Target: the highlight tint rises with luminance to
   about b\* +12 at paper white. Confidence: moderate-high (two scenes).
3. **Shadows are neutral, and blacks are true black.** The bottom decile has C\* < 5 in
   every image, with no teal or orange split-toning. Blacks reach L\* ≈ 0–3 with no
   matte lift, and R4 lets 69% of the frame go to near-black. Target: the toe reaches
   true black, and the warm tint fades to 0 below mid-grey. **This rules out the
   "faded film" filter look.** Confidence: high.
4. **Low-key placement, with no shadow recovery.** The median L\* is 23–25 in the three
   scenes with significant shade. R3 keeps the interior at L\* ≈ 33 while the window
   view sits at 57, and Apple's local tone mapping would pull those much closer
   together. Target: global tone scale only (no local tone mapping, consistent with
   L-D2), and default auto-exposure biased about −0.3 to −0.7 EV against Apple's metering
   so highlights are protected. The EV figure is a guess, low confidence; LAT-051 tunes
   it. The trait itself: high confidence.
5. **Skies are deep and lean cyan.** The R2 clear sky is L\* 46.5, C\* 25, hue 241°,
   which is darker than typical iPhone skies and rotated away from pure blue (≈ 270–290°)
   toward cyan. The sea sits at 228°. Target: saturated blues come out darker and rotate
   about 15–30° toward cyan in the chroma stage. Confidence: moderate. There is one
   scene, and we do not know the true sky colour.
6. **Greens are pulled toward yellow and muted when natural.** The emerald glassware
   lands at 131° (yellow side of green). Foliage and landscape sit at C\* 10–15. Target:
   hue-dependent desaturation of mid-chroma greens, with a small rotation toward yellow.
   Confidence: moderate.
7. **Skin and warm hues are rich and golden.** Sunlit skin is at hue 69° with C\* 43,
   and warm hues carry most of the chroma in R1, R3 and R4. Target: protect the skin hue
   band (55–75°) from the green and blue manipulations, and let warm hues stay dense.
   Confidence: low to moderate. The skin sample is small and sunlit.
8. **Mixed lighting is preserved, not neutralised.** In R4 the candle-lit cloth is
   b\* +34 while the daylight garden is near-neutral. R1's golden hour stays golden. That
   is what film balanced for daylight does. Target: white balance adapts only
   **partially** from the camera's auto white balance toward a fixed ~5500 K anchor. That
   is a new look parameter, `adaptationStrength` (start at 0.5–0.6), applied through
   CAT16. Confidence: moderate.
9. **Grain and halation: unknown.** At 652 px the midtone high-pass residual is about
   1.2–1.4 L\*, but downsampling and compression make this meaningless as a grain
   measurement. **To set the grain and halation targets, get full-resolution
   references.** Until then, keep both subtle, because these images do not read as
   visibly grainy even at this size.

## Caveats

- **Four images, and three of four are warm or golden light.** The brief says nothing
  about overcast skies, fluorescent offices, night streets, snow, or skin in open shade.
  LAT-051's 50-scene set must cover those, and the A/B gate is what judges them.
- **We measured someone else's output.** If these are another app's renders, matching
  their numbers aims at that look by eye. That is how look development normally works,
  and it is fine for a personal app. It is also why PRD §5 forbids claiming to reproduce
  anyone's look in public.
- The R4 doorway is a mix of foliage and sunlit wall, so its hue (156°) is an average,
  not a clean green.
