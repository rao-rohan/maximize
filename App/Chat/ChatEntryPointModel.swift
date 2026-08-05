import SwiftUI
import MaximizeCore

/// Holds what the persistent Ask button is sitting on top of (§7.5).
///
/// Deliberately almost empty. Everything this touches — which subject a focused run
/// resolves to, what the button then says, and the ordering rule that makes paging
/// between two runs land on the right one — is `ChatEntryPointFocus` and
/// `ChatEntryPoint` in `MaximizeCore`, tested on every commit. This type is the
/// `@Observable` box those values live in so a view can re-render when they change, and
/// it decides nothing.
///
/// Owned by `RootTabView` and placed in the environment, which is §7.5's own suggested
/// mechanism. The alternative it names — a `PreferenceKey` — is the more idiomatic
/// SwiftUI spelling for "a child tells an ancestor something", but preferences propagate
/// up a view hierarchy, and the ancestor here is on the far side of a `TabView`
/// containing three `NavigationStack`s. An environment object read by the one screen
/// that has something to report is the shape that stays legible through that.
@MainActor
@Observable
final class ChatEntryPointModel {

    private(set) var focus = ChatEntryPointFocus()

    /// A workout detail screen appeared.
    func focusWorkout(_ workoutID: UUID) {
        focus.focus(workoutID)
    }

    /// A workout detail screen disappeared. Ignored unless it is the one currently
    /// held — see `ChatEntryPointFocus` for the ordering this survives.
    func releaseWorkout(_ workoutID: UUID) {
        focus.release(workoutID)
    }
}

extension View {

    /// Tells the persistent Ask button that this screen is about one run, for as long as
    /// it is on screen (§2.1: the button reads "Ask about this run" and opens that run's
    /// thread).
    ///
    /// A modifier rather than two lines of `onAppear`/`onDisappear` at the call site so
    /// the pair cannot drift apart, in the same spirit as `settingsToolbarItem()`.
    func chatEntryPointFocus(workoutID: UUID) -> some View {
        modifier(ChatEntryPointFocusModifier(workoutID: workoutID))
    }
}

private struct ChatEntryPointFocusModifier: ViewModifier {
    let workoutID: UUID

    /// Optional on purpose. `WorkoutDetailView` is mounted from `RootTabView`, which
    /// always supplies one — but the non-optional form of this property traps when the
    /// value is absent, and a preview or a future host that renders the detail screen
    /// outside the tab hierarchy should lose the Ask button's subject-awareness, not
    /// crash.
    @Environment(ChatEntryPointModel.self) private var model: ChatEntryPointModel?

    func body(content: Content) -> some View {
        content
            .onAppear { model?.focusWorkout(workoutID) }
            .onDisappear { model?.releaseWorkout(workoutID) }
    }
}
