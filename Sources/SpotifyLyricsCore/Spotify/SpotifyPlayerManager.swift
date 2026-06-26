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
    private var axPollTimer: Timer?
    private var lastTrackKey: String?

    // MARK: - Interpolation State

    private var lastPolledPosition: TimeInterval = 0
    private var lastPollTime: CFAbsoluteTime = 0

    // MARK: - Drift Correction

    /// Accumulated drift correction factor. Positive = interpolation runs ahead.
    /// Applied as: correctedPosition = interpolatedPosition - driftOffset
    private var driftOffset: TimeInterval = 0

    /// Smoothing factor for exponential moving average of drift measurements.
    private let driftAlpha: Double = 0.3

    /// Returns the interpolated playback position with drift correction.
    public var playbackPosition: TimeInterval {
        guard playerState == .playing else { return lastPolledPosition }
        let elapsed = CFAbsoluteTimeGetCurrent() - lastPollTime
        return lastPolledPosition + elapsed - driftOffset
    }

    public var onTrackChanged: ((TrackInfo) -> Void)?

    // MARK: - Predictive Line Switching

    /// Timer for precise next-line switching.
    private var nextLineTimer: Timer?
    /// Callback invoked when the predictive timer fires at the next line's timestamp.
    public var onPredictiveLineSwitch: ((TimeInterval) -> Void)?

    public init() {}

    // MARK: - Polling

    public func startPolling() {
        pollTimer?.invalidate()
        // Primary AppleScript poll every 300ms
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
        poll()

        // Supplementary Accessibility poll every 100ms for faster state detection
        axPollTimer?.invalidate()
        axPollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.accessibilityPoll()
            }
        }
    }

    public func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        axPollTimer?.invalidate()
        axPollTimer = nil
        nextLineTimer?.invalidate()
        nextLineTimer = nil
    }

    /// Fast supplementary poll using Accessibility APIs (~1-5ms).
    /// Updates play/pause state and like status between AppleScript polls.
    private func accessibilityPoll() {
        guard AccessibilityBridge.isAccessibilityEnabled else { return }
        guard let info = accessibilityBridge.getPlaybackInfo() else { return }

        isLiked = info.isLiked

        let newState: AppleScriptBridge.PlayerState = info.isPlaying ? .playing : .paused
        if newState != playerState {
            playerState = newState
        }

        // Use AX progress to cross-check interpolation drift
        if let progress = info.progress, let track = currentTrack, track.duration > 0 {
            let axPosition = progress * track.duration
            let interpolated = playbackPosition
            let error = interpolated - axPosition

            // Only correct if the AX position looks reasonable (not 0, not stale)
            if axPosition > 0.5 && abs(error) < 5.0 {
                // Exponential moving average of drift
                driftOffset = driftOffset * (1 - driftAlpha) + error * driftAlpha
            }
        }
    }

    private func poll() {
        let pollStart = CFAbsoluteTimeGetCurrent()

        guard let info = bridge.getPlaybackInfo() else {
            isSpotifyRunning = false
            currentTrack = nil
            playerState = .stopped
            lastPolledPosition = 0
            lastTrackKey = nil
            driftOffset = 0
            return
        }

        let pollEnd = CFAbsoluteTimeGetCurrent()
        let pollMid = (pollStart + pollEnd) / 2

        // Drift correction: compare what we predicted vs what Spotify reports
        if playerState == .playing && lastPollTime > 0 {
            let predicted = lastPolledPosition + (pollMid - lastPollTime) - driftOffset
            let actual = info.position
            let error = predicted - actual

            // Only apply drift correction for reasonable errors (< 2s).
            // Larger jumps indicate seeks or track changes.
            if abs(error) < 2.0 {
                driftOffset = driftOffset * (1 - driftAlpha) + error * driftAlpha
            } else {
                // Large jump — reset drift
                driftOffset = 0
            }
        }

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
            driftOffset = 0  // Reset drift on track change
            if let urlStr = info.artworkURLString, let url = URL(string: urlStr) {
                artworkURL = url
            } else {
                artworkURL = nil
            }
            onTrackChanged?(info.track)
        }
    }

    // MARK: - Predictive Line Switching

    /// Schedule a precise timer to fire at the next lyric line's timestamp.
    /// Much more accurate than polling at fixed intervals — fires exactly when needed.
    ///
    /// - Parameter nextLineTimestamp: The absolute song timestamp of the next line.
    public func scheduleNextLineSwitch(at nextLineTimestamp: TimeInterval) {
        nextLineTimer?.invalidate()

        guard playerState == .playing else { return }

        let currentPos = playbackPosition
        let delay = nextLineTimestamp - currentPos

        guard delay > 0 && delay < 30 else { return }

        nextLineTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.onPredictiveLineSwitch?(self.playbackPosition)
            }
        }
    }

    // MARK: - Controls

    public func seekTo(_ position: TimeInterval) {
        bridge.seekTo(position)
        lastPolledPosition = position
        lastPollTime = CFAbsoluteTimeGetCurrent()
        driftOffset = 0
        nextLineTimer?.invalidate()
    }

    public func playPause() {
        bridge.playPause()
        playerState = (playerState == .playing) ? .paused : .playing
        if playerState == .paused {
            nextLineTimer?.invalidate()
        }
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
        driftOffset = 0
    }

    deinit {
        pollTimer?.invalidate()
        axPollTimer?.invalidate()
        nextLineTimer?.invalidate()
    }
}
