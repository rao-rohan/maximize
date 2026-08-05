import SwiftUI
import MaximizeCore

/// The persistent Ask control (§2.1, §7) — the app's one door into chat, in one place,
/// on every screen.
///
/// It decides nothing. Which subject a tap opens, what the button says, what VoiceOver
/// reads and which glyph it wears are all fields of `ChatEntryPoint` (`MaximizeCore`),
/// resolved by `RootTabView` from the screen currently showing. This view lays out four
/// strings and forwards a tap, which is what CLAUDE.md means by a thin shell.
///
/// ## No `glassChrome(.floatingControl)` here, deliberately
///
/// This control is mounted as the `TabView`'s bottom accessory, and the system draws
/// that container in Liquid Glass itself — the same situation as the tab bar above it
/// and the sheet this button opens. `RootTabView` and `SettingsToolbar.swift` both make
/// the argument in full: re-applying the platform's own material to the platform's own
/// control is how an app stops looking like the platform. It also means Reduce
/// Transparency and Increase Contrast are handled by the system here (MAX-070), exactly
/// as they are for the tab bar, rather than by a hand-rolled fallback.
///
/// Spec §7.1 expected this ticket to be `glassChrome(.floatingControl)`'s first call
/// site. It is not, and the reason is the mechanism: that case exists for a *custom*
/// floating control standing in for a system one, and this ticket found a system one.
///
/// ## Why the whole bar is the target
///
/// The accessory is full-width, so a content-sized button inside it would leave most of
/// a persistent, prominent strip inert — the classic "I tapped it and nothing happened"
/// surface. The label is centred and the hit area is the whole width.
struct ChatEntryButton: View {

    let entryPoint: ChatEntryPoint
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Dynamic Type first: at large text sizes "Ask about this run" stops fitting
            // a bar whose height the system owns, and truncating it would take away the
            // one thing the label is there to say. `ViewThatFits` drops to the compact
            // wording instead, which keeps the scope and loses only the verb.
            ViewThatFits(in: .horizontal) {
                labelRow(entryPoint.label)
                labelRow(entryPoint.compactLabel)
            }
            .frame(maxWidth: .infinity, minHeight: LayoutMetrics.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accent)
        // The visible label leans on the screen behind it; a VoiceOver user cannot
        // glance at that screen, so the spoken label always names the subject in full
        // and the hint names the window (§2.1). `children: .ignore` collapses the glyph
        // and text into one element so the control is read once, and the button trait is
        // added back because ignoring children drops it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entryPoint.accessibilityLabel)
        .accessibilityHint(entryPoint.accessibilityHint)
        .accessibilityAddTraits(.isButton)
    }

    private func labelRow(_ text: String) -> some View {
        HStack(spacing: Spacing.snug) {
            Image(systemName: ChatEntryPoint.glyphSystemImageName)
                .accessibilityHidden(true)
            Text(text)
                .lineLimit(1)
        }
        .font(.bodyCopy)
        .padding(.horizontal, LayoutMetrics.screenMargin)
    }
}
