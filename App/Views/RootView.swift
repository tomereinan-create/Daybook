import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var showsOnboarding = !SharedDefaults.onboardingComplete

    var body: some View {
        TabView {
            Tab("tab.today", systemImage: "sun.max") {
                TodayView()
            }
            Tab("tab.items", systemImage: "tray.full") {
                AllItemsView()
            }
            Tab("tab.review", systemImage: "chart.bar") {
                ReviewView()
            }
            Tab("tab.settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .sheet(isPresented: $showsOnboarding) {
            OnboardingView()
        }
    }
}

#Preview {
    PreviewHost { RootView() }
}
