import SwiftUI
import WidgetKit

@main
struct CodexRadarApp: App {
    var body: some Scene {
        Window("Codex Radar", id: "radar") {
            RadarCompanion()
        }
        .windowResizability(.contentSize)
    }
}

private struct RadarCompanion: View {
    @State private var snapshot: RadarSnapshot?
    @State private var updating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RadarFace(snapshot: snapshot)
                .frame(width: RadarFace.width, height: RadarFace.height)
                .background(RadarFace.casing, in: RoundedRectangle(cornerRadius: 20))
            Text("在桌面空白处右键，选「编辑小组件」，搜索 Codex Radar。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: RadarFace.width, alignment: .leading)
            HStack {
                if updating { ProgressView().controlSize(.small) }
                Spacer()
                Button("重新取数") {
                    Task { await update(requestTimeline: true) }
                }
                .disabled(updating)
            }
        }
        .frame(width: RadarFace.width, alignment: .leading)
        .padding(20)
        .task {
            snapshot = await RadarStore.shared.cached()
            await update(requestTimeline: false)
        }
    }

    @MainActor
    private func update(requestTimeline: Bool) async {
        guard !updating else { return }
        updating = true
        let result = await RadarStore.shared.refresh()
        snapshot = result.snapshot
        updating = false
        if requestTimeline {
            WidgetCenter.shared.reloadTimelines(ofKind: RadarData.widgetKind)
        }
    }
}
