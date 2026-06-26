@testable import SpotifyLyricsCore
import Foundation

@MainActor
func testPlaybackInterpolation() {
    print("--- Playback Interpolation Tests ---")

    // Interpolation advances position when playing
    do {
        let manager = SpotifyPlayerManager()
        // Simulate a poll: set state to playing and seed position
        manager.playerState = .playing
        manager.setInterpolationState(position: 10.0, pollTime: CFAbsoluteTimeGetCurrent() - 0.2)

        // Position should have advanced by ~0.2s
        let pos = manager.playbackPosition
        check(pos >= 10.15, "interpolation advances: got \(pos)")
        check(pos <= 10.35, "interpolation not too far: got \(pos)")
        print("  ✓ Interpolation advances position when playing")
    }

    // Position freezes when paused
    do {
        let manager = SpotifyPlayerManager()
        manager.playerState = .paused
        manager.setInterpolationState(position: 30.0, pollTime: CFAbsoluteTimeGetCurrent() - 1.0)

        let pos = manager.playbackPosition
        checkApprox(pos, 30.0, accuracy: 0.001)
        print("  ✓ Position freezes when paused")
    }

    // Position freezes when stopped
    do {
        let manager = SpotifyPlayerManager()
        manager.playerState = .stopped
        manager.setInterpolationState(position: 0.0, pollTime: CFAbsoluteTimeGetCurrent() - 5.0)

        let pos = manager.playbackPosition
        checkApprox(pos, 0.0, accuracy: 0.001)
        print("  ✓ Position freezes when stopped")
    }

    // Midpoint timestamp alignment: pollTime is the midpoint between call start
    // and end, minimizing interpolation error in both directions.
    do {
        let now = CFAbsoluteTimeGetCurrent()
        let manager = SpotifyPlayerManager()
        manager.playerState = .playing

        // Simulate midpoint behavior: 200ms call, midpoint is 100ms ago
        let midpointTime = now - 0.1
        manager.setInterpolationState(position: 50.0, pollTime: midpointTime)
        let midPos = manager.playbackPosition

        // Simulate pre-call (200ms ago) — would overshoot
        manager.setInterpolationState(position: 50.0, pollTime: now - 0.2)
        let prePos = manager.playbackPosition

        // Simulate post-call (now) — would undershoot
        manager.setInterpolationState(position: 50.0, pollTime: now)
        let postPos = manager.playbackPosition

        // Midpoint should be between pre-call and post-call
        check(midPos < prePos, "midpoint < pre-call: \(midPos) < \(prePos)")
        check(midPos > postPos, "midpoint > post-call: \(midPos) > \(postPos)")
        // Midpoint error is ~half the IPC latency (~100ms), not the full amount
        let midError = midPos - 50.0
        check(midError >= 0.05, "midpoint offset is reasonable: \(midError)")
        check(midError <= 0.15, "midpoint offset not too large: \(midError)")
        print("  ✓ Midpoint timestamp alignment minimizes sync error")
    }

    // seekTo resets interpolation baseline
    do {
        let manager = SpotifyPlayerManager()
        manager.playerState = .playing
        manager.setInterpolationState(position: 10.0, pollTime: CFAbsoluteTimeGetCurrent() - 5.0)

        // Before seek, position is way ahead
        let before = manager.playbackPosition
        check(before > 14.0, "position advanced significantly before seek")

        // After seek, position resets to near the seek target
        manager.seekTo(60.0)
        let after = manager.playbackPosition
        check(after >= 60.0, "position at seek target: got \(after)")
        check(after < 60.1, "position not far from seek target: got \(after)")
        print("  ✓ seekTo resets interpolation baseline")
    }
}
