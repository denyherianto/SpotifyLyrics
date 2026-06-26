import AppKit
import SwiftUI
import Combine
import SpotifyLyricsCore

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(playerManager: SpotifyPlayerManager,
         lyricsManager: LyricsManager,
         overlayController: OverlayController,
         soundClassifier: SoundClassifier) {

        // Status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        // Popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 460)
        popover.behavior = .transient
        popover.animates = true

        let hostingController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(playerManager)
                .environmentObject(lyricsManager)
                .environmentObject(overlayController)
                .environmentObject(soundClassifier)
        )
        popover.contentViewController = hostingController

        // Setup button
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: "SpotifyLyrics")
            button.image?.isTemplate = true
            button.action = #selector(handleButtonClick(_:))
            button.target = self
        }
    }

    @objc private func handleButtonClick(_ sender: Any?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
            removeMonitors()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            addMonitors()
        }
    }

    private func addMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
            self?.removeMonitors()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, self.popover.isShown {
                if let button = self.statusItem.button, event.window == button.window {
                    return event
                }
            }
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    deinit {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}
