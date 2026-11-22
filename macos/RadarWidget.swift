import OSLog
import SwiftUI
import WidgetKit

struct RadarEntry: TimelineEntry {
    let date: Date
    let snapshot: RadarSnapshot?
}

struct RadarTimeline: TimelineProvider {
    private let logger = Logger(subsystem: "local.codexradar.desktop", category: "Widget")

    func placeholder(in context: Context) -> RadarEntry {
        RadarEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (RadarEntry) -> Void) {
        Task {
            let cached = await RadarStore.shared.cached()
            if context.isPreview {
                completion(RadarEntry(date: Date(), snapshot: cached ?? .preview))
            } else if let cached {
                completion(RadarEntry(date: Date(), snapshot: cached))
            } else {
                let result = await RadarStore.shared.refresh()
                completion(RadarEntry(date: Date(), snapshot: result.snapshot))
            }
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RadarEntry>) -> Void) {
        Task {
            let result = await RadarStore.shared.refresh()
            let now = Date()
            let entry = RadarEntry(date: now, snapshot: result.snapshot)
            let count = result.snapshot?.leaders.count ?? 0
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
            logger.info("Desktop timeline loaded \(count, privacy: .public) cards, live fetch \(result.successful, privacy: .public), build \(build, privacy: .public)")
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(result.reloadAfter))))
        }
    }
}

struct CodexRadarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RadarData.widgetKind, provider: RadarTimeline()) { entry in
            DesktopRadarFace(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Codex Radar")
        .description("质量前四、分数、成本和取数时间。")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

private struct DesktopRadarFace: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let snapshot: RadarSnapshot?

    var body: some View {
        RadarFace(snapshot: snapshot, tinted: renderingMode != .fullColor)
            .containerBackground(RadarFace.casing, for: .widget)
    }
}

@main
struct CodexRadarWidgets: WidgetBundle {
    var body: some Widget {
        CodexRadarWidget()
    }
}
