import SwiftUI
import WidgetKit

@main
nonisolated struct DaybookWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        NextUpWidget()
        ProgressWidget()
        DaybookLiveActivity()
    }
}
