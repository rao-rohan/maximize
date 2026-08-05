import SwiftUI

// MARK: - Reduce Motion hook (FR-4.4 / FR-4.5)
//
// FR-4.4 wants motion that is "purposeful and physical, not decorative" — chart
// transitions, the tab-bar collapse, streaming-text reveal. None of that exists yet;
// the views it belongs to (MAX-041 onward) haven't been built. What MAX-070 owns is
// making sure that whenever it *is* built, honoring Reduce Motion is one call, not a
// re-derivation at every animation site — the same shape `glassChrome(_:)` gives
// Reduce Transparency in Surfaces.swift.
//
// MAX-152 attached the first ones. The seam is unchanged; what is new below is the
// `Motion` ramp — the durations and curves themselves, named once, so that a call site
// says *which* motion it is rather than how many milliseconds it lasts. Spacing and
// colour already work this way in this design system, and motion drifts for exactly the
// same reason those did: every literal is defensible on its own and the screen still
// ends up with four subtly different ideas of "quick".

/// The motion ramp.
///
/// Deliberately short. FR-4.4 wants motion that is purposeful and physical, not
/// decorative, so the set is the small number of *jobs* this app's animation actually
/// does — reveal text as it streams, settle a scroll, sweep a waiting indicator, change
/// a state — rather than a palette of curves to choose from. A new entry should be a new
/// job, and if it is not, one of these is the one to use.
///
/// **None of these is applied directly.** Every call site goes through
/// `accessibleAnimation(_:value:)` below, or checks `accessibilityReduceMotion` itself
/// where the animation is a `repeatForever` one that has to be *withheld* rather than
/// shortened (see `waitingSweep`).
enum Motion {

    /// Text arriving token by token in a chat reply (FR-4.4's "streaming-text reveal").
    ///
    /// Fast and one-directional: the text is what the athlete is reading, and an ease
    /// that takes longer than the gap between two tokens turns a reply into a wobble.
    static let streamingTextReveal: Animation = .easeOut(duration: 0.15)

    /// A transcript settling to its bottom anchor after a message, a state change or the
    /// keyboard. Slower than the reveal because it moves the whole surface, and a jump is
    /// what this is preventing.
    static let scrollSettle: Animation = .easeOut(duration: 0.2)

    /// The waiting indicator's gradient sweep (MAX-152) — the one animation in this app
    /// that repeats forever, and the one that has to be withheld rather than shortened
    /// under Reduce Motion.
    ///
    /// 1.4 seconds, linear, no autoreverse: a sweep that eases at its ends reads as a
    /// pulse, and a pulse is the loader this deliberately is not. Slow enough to be
    /// ambient rather than urgent — the live accessibility complaint about this pattern
    /// elsewhere is that it is *distracting*, and speed is the dial that makes it so.
    ///
    /// Not reachable through `accessibleAnimation(_:value:)`: that modifier substitutes
    /// `nil` under Reduce Motion, and a `repeatForever` animation whose value has already
    /// changed would not be re-evaluated. `ChatPendingReplyView` withholds the whole
    /// animated layer instead, which is a stronger guarantee — there is nothing left to
    /// animate rather than an animation that was asked to be instant.
    static let waitingSweep: Animation = .linear(duration: 1.4).repeatForever(autoreverses: false)

    /// A view swapping for another because the state behind it changed — the waiting
    /// indicator giving way to the first tokens of a reply.
    static let stateChange: Animation = .easeInOut(duration: 0.25)
}

extension View {

    /// Applies `animation`, keyed to `value`, unless Reduce Motion is on — in which
    /// case the state change still happens, just without the animation (FR-4.4/4.5).
    ///
    /// Reach for this instead of `.animation(_:value:)` directly for anything driven
    /// by user-visible motion (a chart transition, the tab-bar collapse, a
    /// streaming-text reveal), so the Reduce Motion check lives in one place rather
    /// than being copied to every call site — and so a call site that forgets it is
    /// visibly wrong in review, the same way `.glassChrome(.floatingControl)` on a
    /// chart is.
    func accessibleAnimation<Value: Equatable>(_ animation: Animation?, value: Value) -> some View {
        modifier(AccessibleAnimationModifier(animation: animation, value: value))
    }
}

private struct AccessibleAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation?
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
