import Foundation
// ActivityKit is only available with the "NSSupportsLiveActivities" entitlement.
// Uncomment the import and the TODO sections below once the widget extension target is added.
// import ActivityKit

// TODO: Dynamic Island / Live Activity support
//
// To enable the Dynamic Island quick-chat feature, follow these steps:
//
// 1. Add a new "Widget Extension" target to the Xcode project (File > New Target > Widget Extension).
//    Check "Include Live Activity" when creating the target.
//
// 2. Define the ActivityAttributes conforming type:
//
// struct OpenGalActivityAttributes: ActivityAttributes {
//     struct ContentState: Codable, Hashable {
//         var lastAssistantMessage: String
//         var isTyping: Bool
//     }
//     var sessionTitle: String
// }
//
// 3. In the widget extension, implement the ActivityConfiguration view for:
//    - .dynamicIsland(for:) with .compactLeading, .compactTrailing, .minimal, and .expanded views
//    - .systemSmall / .systemMedium for the Lock Screen banner
//
// 4. In the expanded Dynamic Island view, embed a TextField bound to a shared AppGroup
//    UserDefaults key (e.g. "dynamicIslandQuickInput"), so the user can type from the island.
//
// 5. In the main app, read that key on foreground and call ChatViewModel.sendQuickMessage(_:).
//
// 6. Start the Live Activity when the first message is sent, and update ContentState
//    after each assistant reply:
//
// Activity<OpenGalActivityAttributes>.request(
//     attributes: OpenGalActivityAttributes(sessionTitle: "OpenGal"),
//     contentState: .init(lastAssistantMessage: "", isTyping: true),
//     pushType: nil
// )
//
// activity.update(using: .init(lastAssistantMessage: reply, isTyping: false))
//
// 7. End the activity when the conversation is cleared or the app terminates.
//
// References:
//   - https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
//   - https://developer.apple.com/documentation/activitykit/updating-and-ending-your-live-activity-with-activitykit-push-notifications

class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    // TODO: replace stubs with actual Activity<OpenGalActivityAttributes> instance
    func startActivity(sessionTitle: String) {
        // TODO: implement
    }

    func updateActivity(assistantReply: String, isTyping: Bool) {
        // TODO: implement
    }

    func endActivity() {
        // TODO: implement
    }
}
