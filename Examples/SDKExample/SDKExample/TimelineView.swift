import SwiftUI

struct TimelineTabView: View {
    var body: some View {
        ContentUnavailableView(
            "Timeline",
            systemImage: "clock",
            description: Text("Coming soon.")
        )
        .navigationTitle("Timeline")
    }
}

#Preview {
    NavigationStack { TimelineTabView() }
}
