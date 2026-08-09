import WidgetKit
import SwiftUI

struct Entry: TimelineEntry {
    let date: Date
    let sessions: [Session]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), sessions: []) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), sessions: Array(loadSessions().prefix(8))))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = Entry(date: Date(), sessions: Array(loadSessions().prefix(8)))
        // ponytail: plain 5-minute refresh. The app pokes reloadAllTimelines() on rename, so this is only for new sessions.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(300))))
    }
}

struct WidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    private var limit: Int { family == .systemLarge ? 8 : 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if entry.sessions.isEmpty {
                Text("No Claude sessions yet").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(entry.sessions.prefix(limit)) { s in
                Link(destination: URL(string: "claudesessions://resume/\(s.id)")!) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.label).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            .foregroundStyle(s.exists ? .primary : .tertiary)
                        Text(s.project).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct ClaudeSessionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeSessionsWidget", provider: Provider()) { WidgetView(entry: $0) }
            .configurationDisplayName("Claude Sessions")
            .description("Your recent Claude Code sessions. Click one to resume it in the terminal.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}
