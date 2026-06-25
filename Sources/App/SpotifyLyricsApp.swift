import SwiftUI
import AppKit
import Combine
import SpotifyLyricsCore

@main
struct SpotifyLyricsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class OverlayController: ObservableObject {
    @Published var isVisible = true {
        didSet { UserDefaults.standard.set(isVisible, forKey: "overlayVisible") }
    }
    @Published var alwaysOnTop = true {
        didSet {
            overlayWindow.setAlwaysOnTop(alwaysOnTop)
            UserDefaults.standard.set(alwaysOnTop, forKey: "overlayAlwaysOnTop")
        }
    }
    @Published var overlayOpacity: Double = 0.9 {
        didSet {
            UserDefaults.standard.set(overlayOpacity, forKey: "overlayOpacity")
        }
    }
    @Published var overlaySize: OverlaySize = .medium {
        didSet {
            overlayWindow.resize(to: overlaySize)
            UserDefaults.standard.set(overlaySize.rawValue, forKey: "overlaySize")
        }
    }
    @Published var showMenuBarTrackInfo: Bool = true {
        didSet { UserDefaults.standard.set(showMenuBarTrackInfo, forKey: "showMenuBarTrackInfo") }
    }

    let overlayWindow = LyricsOverlayWindow()

    init() {
        let defaults = UserDefaults.standard

        if let saved = defaults.string(forKey: "overlaySize"),
           let size = OverlaySize(rawValue: saved) {
            self._overlaySize = Published(initialValue: size)
        }
        if defaults.object(forKey: "overlayOpacity") != nil {
            self._overlayOpacity = Published(initialValue: defaults.double(forKey: "overlayOpacity"))
        }
        if defaults.object(forKey: "overlayAlwaysOnTop") != nil {
            self._alwaysOnTop = Published(initialValue: defaults.bool(forKey: "overlayAlwaysOnTop"))
        }
        if defaults.object(forKey: "overlayVisible") != nil {
            self._isVisible = Published(initialValue: defaults.bool(forKey: "overlayVisible"))
        }
        if defaults.object(forKey: "showMenuBarTrackInfo") != nil {
            self._showMenuBarTrackInfo = Published(initialValue: defaults.bool(forKey: "showMenuBarTrackInfo"))
        }
    }

    func show(lyricsManager: LyricsManager, playerManager: SpotifyPlayerManager) {
        let opacityBinding = Binding<Double>(
            get: { [weak self] in self?.overlayOpacity ?? 0.9 },
            set: { [weak self] in self?.overlayOpacity = $0 }
        )
        let view = LyricsOverlayView(lyricsManager: lyricsManager, playerManager: playerManager, backgroundOpacity: opacityBinding, onClose: { [weak self] in
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
    private var statusBarController: StatusBarController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Setup menu bar status item with scrolling track info
        statusBarController = StatusBarController(
            playerManager: playerManager,
            lyricsManager: lyricsManager,
            overlayController: overlayController
        )

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

        // Show overlay (respect saved visibility)
        overlayController.show(lyricsManager: lyricsManager, playerManager: playerManager)
        if !overlayController.isVisible {
            overlayController.hide()
        }

        // Auto-hide overlay when Spotify closes, re-show when it opens
        playerManager.$isSpotifyRunning
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                guard let self else { return }
                if running {
                    if self.overlayController.isVisible {
                        self.overlayController.overlayWindow.showIfCreated()
                    }
                } else {
                    self.overlayController.overlayWindow.hide()
                }
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        playerManager.stopPolling()
        overlayController.overlayWindow.close()
    }
}
