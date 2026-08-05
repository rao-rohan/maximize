import SwiftUI
import MaximizeCore

/// A specimen sheet for every token in the design system.
///
/// This exists because nothing in this repo's verification story can look at a screen:
/// CI compiles the app but never runs or renders it. The gallery is the one place a
/// human can open an Xcode canvas and see the whole system at once — every color in
/// both appearances, the type scale at its real sizes, the surface treatments side by
/// side, and Liquid Glass floating over content the way FR-4.1 intends.
///
/// It is not wired into the app's navigation. It is a preview target and a review
/// artifact, and it doubles as compile-time proof that each token is usable from a
/// view (an unused token is an unproven one).
struct DesignSystemGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                surfacesSection
                typographySection
                scoreBandSection
                paletteSection
                spacingSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .screenMargins()
            .padding(.top, Spacing.roomy)
            .padding(.bottom, Spacing.hero * 2)
        }
        .contentSurface(.screen)
        .overlay(alignment: .bottom) { floatingChromeSpecimen }
    }

    // MARK: Surfaces

    private var surfacesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.regular) {
            heading("Content surfaces")

            // A stand-in for a chart container: card on the outside, inset plot area
            // inside. Both opaque. This is the shape every data view should take.
            VStack(alignment: .leading, spacing: Spacing.compact) {
                Text("Heart rate")
                    .font(.sectionHeading)
                    .foregroundStyle(Color.textPrimary)

                mockPlot
                    .contentSurface(.inset)

                Text("cap 150 bpm")
                    .font(.microLabel)
                    .foregroundStyle(Color.textTertiary)
            }
            .contentSurface(.card)

            HStack(spacing: Spacing.compact) {
                tile(value: "8.42", unit: "km")
                tile(value: "142", unit: "avg bpm")
                tile(value: "3.1", unit: "% drift")
            }

            // The specimen for MAX-085's one open question. The card above carries a
            // hairline `surfaceBorder`; the tiles beside it deliberately do not, on the
            // grounds that outlining a grid makes a wire mesh. That is arithmetic's
            // limit — whether the card reads as a card, and whether the tiles look
            // unfinished next to it, is a device judgement.
            Text("The card is edged; the tiles are not. Needs device verification.")
                .font(.microLabel)
                .foregroundStyle(Color.textTertiary)
        }
    }

    /// Not a real chart — a threshold line over a couple of gridlines, enough to judge
    /// whether `chartThreshold` and `chartGridline` separate from `surfaceInset`.
    private var mockPlot: some View {
        ZStack {
            VStack(spacing: Spacing.regular) {
                ForEach(0..<4, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.chartGridline)
                        .frame(height: LayoutMetrics.hairline)
                }
            }
            Rectangle()
                .fill(Color.chartThreshold)
                .frame(height: 1)
                .padding(.bottom, Spacing.section)
            Rectangle()
                .fill(Color.chartSeriesPrimary)
                .frame(height: 2)
                .padding(.top, Spacing.compact)
            Rectangle()
                .fill(Color.chartSeriesMuted)
                .frame(height: 2)
                .padding(.top, Spacing.section)
        }
        .frame(height: 96)
    }

    private func tile(value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Text(value)
                .font(.metricPrimary)
                .foregroundStyle(Color.textPrimary)
            Text(unit)
                .font(.metricLabel)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentSurface(.tile)
    }

    // MARK: Typography

    private var typographySection: some View {
        VStack(alignment: .leading, spacing: Spacing.regular) {
            heading("Type scale")

            VStack(alignment: .leading, spacing: Spacing.compact) {
                Text("87")
                    .font(.metricHero)
                    .foregroundStyle(Color.textPrimary)
                Text("metricHero — the effectiveness score, one per screen")
                    .font(.microLabel)
                    .foregroundStyle(Color.textTertiary)

                Divider().overlay(Color.separator)

                Text("Screen title").font(.screenTitle).foregroundStyle(Color.textPrimary)
                Text("Section heading").font(.sectionHeading).foregroundStyle(Color.textPrimary)
                Text("Held under the cap for the first 40 minutes, then drifted.")
                    .font(.bodyCopy)
                    .foregroundStyle(Color.textPrimary)
                Text("metricLabel — quiet by design")
                    .font(.metricLabel)
                    .foregroundStyle(Color.textSecondary)
                Text("microLabel — 12:04 · 165 spm")
                    .font(.microLabel)
                    .foregroundStyle(Color.textTertiary)
            }
            .contentSurface(.card)
        }
    }

    // MARK: Score bands

    private var scoreBandSection: some View {
        VStack(alignment: .leading, spacing: Spacing.regular) {
            heading("Score bands")

            // Driven off ScoreBand.allCases so this cannot silently fall out of sync
            // with the core, and so the band -> color path is the one being shown.
            HStack(spacing: Spacing.snug) {
                ForEach(ScoreBand.allCases, id: \.self) { band in
                    VStack(spacing: Spacing.tight) {
                        // The non-colour channel (MAX-084), shown here because a
                        // specimen sheet that only shows the fills shows the half of
                        // the band system that a colour-blind reader cannot use.
                        ScoreBandMarkView(
                            band: band,
                            diameter: LayoutMetrics.prominentScoreBandMarkSize
                        )
                        Text(band.rawValue)
                            .font(.microLabel)
                            .foregroundStyle(Color.textOnSaturatedFill)
                    }
                    .padding(.vertical, Spacing.snug)
                    .frame(maxWidth: .infinity)
                    .background(
                        Color.scoreBand(band),
                        in: RoundedRectangle(cornerRadius: CornerRadius.tile, style: .continuous)
                    )
                }
            }

            Text("Only the calendar and the verdict header may use these.")
                .font(.microLabel)
                .foregroundStyle(Color.textTertiary)

            Text(
                "effective and marginal are 1.02:1 against each other — "
                    + "the mark, not the fill, is what separates them."
            )
            .font(.microLabel)
            .foregroundStyle(Color.textTertiary)

            // The year heatmap (MAX-083) has no room for the mark above — a cell there
            // is ~6pt. MAX-087's channel for that density is shown at 4x scale here so
            // it can be inspected at all; whether it reads at the true size is a
            // question only a device can answer. See `ScoreBandHeatmapMarkView`.
            HStack(spacing: Spacing.snug) {
                ForEach(ScoreBand.allCases, id: \.self) { band in
                    VStack(spacing: Spacing.tight) {
                        ScoreBandHeatmapMarkView(
                            band: band,
                            cornerRadius: CornerRadius.heatmapMark
                        )
                        .frame(
                            width: LayoutMetrics.scoreBandMarkSize * 4,
                            height: LayoutMetrics.scoreBandMarkSize * 4
                        )
                        Text(band.rawValue)
                            .font(.microLabel)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Text("At year density (~6pt, magnified 4x here) — needs device verification.")
                .font(.microLabel)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: Palette

    private var paletteSection: some View {
        VStack(alignment: .leading, spacing: Spacing.regular) {
            heading("Palette")

            VStack(alignment: .leading, spacing: Spacing.snug) {
                swatch("accent", .accent)
                swatch("surface", .surface)
                swatch("surfaceElevated", .surfaceElevated)
                swatch("surfaceInset", .surfaceInset)
                swatch("surfaceBorder", .surfaceBorder)
                swatch("separator", .separator)
                swatch("textPrimary", .textPrimary)
                swatch("textSecondary", .textSecondary)
                swatch("textTertiary", .textTertiary)
                swatch("chartThreshold", .chartThreshold)
                swatch("chartSeriesPrimary", .chartSeriesPrimary)
                swatch("chartSeriesMuted", .chartSeriesMuted)
                swatch("chartExcursion", .chartExcursion)
                swatch("chartGridline", .chartGridline)
                swatch("chromeOpaque", .chromeOpaque)
            }
            .contentSurface(.card)
        }
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: CornerRadius.control, style: .continuous)
        return HStack(spacing: Spacing.compact) {
            shape
                .fill(color)
                .frame(width: 52, height: 30)
                .overlay { shape.strokeBorder(Color.separator, lineWidth: 1) }
            Text(name)
                .font(.metricLabel)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: Spacing

    private var spacingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.regular) {
            heading("Spacing ramp")

            VStack(alignment: .leading, spacing: Spacing.snug) {
                spacingBar("tight", Spacing.tight)
                spacingBar("snug", Spacing.snug)
                spacingBar("compact", Spacing.compact)
                spacingBar("regular", Spacing.regular)
                spacingBar("roomy", Spacing.roomy)
                spacingBar("section", Spacing.section)
                spacingBar("hero", Spacing.hero)
            }
            .contentSurface(.card)
        }
    }

    private func spacingBar(_ name: String, _ width: CGFloat) -> some View {
        HStack(spacing: Spacing.compact) {
            Rectangle()
                .fill(Color.accent)
                .frame(width: width, height: 10)
            Text(name)
                .font(.microLabel)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: Chrome

    /// The only Liquid Glass in the gallery, and it is floating over the screen rather
    /// than sitting inside a content surface — which is the entire distinction FR-4.1
    /// and FR-4.2 draw between the two layers.
    private var floatingChromeSpecimen: some View {
        HStack(spacing: Spacing.snug) {
            Image(systemName: "chart.xyaxis.line")
            Text("Floating control")
                .font(.metricLabel)
        }
        .foregroundStyle(Color.textPrimary)
        .padding(.horizontal, Spacing.roomy)
        .padding(.vertical, Spacing.compact)
        .glassChrome(.floatingControl)
        .padding(.bottom, Spacing.section)
    }

    // MARK: Shared

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.sectionHeading)
            .foregroundStyle(Color.textSecondary)
    }
}

#Preview("Dark — the designed appearance") {
    DesignSystemGallery()
        .preferredColorScheme(.dark)
}

// Light values exist so the app is not unreadable if someone runs it in light mode.
// They are a fallback, not a designed appearance — see ColorTokens.swift.
#Preview("Light — fallback only") {
    DesignSystemGallery()
        .preferredColorScheme(.light)
}
