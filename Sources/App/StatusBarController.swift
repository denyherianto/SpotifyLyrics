import AppKit
import SwiftUI
import Combine
import SpotifyLyricsCore

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let marqueeField: MarqueeTextField
    private let iconView: NSImageView
    private let containerView: NSView
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private let iconWidth: CGFloat = 22
    private let marqueeMaxWidth: CGFloat = 200
    private let spacing: CGFloat = 4

    init(playerManager: SpotifyPlayerManager,
         lyricsManager: LyricsManager,
         overlayController: OverlayController) {

        // Status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Icon
        let icon = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: "SpotifyLyrics")!
        icon.isTemplate = true
        iconView = NSImageView(image: icon)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        // Marquee
        marqueeField = MarqueeTextField()
        marqueeField.translatesAutoresizingMaskIntoConstraints = false
        marqueeField.isHidden = true

        // Container
        containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(iconView)
        containerView.addSubview(marqueeField)

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
        )
        popover.contentViewController = hostingController

        // Setup button
        if let button = statusItem.button {
            button.addSubview(containerView)

            NSLayoutConstraint.activate([
                containerView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                containerView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                containerView.topAnchor.constraint(equalTo: button.topAnchor),
                containerView.bottomAnchor.constraint(equalTo: button.bottomAnchor),

                iconView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 2),
                iconView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 18),
                iconView.heightAnchor.constraint(equalToConstant: 18),

                marqueeField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: spacing),
                marqueeField.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -2),
                marqueeField.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
                marqueeField.heightAnchor.constraint(equalToConstant: 18),
                marqueeField.widthAnchor.constraint(lessThanOrEqualToConstant: marqueeMaxWidth),
            ])

            button.action = #selector(handleButtonClick(_:))
            button.target = self
        }

        updateStatusItemLength(showMarquee: false)

        // Observe track, player state, and toggle setting
        playerManager.$currentTrack
            .combineLatest(playerManager.$playerState, overlayController.$showMenuBarTrackInfo)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track, state, showTrack in
                self?.updateMarquee(track: track, state: state, showTrack: showTrack)
            }
            .store(in: &cancellables)
    }

    private func updateMarquee(track: TrackInfo?, state: AppleScriptBridge.PlayerState, showTrack: Bool) {
        if state == .playing, let track, showTrack {
            let displayText = "\(track.artist) — \(track.title)"
            marqueeField.text = displayText as NSString
            marqueeField.isHidden = false
            updateStatusItemLength(showMarquee: true)
        } else {
            marqueeField.isHidden = true
            marqueeField.stopScrolling()
            marqueeField.text = nil
            updateStatusItemLength(showMarquee: false)
        }
    }

    private func updateStatusItemLength(showMarquee: Bool) {
        if showMarquee {
            // Icon + spacing + marquee (up to max width)
            let textWidth = min(marqueeField.textWidth, marqueeMaxWidth)
            statusItem.length = iconWidth + spacing + textWidth + 4
        } else {
            statusItem.length = iconWidth + 4
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
                // Let clicks on the status bar button through
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
