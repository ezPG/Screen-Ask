import AppKit
import Combine
import SwiftUI

@MainActor
final class FloatingHUDController {
    private var panel: NSPanel?
    private let state = HUDState()
    private var currentPosition: HUDPosition = .bottomRight

    private let compactSize = NSSize(width: 480, height: 360)
    private let expandedSize = NSSize(width: 520, height: 620)

    var shouldSuppressAutoShow: Bool {
        (panel?.isVisible ?? false) && state.hasUserInteracted && !state.isLoading
    }

    var onAsk: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    func show(image: NSImage, autoDismiss: TimeInterval?, position: HUDPosition) {
        currentPosition = position
        let preservePrompt = (panel?.isVisible ?? false) && state.hasUserInteracted

        state.image = image
        state.responseText = ""
        state.showResponse = false
        if !preservePrompt {
            state.prompt = ""
            state.hasUserInteracted = false
        }
        state.isLoading = false

        let panel = panel ?? makePanel()
        resize(panel: panel, size: compactSize)
        place(panel: panel, position: position)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        if let autoDismiss, autoDismiss > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + autoDismiss) { [weak self] in
                guard let self else { return }
                guard !self.state.isLoading, !self.state.hasUserInteracted else { return }
                self.dismiss()
            }
        }
    }

    func beginResponse() {
        state.responseText = ""
        state.showResponse = true
        if let panel {
            resize(panel: panel, size: expandedSize)
        }
    }

    func appendResponse(_ text: String) {
        if !state.showResponse {
            beginResponse()
        }
        state.responseText += text
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
            contentRect: NSRect(origin: .zero, size: compactSize),
            styleMask: [.fullSizeContentView, .titled],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = true

        panel.contentView = NSHostingView(rootView: HUDContainerView(state: state) { [weak self] prompt in
            self?.onAsk?(prompt)
        } onDismiss: { [weak self] in
            self?.dismiss()
        })

        self.panel = panel
        return panel
    }

    private func resize(panel: NSPanel, size: NSSize) {
        var frame = panel.frame

        let targetWidth = size.width
        let targetHeight = size.height

        let deltaW = targetWidth - frame.width
        let deltaH = targetHeight - frame.height

        // Grow upward from bottom edge.
        frame.origin.y -= deltaH

        // For bottom-right anchoring, grow inward to the left.
        if currentPosition == .bottomRight {
            frame.origin.x -= deltaW
        }

        frame.size.width = targetWidth
        frame.size.height = targetHeight

        frame = clampedFrame(frame)
        panel.setFrame(frame, display: true, animate: true)
    }

    private func place(panel: NSPanel, position: HUDPosition) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let width = panel.frame.width
        let margin: CGFloat = 20

        let x: CGFloat = position == .bottomRight
            ? visible.maxX - width - margin
            : visible.minX + margin
        let y: CGFloat = visible.minY + margin

        let frame = clampedFrame(NSRect(x: x, y: y, width: panel.frame.width, height: panel.frame.height))
        panel.setFrame(frame, display: true)
    }

    private func clampedFrame(_ frame: NSRect) -> NSRect {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return frame }
        let visible = screen.visibleFrame.insetBy(dx: 12, dy: 12)

        var clamped = frame

        if clamped.width > visible.width {
            clamped.size.width = visible.width
        }
        if clamped.height > visible.height {
            clamped.size.height = visible.height
        }

        clamped.origin.x = max(visible.minX, min(clamped.origin.x, visible.maxX - clamped.width))
        clamped.origin.y = max(visible.minY, min(clamped.origin.y, visible.maxY - clamped.height))

        return clamped
    }
}

@MainActor
final class HUDState: ObservableObject {
    @Published var image: NSImage = NSImage(size: NSSize(width: 1, height: 1))
    @Published var prompt: String = ""
    @Published var isLoading: Bool = false
    @Published var hasUserInteracted: Bool = false
    @Published var responseText: String = ""
    @Published var showResponse: Bool = false
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
            responseText: state.responseText,
            showResponse: state.showResponse,
            onPromptChanged: {
                state.hasUserInteracted = true
            },
            onAsk: { onAsk(state.prompt) },
            onDismiss: onDismiss
        )
    }
}
