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

    // MARK: - Poll Scheduling

    /// True while a background AppleScript read is in flight — prevents overlapping
    /// (and therefore contending) Apple-event round-trips if one runs long.
    private var isAppleScriptPolling = false
    /// True while a background Accessibility read is in flight.
    private var isAXPolling = false
    /// Counts skipped AppleScript ticks while idle (paused/stopped) so we can back the
    /// expensive poll off to ~1.2s instead of running it 3×/sec for no benefit.
    private var idlePollTicks = 0
    /// Set by the fast AX poll on a play-state transition to force the next AppleScript
    /// poll to run immediately (so resume refreshes position/track without backoff lag).
    private var forceFullPoll = false

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
    /// Timestamp the live `nextLineTimer` is scheduled for, so repeated calls with the same
    /// target don't tear down and rebuild the timer on every position tick.
    private var scheduledNextLineTimestamp: TimeInterval?
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

        // Supplementary Accessibility poll every 200ms for fast play/pause + like detection.
        // The full AX-tree traversal is comparatively expensive (many IPC calls), so it runs
        // on a background thread and at a lower rate than position interpolation needs.
        axPollTimer?.invalidate()
        axPollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
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
        scheduledNextLineTimestamp = nil
    }

    /// Fast supplementary poll using Accessibility APIs. The (relatively expensive) AX-tree
    /// traversal runs on a background thread so it never blocks SwiftUI rendering; results are
    /// applied back on the main actor.
    private func accessibilityPoll() {
        guard AccessibilityBridge.isAccessibilityEnabled, !isAXPolling else { return }
        isAXPolling = true
        let axBridge = accessibilityBridge
        Task.detached(priority: .userInitiated) { [weak self] in
            let info = axBridge.getPlaybackInfo()
            await self?.applyAXPoll(info)
        }
    }

    private func applyAXPoll(_ info: AccessibilityBridge.AXPlaybackInfo?) {
        isAXPolling = false
        guard let info else { return }

        // Guard every @Published assignment: `@Published` fires objectWillChange on *every*
        // set (even when the value is unchanged), so an unconditional assignment here would
        // rebuild the entire SwiftUI overlay several×/sec and make animations feel laggy.
        if isLiked != info.isLiked { isLiked = info.isLiked }

        let newState: AppleScriptBridge.PlayerState = info.isPlaying ? .playing : .paused
        if newState != playerState {
            playerState = newState
            // A state change (e.g. resume) should refresh the authoritative AppleScript read
            // promptly even if we're currently in idle backoff.
            forceFullPoll = true
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
        guard !isAppleScriptPolling else { return }

        // Idle backoff: while paused/stopped the position doesn't advance and the track
        // rarely changes, so the expensive AppleScript read can run far less often. The AX
        // poll flips `forceFullPoll` on resume so we never lag a real state change.
        if playerState != .playing && !forceFullPoll {
            idlePollTicks += 1
            if idlePollTicks < 4 { return }   // run ~every 1.2s while idle
        }
        idlePollTicks = 0
        forceFullPoll = false

        isAppleScriptPolling = true
        let bridge = self.bridge
        Task.detached(priority: .userInitiated) { [weak self] in
            let pollStart = CFAbsoluteTimeGetCurrent()
            let info = bridge.getPlaybackInfo()
            let pollEnd = CFAbsoluteTimeGetCurrent()
            await self?.applyPoll(info, pollStart: pollStart, pollEnd: pollEnd)
        }
    }

    private func applyPoll(_ info: AppleScriptBridge.PlaybackInfo?, pollStart: CFAbsoluteTime, pollEnd: CFAbsoluteTime) {
        isAppleScriptPolling = false

        guard let info else {
            if isSpotifyRunning { isSpotifyRunning = false }
            if currentTrack != nil { currentTrack = nil }
            if playerState != .stopped { playerState = .stopped }
            lastPolledPosition = 0
            lastTrackKey = nil
            driftOffset = 0
            return
        }

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

        // Only assign @Published properties when they actually change — see applyAXPoll().
        if !isSpotifyRunning { isSpotifyRunning = true }
        if playerState != info.state { playerState = info.state }
        if isShuffling != info.isShuffling { isShuffling = info.isShuffling }
        if isRepeating != info.isRepeating { isRepeating = info.isRepeating }
        lastPolledPosition = info.position
        lastPollTime = pollMid

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
        // The position timer calls this several×/sec with the same target; only (re)build the
        // timer when the target actually changes, otherwise we churn a Timer continuously.
        if scheduledNextLineTimestamp == nextLineTimestamp && nextLineTimer != nil { return }

        nextLineTimer?.invalidate()
        nextLineTimer = nil
        scheduledNextLineTimestamp = nil

        guard playerState == .playing else { return }

        let delay = nextLineTimestamp - playbackPosition
        guard delay > 0 && delay < 30 else { return }

        scheduledNextLineTimestamp = nextLineTimestamp
        nextLineTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.nextLineTimer = nil
                self.scheduledNextLineTimestamp = nil
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
        nextLineTimer = nil
        scheduledNextLineTimestamp = nil
    }

    public func playPause() {
        bridge.playPause()
        playerState = (playerState == .playing) ? .paused : .playing
        if playerState == .paused {
            nextLineTimer?.invalidate()
            nextLineTimer = nil
            scheduledNextLineTimestamp = nil
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
