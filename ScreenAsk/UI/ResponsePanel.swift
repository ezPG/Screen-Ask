import AppKit
import Combine
import SwiftUI

@MainActor
final class ResponsePanelController {
    private var panel: NSPanel?
    private let state = ResponsePanelState()

    func show() {
        let panel = panel ?? makePanel()
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func append(_ text: String) {
        state.response += text
    }

    func reset() {
        state.response = ""
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "ScreenAsk Response"
        panel.isFloatingPanel = true
        panel.contentView = NSHostingView(rootView: ResponsePanelView(state: state))
        self.panel = panel
        return panel
    }
}

@MainActor
final class ResponsePanelState: ObservableObject {
    @Published var response: String = ""
}

struct ResponsePanelView: View {
    @ObservedObject var state: ResponsePanelState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AI Response")
                    .font(.headline)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(state.response, forType: .string)
                }
            }

            ScrollView {
                Text(state.response.isEmpty ? "Waiting for response..." : state.response)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
    }
}
