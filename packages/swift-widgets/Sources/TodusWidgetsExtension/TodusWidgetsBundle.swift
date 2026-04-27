import WidgetKit
import SwiftUI

@main
struct TodusWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DailyOverviewWidget()
        CalendarWidget()
        TasksWidget()
        EmailWidget()
        SmartInsightWidget()
    }
}
