import SwiftData
import SwiftUI
import UserNotifications

@main
struct DaybookApp: App {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    private let notificationDelegate: NotificationDelegate

    init() {
        let store = DataStore()
        let model = AppModel(store: store)
        _model = State(initialValue: model)

        // Set before the first launch finishes, or an action tapped on a
        // notification that opened the app is dropped.
        notificationDelegate = NotificationDelegate { key, action in
            await model.apply(action, to: key)
        }
        UNUserNotificationCenter.current().delegate = notificationDelegate

        BackgroundRefresh.register {
            await model.reschedule()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .modelContainer(model.store.container)
                .task {
                    await model.start()
                    BackgroundRefresh.schedule()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Coming back from the background is the cheapest chance to
                // catch up on a day that rolled over while the app was closed.
                Task { await model.reschedule() }
            case .background:
                // Leaving the app is usually locking the phone, and that is
                // the moment the day summary has to be freshly delivered. One
                // posted while the app was open has already been seen, so the
                // lock screen files it away rather than showing it — which is
                // exactly the state it was found in: delivered, and nowhere
                // to be seen.
                Task { await model.postDaySummaryNow() }
            default:
                break
            }
        }
    }
}
