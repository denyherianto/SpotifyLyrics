@testable import SpotifyLyricsCore


@MainActor
func testModels() {
    print("--- Model Tests ---")

    // TrackInfo cache key
    do {
        let track = TrackInfo(title: "Hello World", artist: "Test Artist", album: "Album", duration: 180)
        checkEqual(track.cacheKey, "test artist|hello world", "cache key")
        print("  ✓ Cache key lowercase")
    }

    // Cache key consistency
    do {
        let track1 = TrackInfo(title: "HELLO", artist: "ARTIST", album: "A", duration: 100)
        let track2 = TrackInfo(title: "hello", artist: "artist", album: "B", duration: 200)
        checkEqual(track1.cacheKey, track2.cacheKey, "cache key case insensitive")
        print("  ✓ Cache key case insensitive")
    }

    // TrackInfo equality
    do {
        let track1 = TrackInfo(title: "Song", artist: "Artist", album: "Album", duration: 180)
        let track2 = TrackInfo(title: "Song", artist: "Artist", album: "Album", duration: 180)
        check(track1 == track2, "tracks should be equal")
        print("  ✓ TrackInfo equality")
    }

    // TrackInfo inequality
    do {
        let track1 = TrackInfo(title: "Song A", artist: "Artist", album: "Album", duration: 180)
        let track2 = TrackInfo(title: "Song B", artist: "Artist", album: "Album", duration: 180)
        check(track1 != track2, "tracks should not be equal")
        print("  ✓ TrackInfo inequality")
    }

    // LyricLine equality
    do {
        let line1 = LyricLine(timestamp: 5.0, text: "Hello")
        let line2 = LyricLine(timestamp: 5.0, text: "Hello")
        check(line1 == line2, "lines should be equal")
        print("  ✓ LyricLine equality")
    }

    // LyricLine inequality text
    do {
        let line1 = LyricLine(timestamp: 5.0, text: "Hello")
        let line2 = LyricLine(timestamp: 5.0, text: "World")
        check(line1 != line2, "lines should not be equal")
        print("  ✓ LyricLine inequality by text")
    }

    // LyricLine inequality timestamp
    do {
        let line1 = LyricLine(timestamp: 5.0, text: "Hello")
        let line2 = LyricLine(timestamp: 10.0, text: "Hello")
        check(line1 != line2, "lines should not be equal")
        print("  ✓ LyricLine inequality by timestamp")
    }

    // LyricLine unique IDs
    do {
        let line1 = LyricLine(timestamp: 5.0, text: "Hello")
        let line2 = LyricLine(timestamp: 5.0, text: "Hello")
        check(line1.id != line2.id, "IDs should be unique")
        print("  ✓ LyricLine unique IDs")
    }
}
