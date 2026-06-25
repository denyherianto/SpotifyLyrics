@testable import SpotifyLyricsCore

@MainActor
func testLyricsManager() {
    print("--- Lyrics Manager Tests ---")

    // Update at start
    do {
        let manager = LyricsManager()
        manager.currentLines = [
            LyricLine(timestamp: 0.0, text: "First"),
            LyricLine(timestamp: 5.0, text: "Second"),
            LyricLine(timestamp: 10.0, text: "Third"),
        ]
        manager.updateCurrentLine(at: 0.0)
        checkEqual(manager.currentLineIndex, 0, "at start: index")
        print("  ✓ Update at start")
    }

    // Mid-song
    do {
        let manager = LyricsManager()
        manager.currentLines = [
            LyricLine(timestamp: 0.0, text: "First"),
            LyricLine(timestamp: 5.0, text: "Second"),
            LyricLine(timestamp: 10.0, text: "Third"),
            LyricLine(timestamp: 15.0, text: "Fourth"),
        ]

        manager.updateCurrentLine(at: 7.0)
        checkEqual(manager.currentLineIndex, 1, "mid: at 7s")

        manager.updateCurrentLine(at: 10.0)
        checkEqual(manager.currentLineIndex, 2, "mid: at 10s exact")

        manager.updateCurrentLine(at: 14.9)
        checkEqual(manager.currentLineIndex, 2, "mid: at 14.9s")

        manager.updateCurrentLine(at: 15.0)
        checkEqual(manager.currentLineIndex, 3, "mid: at 15s")
        print("  ✓ Update mid-song")
    }

    // Past end
    do {
        let manager = LyricsManager()
        manager.currentLines = [
            LyricLine(timestamp: 0.0, text: "First"),
            LyricLine(timestamp: 5.0, text: "Second"),
        ]
        manager.updateCurrentLine(at: 999.0)
        checkEqual(manager.currentLineIndex, 1, "past end: last line")
        print("  ✓ Past end stays on last line")
    }

    // Before first line
    do {
        let manager = LyricsManager()
        manager.currentLines = [
            LyricLine(timestamp: 5.0, text: "First"),
            LyricLine(timestamp: 10.0, text: "Second"),
        ]
        manager.updateCurrentLine(at: 2.0)
        checkEqual(manager.currentLineIndex, 0, "before first: stays 0")
        print("  ✓ Before first line")
    }

    // Empty lines
    do {
        let manager = LyricsManager()
        manager.currentLines = []
        manager.updateCurrentLine(at: 5.0)
        checkEqual(manager.currentLineIndex, 0, "empty: stays 0")
        print("  ✓ Empty lines no crash")
    }

    // No change keeps index
    do {
        let manager = LyricsManager()
        manager.currentLines = [
            LyricLine(timestamp: 0.0, text: "First"),
            LyricLine(timestamp: 10.0, text: "Second"),
        ]
        manager.updateCurrentLine(at: 1.0)
        checkEqual(manager.currentLineIndex, 0, "no change: first call")
        manager.updateCurrentLine(at: 3.0)
        checkEqual(manager.currentLineIndex, 0, "no change: second call")
        print("  ✓ No change keeps index")
    }
}
