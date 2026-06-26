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

    // Pre-call timestamp alignment: simulates that pollTime is captured BEFORE
    // the AppleScript call, so the interpolated position stays ahead rather than behind.
    do {
        let now = CFAbsoluteTimeGetCurrent()
        let manager = SpotifyPlayerManager()
        manager.playerState = .playing

        // Simulate correct behavior: pollTime captured before AppleScript (200ms ago)
        let preCallTime = now - 0.2
        manager.setInterpolationState(position: 50.0, pollTime: preCallTime)

        let correctPos = manager.playbackPosition

        // Simulate old buggy behavior: pollTime captured after AppleScript (now)
        manager.setInterpolationState(position: 50.0, pollTime: now)

        let buggyPos = manager.playbackPosition

        // The correct position should be ahead of the buggy one by ~200ms
        let diff = correctPos - buggyPos
        check(diff >= 0.15, "pre-call timestamp produces ahead position: diff=\(diff)")
        check(diff <= 0.25, "difference is roughly the IPC latency: diff=\(diff)")
        print("  ✓ Pre-call timestamp alignment reduces lag")
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
