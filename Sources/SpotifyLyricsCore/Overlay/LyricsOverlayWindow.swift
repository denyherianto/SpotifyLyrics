import AppKit
import SwiftUI

public final class LyricsOverlayWindow {
    private var panel: NSPanel?

    public var isVisible: Bool {
        panel?.isVisible ?? false
    }

    public init() {}

    public func show(with view: some View, size: OverlaySize = .medium) {
        if panel != nil {
            panel?.orderFront(nil)
            return
        }

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        let (width, height) = size.dimensions
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
        panel.acceptsMouseMovedEvents = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = panel.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hostingView)

        // Restore saved position
        panel.setFrameUsingName("LyricsOverlay")
        panel.setFrameAutosaveName("LyricsOverlay")

        panel.orderFront(nil)
        self.panel = panel
    }

    public func showIfCreated() {
        panel?.orderFront(nil)
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
        // No longer setting panel alphaValue — opacity is handled
        // per-view on the background only, so text/controls stay fully visible.
    }

    public func resize(to size: OverlaySize) {
        guard let panel else { return }
        let (width, height) = size.dimensions
        let currentFrame = panel.frame
        let newX = currentFrame.midX - width / 2
        let newY = currentFrame.midY - height / 2
        panel.setFrame(NSRect(x: newX, y: newY, width: width, height: height), display: true, animate: true)
    }

    public func close() {
        panel?.close()
        panel = nil
    }
}
