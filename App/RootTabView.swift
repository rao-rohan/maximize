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
/// ## The persistent Ask control (MAX-098, §2.1 / §7)
///
/// Chat's one door is mounted here, on the `TabView` itself, so every tab gets it and
/// pushing a workout detail does not stack a second one. Three things about it are
/// decided in this file and nowhere else:
///
/// - **It is the `TabView`'s bottom accessory, not an overlay.** Spec §7.2 named the
///   accessory as preferred and could not verify it existed; it does, and it is the
///   better of the two for a reason beyond idiom — the system insets the tab content's
///   safe area around it and moves it with the tab bar as that bar minimises. An
///   overlay does neither: it would sit permanently on top of the bottom-trailing
///   corner of three dense scrolling screens, and §7.3's "it never disappears, it may
///   move" would have to be hand-written against `.tabBarMinimizeBehavior(.onScrollDown)`.
///   The cost of the choice is stated plainly: the accessory is a full-width bar, so
///   this is *not* §2.1's bottom-trailing capsule. See the PR.
/// - **What it says is not decided here.** `ChatEntryPoint.resolve(focus:currentInterval:)`
///   (`MaximizeCore`) turns "a run is on screen, or none is" into the subject, the
///   label, and what VoiceOver reads. This file supplies the two facts and draws the
///   result.
/// - **A14 — no unattended chat call.** The button presents a sheet and nothing else.
///   `ChatSheet` is constructed only when presented, and `ChatModel.load()` reads stored
///   records; the model is called when the athlete sends a message.
///
/// ## Why the dashboard's interval model is owned up here
///
/// §3.4 makes the interval selector the app's single notion of "what period are we
/// talking about", and a training thread freezes that window at creation. The Ask
/// button needs it on every tab, so the model that holds it lives at the root and
/// `DashboardView` is handed the same instance it used to own. One control, one window
/// — a second notion of scope is precisely the class of mistake D2 and D3 exist to
/// prevent.
struct RootTabView: View {

    /// The app's one interval selection (§3.4). `DashboardView` renders and mutates it;
    /// the Ask button reads it to know which window a training thread would be about.
    @State private var intervalModel = TrendIntervalSelectionModel()

    /// What screen the Ask button is sitting on top of (§7.5). Put in the environment
    /// so `WorkoutDetailView` — the one screen with something to report — can say so.
    @State private var chatEntryPoint = ChatEntryPointModel()

    /// Non-nil exactly while the chat sheet is up. Carries the subject captured **at the
    /// moment of the tap** rather than re-reading it while the sheet is open, so what
    /// opens is what the button said it would open.
    @State private var chatOpening: ChatOpening?

    /// MAX-163's device-lifetime record of whether the Health sheet has been presented.
    /// One instance for the view's lifetime — cheap to construct, and stable identity is
    /// what lets `FirstRunCoverView` hand it straight to `recordHealthRequestPresented()`
    /// without re-reading `UserDefaults` at every call.
    @State private var firstRunRecording = UserDefaultsFirstRunPresentationStore()

    /// Whether the first-launch cover is up. Resolved once, from `FirstRunCoverGate`, when
    /// this view first appears — **not** recomputed on every re-render, which is what
    /// keeps a later launch from re-opening it: `FirstRunCoverGate.shouldPresent(_:)`
    /// reads a device-lifetime fact, but a `Bool` still has to hold that answer for
    /// SwiftUI's presentation binding to drive off, and `.onAppear` is where it is asked.
    @State private var isPresentingFirstRunCover = false

    /// `ChatSubject` is `Hashable`, which is all `sheet(item:)` needs of an identifier,
    /// and it is the right one: two taps on the same subject are the same presentation.
    private struct ChatOpening: Identifiable {
        let subject: ChatSubject
        var id: ChatSubject { subject }
    }

    private var entryPoint: ChatEntryPoint? {
        ChatEntryPoint.resolve(
            focus: chatEntryPoint.focus,
            currentInterval: intervalModel.state.interval
        )
    }

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
                DashboardView(intervalModel: intervalModel)
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
        // §7.2 / §7.3. The accessory is the slot above the tab bar that travels with it
        // as it minimises, which is the whole reason it beats an overlay here: the
        // control never disappears, it moves, and it does so because the platform moves
        // it rather than because this file tried to.
        //
        // Nothing glasses this. The system draws the accessory's own container in
        // Liquid Glass, exactly as it draws the tab bar's — see `ChatEntryButton` for
        // why `glassChrome(.floatingControl)` would be the wrong call here, and the
        // "Chrome" note above for the same argument about the bar.
        //
        // `entryPoint` is nil only when no run is on screen *and* the interval model is
        // `.failed`, i.e. a system clock outside `CalendarDay`'s domain. Drawing nothing
        // is the honest answer: there would be no subject to open a conversation about.
        .tabViewBottomAccessory {
            if let entryPoint {
                ChatEntryButton(entryPoint: entryPoint) {
                    chatOpening = ChatOpening(subject: entryPoint.subject)
                }
            }
        }
        // Attached to the `TabView` rather than inside the accessory so the sheet is
        // presented by the app's root and covers the tab bar, matching how the workout
        // detail screen has presented this same sheet since MAX-097.
        //
        // `currentInterval` is read live rather than captured with the subject: it is
        // what §3.6(b)'s scope-mismatch note compares the thread's frozen window
        // against, and what **New chat** freezes a fresh one from — both of which want
        // the dashboard's window now, not the window at the instant of a tap.
        .sheet(item: $chatOpening) { opening in
            ChatSheet(subject: opening.subject, currentInterval: intervalModel.state.interval)
        }
        // MAX-163, FIRST-RUN-SPEC §4. `fullScreenCover`, not `sheet`: see
        // `FirstRunCoverView`'s own note for why a drag-dismissible sheet is wrong here.
        // Attached to the `TabView` — the same root the chat sheet presents from — so it
        // covers the tab bar too; the athlete has not set anything up yet, so there is
        // nothing behind it worth leaving reachable.
        .fullScreenCover(isPresented: $isPresentingFirstRunCover) {
            FirstRunCoverView(isPresented: $isPresentingFirstRunCover, recording: firstRunRecording)
        }
        // Resolved once, on first appearance, from the device-lifetime recording —
        // never from `FirstRunChecklist`, which answers a different question (what is
        // left to set up) and is MAX-164's setup card's seam, not this cover's. See
        // `FirstRunCoverGate`'s doc for why the two are deliberately not the same check.
        .onAppear {
            isPresentingFirstRunCover = FirstRunCoverGate.shouldPresent(firstRunRecording)
        }
        // Read by `chatEntryPointFocus(workoutID:)` on the workout detail screen. Set on
        // the `TabView` so every tab's navigation stack inherits it.
        .environment(chatEntryPoint)
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
