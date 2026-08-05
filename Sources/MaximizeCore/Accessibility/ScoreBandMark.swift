/// The band channel that is not colour (MAX-084).
///
/// ## The defect this exists to close
///
/// `ScoreCalendarView` and `ScoreCalendarFormatting` both used to claim that colour is
/// never the only channel carrying a calendar cell's meaning, and both were wrong about
/// the pair that matters most. Two independent reasons, measured in
/// `WCAGContrastTests`:
///
/// - **Luminance.** `scoreEffective` and `scoreMarginal` contrast with *each other* at
///   **1.02:1** in dark and **1.04:1** in light. In greyscale they are the same square.
///   (Light is worse still: all three bands land within 1.04:1 of one another, so a
///   light-appearance calendar is one flat grey in greyscale.)
/// - **Glyph.** `ScoreCalendarFormatting.systemImageName(for:)` returns the *activity*
///   glyph for a scored day. It encodes what the athlete did, not how it went, so a
///   green run day and an amber run day carry the identical mark.
///
/// Green-versus-orange is precisely the axis protanopia and deuteranopia collapse, and
/// identical luminance removes the one channel that would otherwise rescue it. So
/// "effective" and "marginal" — the calendar's primary output — were distinguishable by
/// hue alone.
///
/// ## Why a shape rather than retuned colours
///
/// Pulling the fills apart on the luminance axis was the other candidate (design review
/// §8.1, option 2) and it is not sufficient on its own: it helps greyscale and it helps
/// nobody who sees hue but sees it differently. It is also boxed in. In light
/// appearance every band fill carries white ink, which caps its relative luminance at
/// 0.183 for WCAG AA; fitting three bands into that window with real separation means
/// re-picking all three light values, and nothing in this project can look at the
/// result. A shape works in every appearance, under every kind of colour vision, and at
/// 1.02:1 or 21:1 alike.
///
/// ## Why this lives in the core
///
/// Same reason `ScoreBand` does: it is a decision, and decisions belong where CI can
/// see them. The app layer draws the pip (`ScoreBandMarkView`); which pip a band gets
/// is settled here, once, for the calendar and the verdict header both — the two
/// surfaces FR-4.3 lets the band colours appear on.
public enum ScoreBandMark: String, Hashable, Sendable, CaseIterable {
    /// A small solid dot.
    case filledPip

    /// A ring of the same outside diameter — the same footprint, a different figure.
    case hollowPip

    /// No mark. Reserved for the band that needs the shape channel least: in the
    /// designed appearance `scoreIneffective` sits 1.68:1 from `scoreEffective` and
    /// 1.66:1 from `scoreMarginal` — the two widest gaps in dark, against 1.02:1 for
    /// the pair this exists to separate — and a bad day is the one that least wants
    /// extra ornament on it. It is still covered: absence of a mark is as readable a
    /// difference from a dot or a ring as those two are from each other, and the
    /// contrast suite treats it as a distinct value rather than as an opt-out.
    case unmarked
}

extension ScoreBand {

    /// The non-colour mark that stands in for this band's hue.
    ///
    /// Read at every site that draws a band fill. The mapping is deliberately total and
    /// deliberately distinct: `WCAGContrastTests` asserts that no two bands are left
    /// relying on hue alone, so collapsing two bands onto one mark fails CI unless
    /// their fills are separated by 3:1 — which today they are not, in any appearance.
    public var mark: ScoreBandMark {
        switch self {
        case .effective:
            return .filledPip
        case .marginal:
            return .hollowPip
        case .ineffective:
            return .unmarked
        }
    }
}

extension ScoreCalendarDayState {

    /// The band this day carries a verdict for, or nil if it carries none.
    ///
    /// `.missed` returns nil even though it draws in `scoreIneffective`: D9 says a
    /// missed session shows red, but no band was ever decided for it (no workout, no
    /// score), and inventing one here would be the same mistake `Color.scoreBand(_:)`
    /// refuses at its call site. It has its own glyph — a dedicated "×" rather than an
    /// activity mark — which is the channel that already tells it apart from a scored
    /// red day.
    ///
    /// Here rather than pattern-matched in the view so the rendering ticket in flight
    /// against the calendar picks up one accessor instead of re-deriving it.
    public var scoredBand: ScoreBand? {
        if case .scored(let band, _) = self {
            return band
        }
        return nil
    }
}
