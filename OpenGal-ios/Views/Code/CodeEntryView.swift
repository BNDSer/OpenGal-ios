import SwiftUI

// Root entry point for the Code feature.
// Presented as a fullScreenCover from ChatView, owns its own NavigationStack.
struct CodeEntryView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ServerListView()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                }
        }
    }
}
