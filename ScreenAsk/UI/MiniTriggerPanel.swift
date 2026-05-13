import AppKit
import SwiftUI

@MainActor
final class MiniTriggerPanelController {
    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    var onAskTapped: (() -> Void)?

    func show(autoDismiss: TimeInterval, position: HUDPosition) {
        let panel = panel ?? makePanel()
        place(panel: panel, position: position)
        panel.orderFrontRegardless()

        dismissWorkItem?.cancel()
        if autoDismiss > 0 {
            let work = DispatchWorkItem { [weak self] in
                self?.dismiss()
            }
            dismissWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + autoDismiss, execute: work)
        }
    }

    func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 210, height: 56),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        panel.contentView = NSHostingView(
            rootView: MiniTriggerView {
                self.onAskTapped?()
            }
        )

        self.panel = panel
        return panel
    }

    private func place(panel: NSPanel, position: HUDPosition) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let width = panel.frame.width
        let margin: CGFloat = 26

        let x: CGFloat = position == .bottomRight
            ? visible.maxX - width - margin
            : visible.minX + margin
        let y: CGFloat = visible.minY + 88

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

struct MiniTriggerView: View {
    let onAskTapped: () -> Void

    var body: some View {
        Button(action: onAskTapped) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                Text("Ask with ScreenAsk")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.8))
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}
