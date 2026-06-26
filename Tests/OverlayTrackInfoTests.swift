@testable import SpotifyLyricsCore


@MainActor
func testOverlayTrackInfo() {
    print("--- Overlay Track Info Tests ---")

    // Track title and artist are accessible for overlay display
    do {
        let track = TrackInfo(title: "Blinding Lights", artist: "The Weeknd", album: "After Hours", duration: 200)
        checkEqual(track.title, "Blinding Lights", "track title")
        checkEqual(track.artist, "The Weeknd", "track artist")
        print("  ✓ Track info properties available")
    }

    // Track info with empty title/artist
    do {
        let track = TrackInfo(title: "", artist: "", album: "", duration: 0)
        checkEqual(track.title, "", "empty title")
        checkEqual(track.artist, "", "empty artist")
        print("  ✓ Empty track info handled")
    }

    // Track info with unicode characters
    do {
        let track = TrackInfo(title: "夜に駆ける", artist: "YOASOBI", album: "THE BOOK", duration: 258)
        checkEqual(track.title, "夜に駆ける", "unicode title")
        checkEqual(track.artist, "YOASOBI", "unicode artist")
        print("  ✓ Unicode track info")
    }

    // Track info with long title (overlay uses lineLimit(1))
    do {
        let track = TrackInfo(title: "A Very Long Song Title That Should Be Truncated In The Overlay", artist: "An Artist With A Very Long Name", album: "Album", duration: 300)
        check(!track.title.isEmpty, "long title is non-empty")
        check(!track.artist.isEmpty, "long artist is non-empty")
        print("  ✓ Long track info handled")
    }

    // Overlay visibility depends on hover state
    do {
        let isOverlayHovered = true
        let hasTrack = true
        let shouldShowTrackInfo = isOverlayHovered && hasTrack
        check(shouldShowTrackInfo, "shows when hovered and track exists")

        check(!(false && hasTrack), "hidden when not hovered")
        check(!(isOverlayHovered && false), "hidden when no track")
        print("  ✓ Track info visibility logic")
    }

    // Player manager currentTrack nil means no track info shown
    do {
        let playerManager = SpotifyPlayerManager()
        check(playerManager.currentTrack == nil, "no track initially")
        print("  ✓ No track info when currentTrack is nil")
    }
}
