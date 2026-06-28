@testable import SpotifyLyricsCore


@MainActor
func testInstrumentalBreak() {
    print("--- Instrumental Break Tests ---")

    // Break detected when gap > 8s and position past current line end
    do {
        let manager = LyricsManager()
        manager.currentLines = [
            LyricLine(timestamp: 0.0, text: "First line", endTime: 4.0),
            LyricLine(timestamp: 15.0, text: "After break"),
        ]
        manager.updateCurrentLine(at: 5.0)
        manager.updateInstrumentalBreak(at: 5.0)
        check(manager.isInstrumentalBreak, "break: detected with 11s gap")
        check(manager.instrumentalBreakCountdown > 0, "break: countdown positive")
        checkEqual(manager.nextVocalLineText, "After break", "break: next line text")
        print("  ✓ Break detected with large gap")
    }

    // No break when gap < threshold
    do {
        let manager = LyricsManager()
        manager.currentLines = [
            LyricLine(timestamp: 0.0, text: "First line", endTime: 4.0),
            LyricLine(timestamp: 10.0, text: "Close line"),
        ]
        manager.updateCurrentLine(at: 5.0)
        manager.updateInstrumentalBreak(at: 5.0)
        check(!manager.isInstrumentalBreak, "no break: gap < 8s")
        print("  ✓ No break with small gap")
    }

    // No break when gap exactly at threshold
    do {
        let manager = LyricsManager()
        manager.currentLines = [
            LyricLine(timestamp: 0.0, text: "First line", endTime: 2.0),
            LyricLine(timestamp: 10.0, text: "Next line"),
        ]
        manager.updateCurrentLine(at: 3.0)
        manager.updateInstrumentalBreak(at: 3.0)
        // gap = 10 - 2 = 8, exactly at threshold → should trigger
        check(manager.isInstrumentalBreak, "exact threshold: break detected")
        print("  ✓ Exact threshold triggers break")
    }

    // Break dismisses within lead time (1s before next line)
    do {
        let manager = LyricsManager()
        manager.currentLines = [
            LyricLine(timestamp: 0.0, text: "First line", endTime: 4.0),
            LyricLine(timestamp: 15.0, text: "After break"),
        ]
        manager.updateCurrentLine(at: 14.5)
        manager.updateInstrumentalBreak(at: 14.5)
        check(!manager.isInstrumentalBreak, "lead time: break dismissed")
        print("  ✓ Break dismissed within lead time")
    }

    // No break before current line ends
    do {
        let manager = LyricsManager()
        manager.currentLines = [
            LyricLine(timestamp: 0.0, text: "First line", endTime: 4.0),
            LyricLine(timestamp: 15.0, text: "After break"),
        ]
        manager.updateCurrentLine(at: 2.0)
        manager.updateInstrumentalBreak(at: 2.0)
        check(!manager.isInstrumentalBreak, "before end: no break yet")
        print("  ✓ No break before current line ends")
    }

    // No break on last line (no next line)
    do {
        let manager = LyricsManager()
        manager.currentLines = [
            LyricLine(timestamp: 0.0, text: "Only line"),
        ]
        manager.updateCurrentLine(at: 10.0)
        manager.updateInstrumentalBreak(at: 10.0)
        check(!manager.isInstrumentalBreak, "last line: no break")
        print("  ✓ No break on last line")
    }

    // Empty lines: no crash
    do {
        let manager = LyricsManager()
        manager.currentLines = []
        manager.updateInstrumentalBreak(at: 5.0)
        check(!manager.isInstrumentalBreak, "empty: no break")
        print("  ✓ Empty lines no crash")
    }

    // Countdown calculation accuracy
    do {
        let manager = LyricsManager()
        manager.currentLines = [
            LyricLine(timestamp: 0.0, text: "First", endTime: 4.0),
            LyricLine(timestamp: 20.0, text: "After long break"),
        ]
        manager.updateCurrentLine(at: 10.0)
        manager.updateInstrumentalBreak(at: 10.0)
        // countdown = nextTimestamp(20) - leadTime(1) - position(10) = 9
        checkApprox(manager.instrumentalBreakCountdown, 9.0, accuracy: 0.01)
        print("  ✓ Countdown calculation accurate")
    }

    // Break without explicit endTime uses next line start as current end
    do {
        let manager = LyricsManager()
        manager.currentLines = [
            LyricLine(timestamp: 0.0, text: "First"),
            LyricLine(timestamp: 20.0, text: "Way later"),
        ]
        // Without endTime, currentEnd = next line start = 20.0
        // gap = 20 - 20 = 0, so no break (the gap is effectively 0)
        manager.updateCurrentLine(at: 5.0)
        manager.updateInstrumentalBreak(at: 5.0)
        check(!manager.isInstrumentalBreak, "no endTime: gap is 0")
        print("  ✓ No endTime uses next line as end (no gap)")
    }

    // Break clears when moving to a non-break region
    do {
        let manager = LyricsManager()
        manager.currentLines = [
            LyricLine(timestamp: 0.0, text: "First", endTime: 4.0),
            LyricLine(timestamp: 15.0, text: "After break"),
            LyricLine(timestamp: 18.0, text: "Close next"),
        ]
        // Enter break
        manager.updateCurrentLine(at: 5.0)
        manager.updateInstrumentalBreak(at: 5.0)
        check(manager.isInstrumentalBreak, "transition: in break")

        // Move past break to line 1 (gap to line 2 is only 3s)
        manager.updateCurrentLine(at: 16.0)
        manager.updateInstrumentalBreak(at: 16.0)
        check(!manager.isInstrumentalBreak, "transition: break cleared")
        print("  ✓ Break clears on transition to non-break region")
    }

    // Threshold constant value
    do {
        checkApprox(LyricsManager.instrumentalBreakThreshold, 8.0, accuracy: 0.001)
        checkApprox(LyricsManager.breakDismissLeadTime, 1.0, accuracy: 0.001)
        print("  ✓ Threshold constants correct")
    }

    // Countdown decreases as position advances
    do {
        let manager = LyricsManager()
        manager.currentLines = [
            LyricLine(timestamp: 0.0, text: "First", endTime: 4.0),
            LyricLine(timestamp: 20.0, text: "After break"),
        ]
        manager.updateCurrentLine(at: 5.0)
        manager.updateInstrumentalBreak(at: 5.0)
        let countdown1 = manager.instrumentalBreakCountdown
        // countdown at 5.0 = 20 - 1 - 5 = 14

        manager.updateInstrumentalBreak(at: 10.0)
        let countdown2 = manager.instrumentalBreakCountdown
        // countdown at 10.0 = 20 - 1 - 10 = 9

        check(countdown1 > countdown2, "countdown: decreases with position")
        checkApprox(countdown1, 14.0, accuracy: 0.01)
        checkApprox(countdown2, 9.0, accuracy: 0.01)
        print("  ✓ Countdown decreases as position advances")
    }

    // Next vocal line text cleared when break ends
    do {
        let manager = LyricsManager()
        manager.currentLines = [
            LyricLine(timestamp: 0.0, text: "First", endTime: 4.0),
            LyricLine(timestamp: 15.0, text: "After break"),
            LyricLine(timestamp: 18.0, text: "Close next"),
        ]
        manager.updateCurrentLine(at: 5.0)
        manager.updateInstrumentalBreak(at: 5.0)
        checkEqual(manager.nextVocalLineText, "After break", "vocal text: set during break")

        // Move to non-break region
        manager.updateCurrentLine(at: 16.0)
        manager.updateInstrumentalBreak(at: 16.0)
        check(manager.nextVocalLineText == nil, "vocal text: cleared after break")
        print("  ✓ Next vocal line text lifecycle")
    }

    // Break with multiple consecutive breaks
    do {
        let manager = LyricsManager()
        manager.currentLines = [
            LyricLine(timestamp: 0.0, text: "Intro", endTime: 3.0),
            LyricLine(timestamp: 15.0, text: "Verse", endTime: 18.0),
            LyricLine(timestamp: 30.0, text: "Chorus"),
        ]
        // First break (gap = 15 - 3 = 12s)
        manager.updateCurrentLine(at: 4.0)
        manager.updateInstrumentalBreak(at: 4.0)
        check(manager.isInstrumentalBreak, "multi break: first detected")
        checkEqual(manager.nextVocalLineText, "Verse", "multi break: first next line")

        // Second break (gap = 30 - 18 = 12s)
        manager.updateCurrentLine(at: 19.0)
        manager.updateInstrumentalBreak(at: 19.0)
        check(manager.isInstrumentalBreak, "multi break: second detected")
        checkEqual(manager.nextVocalLineText, "Chorus", "multi break: second next line")
        print("  ✓ Multiple consecutive breaks")
    }

    // Default endTime fallback (timestamp + 5) on last line
    do {
        let manager = LyricsManager()
        manager.currentLines = [
            LyricLine(timestamp: 0.0, text: "Only line"),
        ]
        manager.updateCurrentLine(at: 6.0)
        manager.updateInstrumentalBreak(at: 6.0)
        // Last line with no next → no break (guard returns early)
        check(!manager.isInstrumentalBreak, "fallback endTime: no break on single line")
        print("  ✓ Default endTime fallback on last line")
    }
}
