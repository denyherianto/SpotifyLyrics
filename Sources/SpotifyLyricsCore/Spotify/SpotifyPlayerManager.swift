import Foundation
import Combine

@MainActor
public final class SpotifyPlayerManager: ObservableObject {
    @Published public var currentTrack: TrackInfo?
    @Published public var playerState: AppleScriptBridge.PlayerState = .stopped
    @Published public var isSpotifyRunning = false
    @Published public var isShuffling = false
    @Published public var isRepeating = false
    @Published public var artworkURL: URL?
    @Published public var isLiked: Bool = false

    private let bridge = AppleScriptBridge()
    private let accessibilityBridge = AccessibilityBridge()
    private var pollTimer: Timer?
    private var lastTrackKey: String?

    // Interpolation state: we record the Spotify position + wall-clock time
    // at each poll, then estimate current position between polls.
    private var lastPolledPosition: TimeInterval = 0
    private var lastPollTime: CFAbsoluteTime = 0

    /// Returns the interpolated playback position.
    /// Between AppleScript polls, this advances smoothly using wall-clock time.
    public var playbackPosition: TimeInterval {
        guard playerState == .playing else { return lastPolledPosition }
        let elapsed = CFAbsoluteTimeGetCurrent() - lastPollTime
        return lastPolledPosition + elapsed
    }

    public var onTrackChanged: ((TrackInfo) -> Void)?

    /// Whether to use Accessibility APIs for faster supplementary polling.
    public var useAccessibility: Bool = true

    public init() {}

    public func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
        poll()
    }

    public func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Fast supplementary poll using Accessibility APIs.
    /// Much faster than AppleScript (~1-5ms vs ~50-200ms).
    /// Called between AppleScript polls for smoother state updates.
    public func accessibilityPoll() {
        guard useAccessibility, AccessibilityBridge.isAccessibilityEnabled else { return }
        guard let info = accessibilityBridge.getPlaybackInfo() else { return }

        // Update like status (not available via AppleScript)
        isLiked = info.isLiked

        // Update playing state faster than AppleScript
        let newState: AppleScriptBridge.PlayerState = info.isPlaying ? .playing : .paused
        if newState != playerState {
            playerState = newState
        }
    }

    private func poll() {
        let pollStart = CFAbsoluteTimeGetCurrent()

        // Single AppleScript call that also detects if Spotify is not running
        guard let info = bridge.getPlaybackInfo() else {
            isSpotifyRunning = false
            currentTrack = nil
            playerState = .stopped
            lastPolledPosition = 0
            lastTrackKey = nil
            return
        }

        let pollEnd = CFAbsoluteTimeGetCurrent()

        // Use the midpoint between call start and end as the best estimate of
        // when Spotify actually sampled its player position. Using pollStart
        // alone causes overshoot (roundtrip duration added to interpolation);
        // using pollEnd alone causes undershoot. The midpoint minimizes error.
        let pollMid = (pollStart + pollEnd) / 2

        isSpotifyRunning = true
        playerState = info.state
        lastPolledPosition = info.position
        lastPollTime = pollMid
        isShuffling = info.isShuffling
        isRepeating = info.isRepeating

        let newKey = info.track.cacheKey
        if newKey != lastTrackKey && !info.track.title.isEmpty {
            lastTrackKey = newKey
            currentTrack = info.track
            if let urlStr = info.artworkURLString, let url = URL(string: urlStr) {
                artworkURL = url
            } else {
                artworkURL = nil
            }
            onTrackChanged?(info.track)
        }
    }

    public func seekTo(_ position: TimeInterval) {
        bridge.seekTo(position)
        lastPolledPosition = position
        lastPollTime = CFAbsoluteTimeGetCurrent()
    }

    public func playPause() {
        bridge.playPause()
        playerState = (playerState == .playing) ? .paused : .playing
    }

    public func nextTrack() {
        bridge.nextTrack()
    }

    public func previousTrack() {
        bridge.previousTrack()
    }

    public func toggleShuffle() {
        let newValue = !isShuffling
        bridge.setShuffling(newValue)
        isShuffling = newValue
    }

    public func toggleRepeat() {
        let newValue = !isRepeating
        bridge.setRepeating(newValue)
        isRepeating = newValue
    }

    /// Test helper: directly set interpolation state without polling Spotify.
    public func setInterpolationState(position: TimeInterval, pollTime: CFAbsoluteTime) {
        lastPolledPosition = position
        lastPollTime = pollTime
    }

    deinit {
        pollTimer?.invalidate()
    }
}
