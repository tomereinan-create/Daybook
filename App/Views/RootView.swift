import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("tab.today", systemImage: "sun.max") {
                TodayView()
            }
            Tab("tab.items", systemImage: "tray.full") {
                AllItemsView()
            }
        }
    }
}

#Preview {
    PreviewHost { RootView() }
}
