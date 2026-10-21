import SwiftUI
import WidgetKit

struct PREntry: TimelineEntry { let date: Date; let snapshot: PRSnapshot }
struct PRProvider: TimelineProvider {
    func placeholder(in context: Context) -> PREntry { PREntry(date: Date(), snapshot: PRSnapshot()) }
    func getSnapshot(in context: Context, completion: @escaping (PREntry) -> Void) { completion(entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PREntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(1800))))
    }
    private func entry() -> PREntry {
        do { return PREntry(date: Date(), snapshot: try SharedStore.open().read()) }
        catch { var snapshot = PRSnapshot(); snapshot.error = error.localizedDescription; return PREntry(date: Date(), snapshot: snapshot) }
    }
}
@main struct PRWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedStore.widgetKind, provider: PRProvider()) { entry in
            PRWidgetView(snapshot: entry.snapshot).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("GitHub PR")
        .description("Ваши открытые PR, новые комментарии и статусы ревью.")
        .supportedFamilies([.systemLarge])
    }
}
