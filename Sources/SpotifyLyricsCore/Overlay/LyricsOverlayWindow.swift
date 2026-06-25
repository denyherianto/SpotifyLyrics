import AppKit
import SwiftUI

public final class LyricsOverlayWindow {
    private var panel: NSPanel?

    public var isVisible: Bool {
        panel?.isVisible ?? false
    }

    public init() {}

    public func show(with view: some View) {
        if panel != nil {
            panel?.orderFront(nil)
            return
        }

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        let width: CGFloat = 700
        let height: CGFloat = 260
        let x = screenFrame.midX - width / 2
        let y = screenFrame.minY + 20

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = panel.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hostingView)

        panel.orderFront(nil)
        self.panel = panel
    }

    public func hide() {
        panel?.orderOut(nil)
    }

    public func toggle() {
        if isVisible {
            hide()
        } else {
            panel?.orderFront(nil)
        }
    }

    public func setAlwaysOnTop(_ enabled: Bool) {
        panel?.level = enabled ? .floating : .normal
    }

    public func setOpacity(_ opacity: Double) {
        panel?.alphaValue = opacity
    }

    public func close() {
        panel?.close()
        panel = nil
    }
}
