/// The app's top-level modes — what the tab bar claims this app *is*.
///
/// ## Why this is data in the core rather than three literals in a view
///
/// A tab bar's order and labels are decisions, not styling. They are also the kind of
/// decision that gets edited casually — a `Tab` is two lines to add, which is exactly
/// why MAX-081 had to argue Settings back *out* of one. Holding them here means the
/// claim is written down once, reviewed as a claim, and pinned by a test that runs on
/// every commit (`RootTabTests`); `RootTabView` is left with nothing to decide, which
/// is what a thin shell means (CLAUDE.md).
///
/// Symbol names are plain strings — no SF Symbols import, no UIKit. The core says
/// *which* symbol; the app layer is what draws it.
///
/// ## Who gets a tab
///
/// A tab is a **mode**: a place you inhabit, that stays where you left it, that you
/// switch to rather than navigate to. Three surfaces qualify, and the test is the same
/// one MAX-081 applied to Settings and it failed:
///
/// - **Workouts** — what happened, run by run. FR-1.
/// - **Dashboard** — how the block is going, in aggregate. FR-3.
/// - **Plan** — what was prescribed, and by which version. The reference every score on
///   the other two tabs is measured against (D1), and until MAX-102 it was legible only
///   while being *edited*, which is the one moment you are least able to consult it.
///
/// Settings is not here and does not come back: it is somewhere you go to change a
/// preference and immediately leave, which is a destination, not a mode. It reaches all
/// three tabs as a toolbar button — see `SettingsToolbar.swift`.
///
/// ## Why Plan is last
///
/// `allCases` is the tab order, left to right, and the leading tab is what the app
/// opens to. Workouts stays first because "how did today go" is why the app gets opened;
/// Plan is the thing you consult when a number surprises you, which is often but not
/// first. Putting the reference in the leading slot would also mean a fresh install
/// opens onto an empty state ("no plan authored yet") — a reasonable argument for a
/// different app, and one this ticket declined to make on the owner's behalf.
public enum RootTab: String, CaseIterable, Identifiable, Sendable {
    case workouts
    case dashboard
    case plan

    public var id: String { rawValue }

    /// The tab bar's label. Single words on purpose: a tab item truncates before it
    /// wraps, and it has to survive the largest Dynamic Type size in three columns.
    public var title: String {
        switch self {
        case .workouts: return "Workouts"
        case .dashboard: return "Dashboard"
        case .plan: return "Plan"
        }
    }

    /// The SF Symbol drawn above the label.
    ///
    /// The three have to be told apart as *silhouettes* at ~25pt, monochrome, with one
    /// of them tinted — so they are chosen to differ in shape, not only in subject:
    /// a figure, a line graph, and a rectangle of ruled text.
    ///
    /// `list.bullet.clipboard` is MAX-102's suggestion and it survives that test: it is
    /// the only one of the three with a hard rectangular outline, it does not collide
    /// with `chart.xyaxis.line`'s thin diagonal linework, and a clipboard reads as the
    /// sheet you consult rather than a thing you edit — which is precisely what the
    /// plan screen is (read-only, with a hand-off to authoring). The alternatives were
    /// `calendar` (already the dashboard's own content — the score calendar is on the
    /// Dashboard tab, so it would point at the wrong screen) and `target` (reads as a
    /// goal or a race, and the plan is a prescription, not a target).
    public var symbolName: String {
        switch self {
        case .workouts: return "figure.run"
        case .dashboard: return "chart.xyaxis.line"
        case .plan: return "list.bullet.clipboard"
        }
    }
}
