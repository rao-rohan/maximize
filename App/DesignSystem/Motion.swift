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
// This file adds no animation. It is the seam later tickets attach to.

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
