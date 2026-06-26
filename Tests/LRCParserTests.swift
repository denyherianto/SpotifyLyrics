@testable import SpotifyLyricsCore


@MainActor
func testLRCParser() {
    print("--- LRC Parser Tests ---")

    // Basic parsing
    do {
        let lrc = """
        [00:12.50] Hello world
        [00:15.30] Second line
        [01:00.00] Third line
        """
        let lines = LRCParser.parse(lrc)
        checkEqual(lines.count, 3, "basic: count")
        checkEqual(lines[0].text, "Hello world", "basic: first text")
        checkApprox(lines[0].timestamp, 12.5)
        checkEqual(lines[1].text, "Second line", "basic: second text")
        checkApprox(lines[1].timestamp, 15.3)
        checkEqual(lines[2].text, "Third line", "basic: third text")
        checkApprox(lines[2].timestamp, 60.0)
        print("  ✓ Basic parsing")
    }

    // Three-digit milliseconds
    do {
        let lines = LRCParser.parse("[00:05.123] Precise timing")
        checkEqual(lines.count, 1, "3-digit ms: count")
        checkApprox(lines[0].timestamp, 5.123, accuracy: 0.001)
        checkEqual(lines[0].text, "Precise timing", "3-digit ms: text")
        print("  ✓ Three-digit milliseconds")
    }

    // Two-digit milliseconds
    do {
        let lines = LRCParser.parse("[00:05.12] Two digit ms")
        checkEqual(lines.count, 1, "2-digit ms: count")
        checkApprox(lines[0].timestamp, 5.12)
        print("  ✓ Two-digit milliseconds")
    }

    // Empty lines skipped
    do {
        let lrc = "[00:01.00] First\n\n[00:05.00] Second"
        let lines = LRCParser.parse(lrc)
        checkEqual(lines.count, 2, "empty lines: count")
        print("  ✓ Empty lines skipped")
    }

    // Empty text skipped
    do {
        let lrc = "[00:01.00]\n[00:05.00] Has text"
        let lines = LRCParser.parse(lrc)
        checkEqual(lines.count, 1, "empty text: count")
        checkEqual(lines[0].text, "Has text", "empty text: text")
        print("  ✓ Empty text skipped")
    }

    // Sorted by timestamp
    do {
        let lrc = "[01:00.00] Later line\n[00:10.00] Earlier line"
        let lines = LRCParser.parse(lrc)
        checkEqual(lines.count, 2, "sorted: count")
        checkEqual(lines[0].text, "Earlier line", "sorted: first")
        checkEqual(lines[1].text, "Later line", "sorted: second")
        print("  ✓ Sorted by timestamp")
    }

    // Empty input
    do {
        let lines = LRCParser.parse("")
        check(lines.isEmpty, "empty input should return empty array")
        print("  ✓ Empty input")
    }

    // No valid lines
    do {
        let lrc = "[ti:Song Title]\n[ar:Artist Name]\nJust plain text"
        let lines = LRCParser.parse(lrc)
        check(lines.isEmpty, "metadata-only should return empty array")
        print("  ✓ No valid lines")
    }

    // High timestamp
    do {
        let lines = LRCParser.parse("[05:30.00] Five minutes thirty")
        checkEqual(lines.count, 1, "high ts: count")
        checkApprox(lines[0].timestamp, 330.0)
        print("  ✓ High timestamp")
    }

    // Standard LRC has no per-word timings
    do {
        let lines = LRCParser.parse("[00:12.50] Hello world")
        check(lines[0].words == nil, "standard: no words")
        print("  ✓ Standard LRC has no word timings")
    }

    // Enhanced-LRC inline word timing
    do {
        let lines = LRCParser.parse("[00:10.00]<00:10.00>Hi <00:10.40>there")
        checkEqual(lines.count, 1, "enhanced: count")
        checkEqual(lines[0].text, "Hi there", "enhanced: text")
        checkApprox(lines[0].timestamp, 10.0)
        check(lines[0].words != nil, "enhanced: has words")
        checkEqual(lines[0].words?.count, 2, "enhanced: word count")
        if let words = lines[0].words {
            checkApprox(words[0].start, 10.0)
            checkApprox(words[0].end, 10.4)
            checkEqual(words[0].text.trimmingCharacters(in: .whitespaces), "Hi", "enhanced: word0 text")
            checkApprox(words[1].start, 10.4)
        }
        print("  ✓ Enhanced-LRC word timing")
    }
}
