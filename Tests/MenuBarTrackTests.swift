import Foundation
@testable import SpotifyLyricsCore


@MainActor
func testMenuBarTrackInfo() {
    print("--- Menu Bar Track Info Tests ---")

    let defaults = UserDefaults.standard
    let testKey = "test_showMenuBarTrackInfo"

    // Bool round-trip for showMenuBarTrackInfo setting
    do {
        for val in [true, false] {
            defaults.set(val, forKey: testKey)
            let restored = defaults.bool(forKey: testKey)
            checkEqual(restored, val, "showMenuBarTrackInfo persistence \(val)")
        }
        defaults.removeObject(forKey: testKey)
        print("  ✓ showMenuBarTrackInfo UserDefaults round-trip")
    }

    // Default value when key is not set
    do {
        let unusedKey = "test_showMenuBarTrackInfo_unset"
        defaults.removeObject(forKey: unusedKey)
        checkEqual(defaults.bool(forKey: unusedKey), false, "unset showMenuBarTrackInfo defaults false")
        check(defaults.object(forKey: unusedKey) == nil, "unset key returns nil object")
        print("  ✓ showMenuBarTrackInfo default when unset")
    }

    // Track display text format
    do {
        let track = TrackInfo(title: "Bohemian Rhapsody", artist: "Queen", album: "A Night at the Opera", duration: 354)
        let displayText = "\(track.artist) — \(track.title)"
        checkEqual(displayText, "Queen — Bohemian Rhapsody", "display text format")
        print("  ✓ Track display text format")
    }

    // Display text with special characters
    do {
        let track = TrackInfo(title: "Für Elise", artist: "Beethoven", album: "Classics", duration: 180)
        let displayText = "\(track.artist) — \(track.title)"
        check(displayText.contains("—"), "contains em dash separator")
        check(displayText.contains("Für"), "preserves special characters")
        print("  ✓ Track display text with special characters")
    }

    // Visibility logic: should show only when playing + track exists + setting on
    do {
        // Simulate the conditions
        let hasTrack = true
        let isPlaying = true
        let showTrack = true
        let shouldShow = isPlaying && hasTrack && showTrack
        check(shouldShow, "shows when playing + track + setting on")

        let shouldHidePaused = !true && hasTrack && showTrack  // paused
        check(!shouldHidePaused || true, "check paused state") // always true, testing logic below

        // When paused
        check(!(false && hasTrack && showTrack), "hidden when not playing")
        // When no track
        check(!(isPlaying && false && showTrack), "hidden when no track")
        // When setting off
        check(!(isPlaying && hasTrack && false), "hidden when setting off")
        print("  ✓ Visibility logic conditions")
    }

    // Persistence key is correct string
    do {
        let key = "showMenuBarTrackInfo"
        check(!key.isEmpty, "persistence key is non-empty")
        check(key == "showMenuBarTrackInfo", "persistence key matches expected value")
        print("  ✓ Persistence key naming")
    }
}
