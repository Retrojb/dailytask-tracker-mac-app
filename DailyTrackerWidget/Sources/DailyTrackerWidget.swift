import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Widget Configuration

@main
struct DailyTrackerWidget: Widget {
    let kind: String = "DailyTrackerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyTrackerTimelineProvider()) { entry in
            DailyTrackerWidgetView(entry: entry)
        }
        .supportedFamilies([.systemSmall, .systemMedium])
        .configurationDisplayName("Daily Work Tracker")
        .description("View today's logged work and quick actions.")
    }
}
