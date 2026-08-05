import SwiftUI

/// The chat entry point on the workout detail screen (FR-2.1, MAX-081).
///
/// MAX-051 put the whole chat — transcript and composer — in a card here, inside the
/// detail screen's outer `ScrollView`. `WorkoutChatView`'s own documentation sets out
/// why a text field there could not be made to behave; this card is what remains on the
/// detail screen once the conversation moved to a screen of its own.
///
/// The sheet is created only when presented, so opening a workout does not construct a
/// `ChatModel` or a chat client for a conversation nobody asked for.
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
            // A `NavigationStack` purely for the title and the sheet's own Done button,
            // which `WorkoutChatView` supplies so that releasing focus and dismissing
            // are one action. No glass is applied: a sheet is chrome the system already
            // renders in Liquid Glass (FR-4.1).
            NavigationStack {
                WorkoutChatView(workoutID: workoutID)
            }
        }
    }
}
