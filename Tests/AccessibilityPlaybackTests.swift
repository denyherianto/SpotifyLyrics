import Foundation
@testable import SpotifyLyricsCore

@MainActor
func testAccessibilityPlaybackStateDoesNotOverwriteWhenUnknown() {
    print("--- Accessibility Playback Tests ---")

    let manager = SpotifyPlayerManager()
    manager.playerState = .playing
    manager.setInterpolationState(position: 42.0, pollTime: CFAbsoluteTimeGetCurrent())

    manager.applyAXPoll(AccessibilityBridge.AXPlaybackInfo(
        title: "Track",
        artist: "Artist",
        isPlaying: nil,
        progress: nil,
        isLiked: false
    ))

    checkEqual(manager.playerState, .playing, "AX unknown state preserves authoritative player state")
}

@MainActor
func testAccessibilityProgressDoesNotMovePlaybackClock() {
    let manager = SpotifyPlayerManager()
    manager.currentTrack = TrackInfo(title: "Track", artist: "Artist", album: "Album", duration: 200)
    manager.playerState = .playing
    manager.setInterpolationState(position: 50.0, pollTime: CFAbsoluteTimeGetCurrent())

    manager.applyAXPoll(AccessibilityBridge.AXPlaybackInfo(
        title: "Track",
        artist: "Artist",
        isPlaying: true,
        progress: 0.27,
        isLiked: false
    ))

    checkApprox(manager.playbackPosition, 50.0, accuracy: 0.1)
}

func testAccessibilityButtonStateInference() {
    checkEqual(AccessibilityBridge.inferPlaybackState(buttonDescription: "Pause", title: nil), true, "AX pause button means playing")
    checkEqual(AccessibilityBridge.inferPlaybackState(buttonDescription: "Play", title: nil), false, "AX play button means paused")
    check(AccessibilityBridge.inferPlaybackState(buttonDescription: "Playlists", title: nil) == nil, "AX unrelated play text is unknown")
}
