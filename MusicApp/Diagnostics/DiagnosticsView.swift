import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @Environment(CloudMusicStore.self) private var cloud
    @Environment(OnlineMusicStore.self) private var online
    @State private var diagnostics = AppDiagnostics.shared
    @State private var checking = false
    @State private var copied = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            List {
                Section {
                    Text("The session log stays in memory. Downloader progress uses a temporary file. Cookies, credentials and URL paths are hidden.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Current activity") {
                    if diagnostics.active.isEmpty { Text("No active requests").foregroundStyle(.secondary) }
                    ForEach(diagnostics.active) { operation in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(operation.name).font(.headline)
                            Text(operation.stage)
                            if !operation.detail.isEmpty { Text(operation.detail).font(.caption).textSelection(.enabled) }
                            Text("\(Int(timeline.date.timeIntervalSince(operation.stageStarted))) s in this step · \(Int(timeline.date.timeIntervalSince(operation.started))) s total")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if online.downloadingID != nil {
                        Button("Cancel preparation", role: .destructive) { online.cancelDownload() }
                    }
                }
                Section("Network checks") {
                    Button(checking ? "Checking…" : "Check connections") {
                        checking = true
                        Task {
                            await diagnostics.checkYouTubeConnection()
                            if cloud.connected { await cloud.checkDiagnosticsConnection() }
                            checking = false
                        }
                    }.disabled(checking)
                    Text("Checks YouTube and the connected warehouse. A reachable website does not guarantee that a particular audio download will work.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Session log · latest 300 events") {
                    Button(copied ? "Copied" : "Copy diagnostic log") {
                        UIPasteboard.general.string = diagnostics.report; copied = true
                    }.accessibilityIdentifier("copyDiagnostics")
                    ShareLink("Share diagnostic log", item: diagnostics.report)
                    Button("Clear log", role: .destructive) { diagnostics.clear(); copied = false }
                    ForEach(diagnostics.events.reversed()) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(event.date.formatted(date: .omitted, time: .standard)) · \(event.operation)").font(.caption).foregroundStyle(.secondary)
                            Text(event.message).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .navigationTitle("Debug").navigationBarTitleDisplayMode(.inline)
    }
}
