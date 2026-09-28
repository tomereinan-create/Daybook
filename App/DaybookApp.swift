import SwiftData
import SwiftUI

@main
struct DaybookApp: App {
    @State private var model: AppModel

    init() {
        let store = DataStore()
        _model = State(initialValue: AppModel(store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .modelContainer(model.store.container)
        }
    }
}
