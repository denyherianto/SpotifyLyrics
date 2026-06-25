import SwiftUI
import AppKit
import SpotifyLyricsCore

@main
struct SpotifyLyricsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("SpotifyLyrics", systemImage: "music.note.list") {
            MenuBarView()
                .environmentObject(appDelegate.playerManager)
                .environmentObject(appDelegate.lyricsManager)
                .environmentObject(appDelegate.overlayController)
        }
    }
}

@MainActor
final class OverlayController: ObservableObject {
    @Published var isVisible = true
    @Published var alwaysOnTop = true {
        didSet { overlayWindow.setAlwaysOnTop(alwaysOnTop) }
    }
    @Published var overlayOpacity: Double = 0.9 {
        didSet { overlayWindow.setOpacity(overlayOpacity) }
    }
    @Published var overlaySize: OverlaySize = .medium {
        didSet {
            overlayWindow.resize(to: overlaySize)
            UserDefaults.standard.set(overlaySize.rawValue, forKey: "overlaySize")
        }
    }

    let overlayWindow = LyricsOverlayWindow()

    init() {
        if let saved = UserDefaults.standard.string(forKey: "overlaySize"),
           let size = OverlaySize(rawValue: saved) {
            self._overlaySize = Published(initialValue: size)
        }
    }

    func show(lyricsManager: LyricsManager, playerManager: SpotifyPlayerManager) {
        let view = LyricsOverlayView(lyricsManager: lyricsManager, playerManager: playerManager, onClose: { [weak self] in
            self?.hide()
        })
        overlayWindow.show(with: view, size: overlaySize)
        isVisible = true
    }

    func toggle() {
        overlayWindow.toggle()
        isVisible = overlayWindow.isVisible
    }

    func hide() {
        overlayWindow.hide()
        isVisible = false
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let playerManager = SpotifyPlayerManager()
    let lyricsManager = LyricsManager()
    let overlayController = OverlayController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        playerManager.onTrackChanged = { [weak self] track in
            guard let self else { return }
            Task { @MainActor in
                await self.lyricsManager.fetchLyrics(for: track)
            }
        }

        playerManager.startPolling()

        // Start position tracking for lyrics sync
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lyricsManager.updateCurrentLine(at: self.playerManager.playbackPosition)
            }
        }

        // Show overlay
        overlayController.show(lyricsManager: lyricsManager, playerManager: playerManager)
    }

    func applicationWillTerminate(_ notification: Notification) {
        playerManager.stopPolling()
        overlayController.overlayWindow.close()
    }
}
