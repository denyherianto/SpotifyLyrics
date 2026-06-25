import Foundation
import Combine

@MainActor
public final class SpotifyPlayerManager: ObservableObject {
    @Published public var currentTrack: TrackInfo?
    @Published public var playerState: AppleScriptBridge.PlayerState = .stopped
    @Published public var isSpotifyRunning = false

    private let bridge = AppleScriptBridge()
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

    private func poll() {
        // Single AppleScript call that also detects if Spotify is not running
        guard let info = bridge.getPlaybackInfo() else {
            isSpotifyRunning = false
            currentTrack = nil
            playerState = .stopped
            lastPolledPosition = 0
            lastTrackKey = nil
            return
        }

        isSpotifyRunning = true
        playerState = info.state
        lastPolledPosition = info.position
        lastPollTime = CFAbsoluteTimeGetCurrent()

        let newKey = info.track.cacheKey
        if newKey != lastTrackKey && !info.track.title.isEmpty {
            lastTrackKey = newKey
            currentTrack = info.track
            onTrackChanged?(info.track)
        }
    }

    public func seekTo(_ position: TimeInterval) {
        bridge.seekTo(position)
        lastPolledPosition = position
        lastPollTime = CFAbsoluteTimeGetCurrent()
    }

    deinit {
        pollTimer?.invalidate()
    }
}
