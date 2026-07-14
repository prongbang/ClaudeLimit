import WidgetKit
import SwiftUI

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: Date(), snapshot: UsageStore.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = UsageEntry(date: Date(), snapshot: UsageStore.load())
        // Data is refreshed by the menu bar app (which also reloads timelines);
        // this is just a fallback poll of the shared cache.
        let next = Date().addingTimeInterval(5 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct ClaudeLimitWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                case .systemSmall: SmallView(snapshot: snapshot)
                default: MediumView(snapshot: snapshot)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "gauge")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Open the ClaudeLimit app\nto fetch usage data")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .containerBackground(.background, for: .widget)
    }
}

private func color(for utilization: Double) -> Color {
    switch utilization {
    case ..<50: return .green
    case ..<80: return .orange
    default: return .red
    }
}

struct SmallView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        let u = snapshot.fiveHour?.utilization ?? 0
        VStack(spacing: 8) {
            Gauge(value: min(u, 100), in: 0...100) {
                Text("5h")
            } currentValueLabel: {
                Text("\(Int(u))%")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(color(for: u))

            Text("Claude Session")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let resets = snapshot.fiveHour?.resetsAt {
                Text("Resets \(resets.formatted(.relative(presentation: .named).locale(Locale(identifier: "en_US"))))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(4)
    }
}

struct MediumView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Claude Usage")
                    .font(.headline)
                Spacer()
                if snapshot.isStale {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .help("Data may be out of date")
                }
            }
            bar(title: "Session (5 hr)", window: snapshot.fiveHour)
            bar(title: "Weekly", window: snapshot.sevenDay)
            ForEach(snapshot.weeklyModelWindows, id: \.name) { item in
                bar(title: "Weekly · \(item.name)", window: item.window)
            }
        }
        .padding(4)
    }

    @ViewBuilder
    private func bar(title: String, window: UsageWindow?) -> some View {
        let u = window?.utilization ?? 0
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                if let resets = window?.resetsAt {
                    Text("Resets \(resets.formatted(.relative(presentation: .named).locale(Locale(identifier: "en_US"))))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("\(Int(u))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(color(for: u))
            }
            ProgressView(value: min(u, 100), total: 100)
                .tint(color(for: u))
        }
    }
}

@main
struct ClaudeLimitWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeLimitWidget", provider: UsageProvider()) { entry in
            ClaudeLimitWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Limit Usage")
        .description("Shows Claude session and weekly usage limits")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
