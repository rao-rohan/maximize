import SwiftUI
import MaximizeCore

/// The app's top-level structure: three tabs, three modes.
///
/// **What is a tab, and what is not, is decided in `MaximizeCore.RootTab`** — the order,
/// the labels, and the symbols, with the argument for each written there and pinned by
/// `RootTabTests`. This file only mounts them. That split is not ceremony: a tab bar is
/// the app's claim about what its parallel modes are, and a `Tab` is two lines to add,
/// so the claim needs to live somewhere a reviewer reads it and CI checks it rather than
/// somewhere it can accrete.
///
/// Two decisions worth restating here, because this is the file where they get undone:
///
/// - **Plan is a tab (MAX-085, mounting MAX-102).** It is the reference every score on
///   the other two tabs is measured against (D1), and before MAX-102 it was legible only
///   while being edited.
/// - **Settings is still not one (MAX-081).** It reaches all three tabs as a toolbar
///   button via `settingsToolbarItem()`; it now has one more tab to reach and the same
///   reason not to occupy one.
///
/// ## Chrome
///
/// The tab bar draws its own Liquid Glass on iOS 26 (FR-4.1), so there is deliberately
/// no `glassChrome(.tabBar)` here — that case exists for a *custom* bar standing in for
/// the system one, and re-applying the platform's material to the platform's own control
/// is how an app stops looking like the platform. `SettingsToolbar.swift` makes the same
/// argument for the navigation bar and the sheet. Reduce Transparency is therefore the
/// system's business here too, and it handles it.
///
/// MAX-098's persistent chat accessory attaches to this `TabView` next, as a
/// `tabViewBottomAccessory`; nothing here is in its way.
struct RootTabView: View {
    var body: some View {
        // The iOS 26 `Tab` builder, not `tabItem` (design review T2 / FR-4.1). The old
        // shape still compiles, and that is the problem with it: it renders a bar that
        // predates the current one, and none of the behaviour below is reachable from it.
        //
        // Written out rather than looped over `RootTab.allCases` because each tab's root
        // is a different type; the order here is `allCases`' order, which is the part a
        // test can hold.
        TabView {
            Tab(RootTab.workouts.title, systemImage: RootTab.workouts.symbolName) {
                WorkoutsView()
            }

            Tab(RootTab.dashboard.title, systemImage: RootTab.dashboard.symbolName) {
                DashboardView()
            }

            Tab(RootTab.plan.title, systemImage: RootTab.plan.symbolName) {
                PlanView()
            }
        }
        // FR-4.1 names scroll-collapsing tab bar behaviour, and this app earns it: all
        // three tabs are long scrolling columns of dense numbers, so scrolling *down*
        // means "I am reading, give me the height back" and the bar minimising to a pill
        // is exactly that. `.onScrollDown` rather than `.automatic` because the automatic
        // behaviour is the platform's judgement about a generic app, and this one is
        // three scroll views.
        .tabBarMinimizeBehavior(.onScrollDown)
        // The single line that makes the accent visible (design review §3.1). MAX-084
        // settled a violet, measured it, wrote it into amendment A7 — and it reached two
        // call sites, both at the bottom of one screen's scroll, because `.tint()` was
        // called nowhere in `App/`. Everything the *system* draws — the selected tab, the
        // segmented interval picker, the date pickers, every `Form` control on the
        // Settings sheet, every `ProgressView`, the navigation back chevron — was
        // untinted iOS blue, which is precisely what `Color.accent`'s own documentation
        // says the accent must not be mistaken for.
        //
        // Placed on the `TabView` rather than in `MaximizeApp` because tint is an
        // environment value: this is the root of the app's view hierarchy, and sheets
        // presented from inside it inherit it, so the Settings sheet is tinted too.
        // Destructive buttons keep `role: .destructive` and stay red.
        .tint(.accent)
    }
}
