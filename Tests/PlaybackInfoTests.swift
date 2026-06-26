@testable import SpotifyLyricsCore


@MainActor
func testPlaybackInfo() {
    print("--- PlaybackInfo Tests ---")

    // Default values
    do {
        let track = TrackInfo(title: "Song", artist: "Artist", album: "Album", duration: 200)
        let info = AppleScriptBridge.PlaybackInfo(track: track, state: .playing, position: 42.0)
        check(info.artworkURLString == nil, "default artwork nil")
        checkEqual(info.isShuffling, false, "default shuffle off")
        checkEqual(info.isRepeating, false, "default repeat off")
        print("  ✓ Default values")
    }

    // Full construction
    do {
        let track = TrackInfo(title: "Song", artist: "Artist", album: "Album", duration: 200)
        let info = AppleScriptBridge.PlaybackInfo(
            track: track, state: .playing, position: 10.0,
            artworkURLString: "https://i.scdn.co/image/abc123",
            isShuffling: true, isRepeating: true
        )
        checkEqual(info.artworkURLString, "https://i.scdn.co/image/abc123", "artwork url")
        checkEqual(info.isShuffling, true, "shuffle on")
        checkEqual(info.isRepeating, true, "repeat on")
        checkApprox(info.position, 10.0)
        print("  ✓ Full construction")
    }

    // Player states
    do {
        let track = TrackInfo(title: "X", artist: "Y", album: "Z", duration: 100)
        let playing = AppleScriptBridge.PlaybackInfo(track: track, state: .playing, position: 0)
        let paused = AppleScriptBridge.PlaybackInfo(track: track, state: .paused, position: 0)
        let stopped = AppleScriptBridge.PlaybackInfo(track: track, state: .stopped, position: 0)
        let unknown = AppleScriptBridge.PlaybackInfo(track: track, state: .unknown, position: 0)

        checkEqual(playing.state.rawValue, "playing", "playing state")
        checkEqual(paused.state.rawValue, "paused", "paused state")
        checkEqual(stopped.state.rawValue, "stopped", "stopped state")
        checkEqual(unknown.state.rawValue, "unknown", "unknown state")
        print("  ✓ Player states")
    }

    // Nil artwork when empty string would be passed
    do {
        let track = TrackInfo(title: "Song", artist: "Artist", album: "Album", duration: 200)
        let info = AppleScriptBridge.PlaybackInfo(
            track: track, state: .playing, position: 5.0,
            artworkURLString: nil
        )
        check(info.artworkURLString == nil, "nil artwork preserved")
        print("  ✓ Nil artwork preserved")
    }

    // Empty artwork string
    do {
        let track = TrackInfo(title: "Song", artist: "Artist", album: "Album", duration: 200)
        let info = AppleScriptBridge.PlaybackInfo(
            track: track, state: .playing, position: 5.0,
            artworkURLString: ""
        )
        checkEqual(info.artworkURLString, "", "empty string artwork")
        print("  ✓ Empty string artwork")
    }
}
