import AppKit
import Combine
import SwiftUI

@MainActor
final class FloatingHUDController {
    private var panel: NSPanel?
    private let state = HUDState()

    var shouldSuppressAutoShow: Bool {
        (panel?.isVisible ?? false) && state.hasUserInteracted && !state.isLoading
    }

    var onAsk: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    func show(image: NSImage, autoDismiss: TimeInterval, position: HUDPosition) {
        let preservePrompt = (panel?.isVisible ?? false) && state.hasUserInteracted

        state.image = image
        if !preservePrompt {
            state.prompt = ""
            state.hasUserInteracted = false
        }
        state.isLoading = false

        let panel = panel ?? makePanel()
        place(panel: panel, position: position)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        if autoDismiss > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + autoDismiss) { [weak self] in
                guard let self else { return }
                guard !self.state.isLoading, !self.state.hasUserInteracted else { return }
                self.dismiss()
            }
        }
    }

    func setLoading(_ loading: Bool) {
        state.isLoading = loading
        if loading {
            state.hasUserInteracted = true
        }
    }

    func dismiss() {
        panel?.orderOut(nil)
        onDismiss?()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 260),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.title = "ScreenAsk"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false

        panel.contentView = NSHostingView(rootView: HUDContainerView(state: state) { [weak self] prompt in
            self?.onAsk?(prompt)
        } onDismiss: { [weak self] in
            self?.dismiss()
        })

        self.panel = panel
        return panel
    }

    private func place(panel: NSPanel, position: HUDPosition) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let width = panel.frame.width
        let height = panel.frame.height
        let margin: CGFloat = 20

        let x: CGFloat = position == .bottomRight
            ? visible.maxX - width - margin
            : visible.minX + margin
        let y: CGFloat = visible.minY + margin

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

@MainActor
final class HUDState: ObservableObject {
    @Published var image: NSImage = NSImage(size: NSSize(width: 1, height: 1))
    @Published var prompt: String = ""
    @Published var isLoading: Bool = false
    @Published var hasUserInteracted: Bool = false
}

struct HUDContainerView: View {
    @ObservedObject var state: HUDState
    let onAsk: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HUDView(
            image: state.image,
            prompt: $state.prompt,
            isLoading: state.isLoading,
            onPromptChanged: {
                state.hasUserInteracted = true
            },
            onAsk: { onAsk(state.prompt) },
            onDismiss: onDismiss
        )
    }
}
