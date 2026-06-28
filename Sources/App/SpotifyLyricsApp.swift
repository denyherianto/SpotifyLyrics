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
    @Published var overlayOpacity: Double = 0.9
    private var opacitySaveTask: DispatchWorkItem?
    /// Remembers the last non-mini size so we can restore it when leaving mini mode.
    private var lastFullSize: OverlaySize = .medium
    @Published var overlaySize: OverlaySize = .medium {
        didSet {
            UserDefaults.standard.set(overlaySize.rawValue, forKey: "overlaySize")
            // Switching between mini ↔ full requires replacing the view, not just resizing
            if oldValue.isMini != overlaySize.isMini {
                switchOverlayMode?()
            } else {
                overlayWindow.resize(to: overlaySize)
            }
            if !overlaySize.isMini {
                lastFullSize = overlaySize
            }
        }
    }
    @Published var animationMode: AnimationMode = .karaoke {
        didSet { UserDefaults.standard.set(animationMode.rawValue, forKey: "animationMode") }
    }
    @Published var showRomanization: Bool = false {
        didSet { UserDefaults.standard.set(showRomanization, forKey: "showRomanization") }
    }
    @Published var showTranslation: Bool = false {
        didSet { UserDefaults.standard.set(showTranslation, forKey: "showTranslation") }
    }
    @Published var showSongSummary: Bool = true {
        didSet { UserDefaults.standard.set(showSongSummary, forKey: "showSongSummary") }
    }
    @Published var aiTranslationMode: AITranslationMode = .refine {
        didSet { UserDefaults.standard.set(aiTranslationMode.rawValue, forKey: "aiTranslationMode") }
    }
    @Published var targetLanguage: TranslationLanguage = .indonesian {
        didSet { UserDefaults.standard.set(targetLanguage.rawValue, forKey: "targetLanguage") }
    }
    let overlayWindow = LyricsOverlayWindow()

    /// Callback set by AppDelegate to rebuild the overlay when switching mini ↔ full.
    var switchOverlayMode: (() -> Void)?

    /// Switch to mini mode, or back to the last full size.
    func toggleMiniMode() {
        if overlaySize.isMini {
            overlaySize = lastFullSize
        } else {
            lastFullSize = overlaySize
            overlaySize = .mini
        }
    }

    /// Debounced opacity persistence — avoids disk I/O on every slider frame.
    func commitOpacity() {
        opacitySaveTask?.cancel()
        let value = overlayOpacity
        let task = DispatchWorkItem {
            UserDefaults.standard.set(value, forKey: "overlayOpacity")
        }
        opacitySaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
    }

    init() {
        let defaults = UserDefaults.standard

        if let saved = defaults.string(forKey: "overlaySize"),
           let size = OverlaySize(rawValue: saved) {
            self._overlaySize = Published(initialValue: size)
            if !size.isMini {
                self.lastFullSize = size
            }
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
        if let saved = defaults.string(forKey: "animationMode"),
           let mode = AnimationMode(rawValue: saved) {
            self._animationMode = Published(initialValue: mode)
        }
        if defaults.object(forKey: "showRomanization") != nil {
            self._showRomanization = Published(initialValue: defaults.bool(forKey: "showRomanization"))
        }
        if defaults.object(forKey: "showTranslation") != nil {
            self._showTranslation = Published(initialValue: defaults.bool(forKey: "showTranslation"))
        }
        if defaults.object(forKey: "showSongSummary") != nil {
            self._showSongSummary = Published(initialValue: defaults.bool(forKey: "showSongSummary"))
        }
        if let saved = defaults.string(forKey: "aiTranslationMode"),
           let mode = AITranslationMode(rawValue: saved) {
            self._aiTranslationMode = Published(initialValue: mode)
        }
        if let saved = defaults.string(forKey: "targetLanguage"),
           let lang = TranslationLanguage(rawValue: saved) {
            self._targetLanguage = Published(initialValue: lang)
        }
    }

    func show(lyricsManager: LyricsManager, playerManager: SpotifyPlayerManager) {
        if overlaySize.isMini {
            showMini(lyricsManager: lyricsManager, playerManager: playerManager)
        } else {
            showFull(lyricsManager: lyricsManager, playerManager: playerManager)
        }
    }

    private func showFull(lyricsManager: LyricsManager, playerManager: SpotifyPlayerManager) {
        let opacityBinding = Binding<Double>(
            get: { [weak self] in self?.overlayOpacity ?? 0.9 },
            set: { [weak self] in self?.overlayOpacity = $0 }
        )
        let animationModeBinding = Binding<AnimationMode>(
            get: { [weak self] in self?.animationMode ?? .karaoke },
            set: { [weak self] in self?.animationMode = $0 }
        )
        let view = LyricsOverlayView(lyricsManager: lyricsManager, playerManager: playerManager, backgroundOpacity: opacityBinding, animationMode: animationModeBinding, onClose: { [weak self] in
            self?.hide()
        })
        overlayWindow.show(with: view, size: overlaySize)
        isVisible = true
    }

    private func showMini(lyricsManager: LyricsManager, playerManager: SpotifyPlayerManager) {
        let opacityBinding = Binding<Double>(
            get: { [weak self] in self?.overlayOpacity ?? 0.9 },
            set: { [weak self] in self?.overlayOpacity = $0 }
        )
        let animationModeBinding = Binding<AnimationMode>(
            get: { [weak self] in self?.animationMode ?? .karaoke },
            set: { [weak self] in self?.animationMode = $0 }
        )
        let view = MiniOverlayView(
            lyricsManager: lyricsManager,
            playerManager: playerManager,
            backgroundOpacity: opacityBinding,
            animationMode: animationModeBinding,
            onSwitchToFull: { [weak self] in
                self?.toggleMiniMode()
            },
            onClose: { [weak self] in
                self?.hide()
            }
        )
        overlayWindow.show(with: view, size: .mini)
        isVisible = true
    }

    /// Rebuild the overlay with the correct view type after switching mini ↔ full.
    func rebuildOverlay(lyricsManager: LyricsManager, playerManager: SpotifyPlayerManager) {
        if overlaySize.isMini {
            let opacityBinding = Binding<Double>(
                get: { [weak self] in self?.overlayOpacity ?? 0.9 },
                set: { [weak self] in self?.overlayOpacity = $0 }
            )
            let animationModeBinding = Binding<AnimationMode>(
                get: { [weak self] in self?.animationMode ?? .karaoke },
                set: { [weak self] in self?.animationMode = $0 }
            )
            let view = MiniOverlayView(
                lyricsManager: lyricsManager,
                playerManager: playerManager,
                backgroundOpacity: opacityBinding,
                animationMode: animationModeBinding,
                onSwitchToFull: { [weak self] in
                    self?.toggleMiniMode()
                },
                onClose: { [weak self] in
                    self?.hide()
                }
            )
            overlayWindow.replaceContent(with: view, size: .mini)
        } else {
            let opacityBinding = Binding<Double>(
                get: { [weak self] in self?.overlayOpacity ?? 0.9 },
                set: { [weak self] in self?.overlayOpacity = $0 }
            )
            let animationModeBinding = Binding<AnimationMode>(
                get: { [weak self] in self?.animationMode ?? .karaoke },
                set: { [weak self] in self?.animationMode = $0 }
            )
            let view = LyricsOverlayView(lyricsManager: lyricsManager, playerManager: playerManager, backgroundOpacity: opacityBinding, animationMode: animationModeBinding, onClose: { [weak self] in
                self?.hide()
            })
            overlayWindow.replaceContent(with: view, size: overlaySize)
        }
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

/// Shared app state singleton for App Intents access.
@MainActor
final class AppState {
    static let shared = AppState()
    var playerManager: SpotifyPlayerManager?
    var lyricsManager: LyricsManager?
    var overlayController: OverlayController?
    private init() {}
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let playerManager = SpotifyPlayerManager()
    let lyricsManager = LyricsManager()
    let overlayController = OverlayController()
    let soundClassifier = SoundClassifier()
    private var statusBarController: StatusBarController?
    private var cancellables = Set<AnyCancellable>()
    private var enrichmentDebounceTask: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Expose shared state for App Intents
        AppState.shared.playerManager = playerManager
        AppState.shared.lyricsManager = lyricsManager
        AppState.shared.overlayController = overlayController

        // Setup menu bar status item with scrolling track info
        statusBarController = StatusBarController(
            playerManager: playerManager,
            lyricsManager: lyricsManager,
            overlayController: overlayController,
            soundClassifier: soundClassifier
        )

        // Sync enrichment settings to LyricsManager
        lyricsManager.showRomanization = overlayController.showRomanization
        lyricsManager.showTranslation = overlayController.showTranslation
        lyricsManager.showSongSummary = overlayController.showSongSummary
        lyricsManager.aiTranslationMode = overlayController.aiTranslationMode
        lyricsManager.targetLanguage = overlayController.targetLanguage.rawValue

        // Sync enrichment settings and debounce refresh to avoid
        // multiple expensive enrichment calls when toggling quickly.
        overlayController.$showRomanization
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self else { return }
                self.lyricsManager.showRomanization = value
                self.scheduleEnrichmentRefresh()
            }
            .store(in: &cancellables)

        overlayController.$showTranslation
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self else { return }
                self.lyricsManager.showTranslation = value
                self.scheduleEnrichmentRefresh()
            }
            .store(in: &cancellables)

        overlayController.$targetLanguage
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self else { return }
                self.lyricsManager.targetLanguage = value.rawValue
                if self.lyricsManager.showTranslation {
                    self.scheduleEnrichmentRefresh()
                }
            }
            .store(in: &cancellables)

        overlayController.$showSongSummary
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self else { return }
                self.lyricsManager.showSongSummary = value
            }
            .store(in: &cancellables)

        overlayController.$aiTranslationMode
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (value: AITranslationMode) in
                guard let self else { return }
                self.lyricsManager.aiTranslationMode = value
                if self.lyricsManager.showTranslation {
                    self.scheduleEnrichmentRefresh()
                }
            }
            .store(in: &cancellables)

        // Wire up mini ↔ full switching callback
        overlayController.switchOverlayMode = { [weak self] in
            guard let self else { return }
            self.overlayController.rebuildOverlay(
                lyricsManager: self.lyricsManager,
                playerManager: self.playerManager
            )
        }

        playerManager.onTrackChanged = { [weak self] track in
            guard let self else { return }
            Task { @MainActor in
                self.lyricsManager.fetchLyrics(for: track)
            }
        }

        playerManager.startPolling()

        // Position tracking: fixed-interval fallback at 100ms
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let pos = self.playerManager.playbackPosition
                self.lyricsManager.updateCurrentLine(at: pos)
                self.lyricsManager.updateInstrumentalBreak(at: pos)
                self.scheduleNextLine()
            }
        }

        // Predictive line switching: fires precisely at next line's timestamp
        playerManager.onPredictiveLineSwitch = { [weak self] position in
            guard let self else { return }
            self.lyricsManager.updateCurrentLine(at: position)
            self.lyricsManager.updateInstrumentalBreak(at: position)
            self.scheduleNextLine()
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

    /// Coalesces rapid enrichment setting changes into a single refresh.
    private func scheduleEnrichmentRefresh() {
        enrichmentDebounceTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.lyricsManager.refreshEnrichment()
        }
        enrichmentDebounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
    }

    private func scheduleNextLine() {
        if let nextTimestamp = lyricsManager.nextLineTimestamp {
            playerManager.scheduleNextLineSwitch(at: nextTimestamp)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        playerManager.stopPolling()
        overlayController.overlayWindow.close()
    }
}
