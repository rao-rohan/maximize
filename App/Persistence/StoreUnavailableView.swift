import SwiftUI
import MaximizeCore

/// What the app shows in place of itself when its one store did not open (MAX-169).
///
/// **This view decides nothing and writes nothing.** Which state is showing is
/// `PersistenceComposition.availability`; every word is `FailureCopy
/// .storeAvailability(_:)`; whether a button exists at all is `StoreOpenFailureReason
/// .isWorthTryingAgain`. It is `FirstRunCardView`'s shape — heading, paragraph, optional
/// second paragraph at secondary weight, at most one button — for the same reason, and
/// the layout is deliberately the same so the two most consequential "the app has
/// something to tell you" screens do not read as different apps.
///
/// ## Why this replaces the app rather than sitting on top of it
///
/// The three tabs, the chat sheet and the settings screen all read the same store, so
/// with no store there is nothing behind this view to leave reachable — only nine
/// surfaces each reporting that its own content could not be loaded, which is what an
/// athlete currently sees and reads as several separate faults rather than one. Mounting
/// this *instead of* `RootTabView` has a second, mechanical consequence that is the real
/// reason for it: no screen's model is constructed while the store is shut, so none of
/// them captures the nil, and a retry that succeeds is picked up by every screen built
/// afterwards rather than by none of them.
///
/// ## No control here can destroy anything
///
/// CloudKit is deferred (A8), so this device's store is the athlete's only copy of their
/// history. `StoreNoticeAction` has exactly two cases and neither deletes, resets or
/// rebuilds anything — see that type for why the absence of a third is enforced by a test
/// rather than by everyone remembering.
///
/// ## Accessibility
///
/// - The three text elements are one VoiceOver stop, matching `FirstRunCardView`: they
///   are one statement, and three stops would make the reader assemble it.
/// - The button stays its own element, because combining an interactive control into a
///   text element loses its double-tap-to-activate behaviour.
/// - Scrolls, because the body is the longest single passage in the app and this is the
///   one screen an athlete cannot navigate away from to escape a clipped layout at large
///   Dynamic Type.
/// - No state is carried by colour: the heading and body are the channel, and the
///   `textPrimary`/`textSecondary` pair already degrades correctly under Increase
///   Contrast (MAX-070's palette).
struct StoreUnavailableView: View {

    let notice: StoreAvailabilityNotice

    let perform: (StoreNoticeAction) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.roomy) {
                VStack(alignment: .leading, spacing: Spacing.compact) {
                    Text(notice.heading)
                        .font(.screenTitle)
                        .foregroundStyle(Color.textPrimary)

                    Text(notice.body)
                        .font(.bodyCopy)
                        .foregroundStyle(Color.textPrimary)

                    if let detail = notice.detail {
                        Text(detail)
                            .font(.metricLabel)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)

                if let action = notice.action, let actionLabel = notice.actionLabel {
                    Button {
                        perform(action)
                    } label: {
                        Text(actionLabel)
                            .frame(maxWidth: .infinity)
                    }
                    // The current bordered-prominent + accent pairing, as on the first-run
                    // cover and `PlanView`'s "Author a plan" — the platform's own button
                    // style rather than a hand-rolled one, which is the same rule
                    // `glassChrome` applies to chrome.
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accent)
                    .controlSize(.large)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .screenMargins()
            .padding(.vertical, Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Content, not chrome: this is a screen of words, and FR-4.2 keeps content
        // surfaces flat and opaque.
        .contentSurface(.screen)
    }
}
