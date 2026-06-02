import SwiftUI

struct ContentView: View {
    @ObservedObject var coordinator: AppCoordinator

    @Environment(\.openSettings) private var openSettings

    private let showsDebugInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ScreenAsk")
                .font(.headline)

            if showsDebugInfo {
                Text("Watching: \(coordinator.settings.watchFolderPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Latest screenshot:")
                    .font(.caption)
                Text(coordinator.latestScreenshotPath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("Status: \(coordinator.statusMessage)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Divider()
            }

            Button("Show HUD For Latest Screenshot") {
                coordinator.showHUDForLatestScreenshot()
            }
            .disabled(!coordinator.canShowHUDForLatestScreenshot)

            HStack {
                Button("Preferences") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                .buttonStyle(.plain)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(12)
        .frame(width: 360)
    }
}

#Preview {
    ContentView(coordinator: AppCoordinator())
}
