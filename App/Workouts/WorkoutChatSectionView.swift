import SwiftUI
import MaximizeCore

/// The chat entry point on the workout detail screen (FR-2.1, MAX-081).
///
/// MAX-051 put the whole chat — transcript and composer — in a card here, inside the
/// detail screen's outer `ScrollView`. `ChatConversationView`'s own documentation sets
/// out why a text field there could not be made to behave; this card is what remains on
/// the detail screen once the conversation moved to a screen of its own.
///
/// The sheet is created only when presented, so opening a workout does not construct a
/// `ChatModel` or a chat client for a conversation nobody asked for.
///
/// ## MAX-097: presents `ChatSheet`, not a bare conversation
///
/// This is still the only door into chat today — the persistent Ask button MAX-098
/// describes is a later ticket. What changed is what the sheet contains: history (§2.3),
/// **New chat**, and the scope subtitle now live behind this same button, because
/// `ChatSheet` is the one presentation surface both this card and the eventual Ask
/// button will use. See `ChatSheet`'s own documentation for exactly the call MAX-098
/// will make.
///
/// No glass is applied here: a sheet is chrome the system already renders in Liquid
/// Glass (FR-4.1), and `ChatSheet` owns its own `NavigationStack` and toolbar.
struct WorkoutChatSectionView: View {
    let workoutID: UUID

    @State private var isPresentingChat = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text("Chat")
                .font(.sectionHeading)
                .foregroundStyle(Color.textPrimary)

            Text("Ask about this run — pacing, drift, whether it matched the plan.")
                .font(.bodyCopy)
                .foregroundStyle(Color.textSecondary)

            Button("Open chat") { isPresentingChat = true }
                .font(.bodyCopy)
                .foregroundStyle(Color.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentSurface(.card)
        .sheet(isPresented: $isPresentingChat) {
            ChatSheet(subject: .workout(workoutID))
        }
    }
}
