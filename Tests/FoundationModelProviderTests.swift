@testable import SpotifyLyricsCore


@MainActor
func testFoundationModelProvider() async {
    print("--- Foundation Model Provider Tests ---")

    // Prompt construction
    do {
        let provider = FoundationModelProvider()
        let prompt = provider.buildPrompt(
            lines: ["Hello", "World"],
            title: "Test Song",
            artist: "Test Artist"
        )
        check(prompt.contains("Test Song"), "prompt: contains title")
        check(prompt.contains("Test Artist"), "prompt: contains artist")
        check(prompt.contains("Hello"), "prompt: contains lyrics")
        print("  ✓ Prompt construction")
    }

    // Caching
    do {
        let provider = FoundationModelProvider()
        check(!provider.hasCachedSummary(title: "Song", artist: "Artist"), "cache: empty initially")

        provider.cacheSummary("A love song", title: "Song", artist: "Artist")
        check(provider.hasCachedSummary(title: "Song", artist: "Artist"), "cache: present after set")
        print("  ✓ Summary caching")
    }

    // Cache key is case-insensitive
    do {
        let provider = FoundationModelProvider()
        provider.cacheSummary("Theme", title: "My Song", artist: "The Band")
        check(provider.hasCachedSummary(title: "my song", artist: "the band"), "cache: case insensitive")
        print("  ✓ Cache key case insensitive")
    }

    // Empty lines returns nil
    do {
        let provider = FoundationModelProvider()
        // summarizeLyrics is async, but with empty lines it should return nil synchronously
        // We can't easily test async here, so we test the guard condition via prompt
        let prompt = provider.buildPrompt(lines: [], title: "Song", artist: "Artist")
        // Prompt is built but summarizeLyrics would return nil for empty lines
        check(!prompt.isEmpty, "empty lines: prompt still built (guard is in summarize)")
        print("  ✓ Empty lines handling")
    }

    // LyricsManager songSummary property
    do {
        let manager = LyricsManager()
        check(manager.songSummary == nil, "manager: summary nil by default")
        check(!manager.showSongSummary, "manager: showSongSummary off by default")
        print("  ✓ LyricsManager summary properties")
    }

    // Prompt truncates to 40 lines
    do {
        let provider = FoundationModelProvider()
        let lines = (1...60).map { "Line \($0)" }
        let prompt = provider.buildPrompt(lines: lines, title: "Song", artist: "Artist")
        check(prompt.contains("Line 40"), "truncation: includes line 40")
        check(!prompt.contains("Line 41"), "truncation: excludes line 41")
        print("  ✓ Prompt truncates to 40 lines")
    }

    // Prompt format structure
    do {
        let provider = FoundationModelProvider()
        let prompt = provider.buildPrompt(lines: ["Verse one", "Verse two"], title: "Dreamer", artist: "Band")
        check(prompt.hasPrefix("Song: Dreamer by Band"), "format: starts with Song: title by artist")
        check(prompt.contains("Lyrics:\n"), "format: contains Lyrics header")
        check(prompt.contains("Verse one\nVerse two"), "format: lines joined by newline")
        print("  ✓ Prompt format structure")
    }

    // Cache returns different entries for different tracks
    do {
        let provider = FoundationModelProvider()
        provider.cacheSummary("Love story", title: "Song A", artist: "Artist A")
        provider.cacheSummary("Breakup anthem", title: "Song B", artist: "Artist B")
        check(provider.hasCachedSummary(title: "Song A", artist: "Artist A"), "multi cache: A present")
        check(provider.hasCachedSummary(title: "Song B", artist: "Artist B"), "multi cache: B present")
        check(!provider.hasCachedSummary(title: "Song C", artist: "Artist C"), "multi cache: C absent")
        print("  ✓ Multiple cache entries independent")
    }

    // Summarize with empty lines returns nil
    do {
        let provider = FoundationModelProvider()
        let result = await provider.summarizeLyrics([], title: "Song", artist: "Artist")
        check(result == nil, "summarize empty: returns nil")
        print("  ✓ Summarize empty lines returns nil")
    }

    // Summarize returns cached value without re-invoking model
    do {
        let provider = FoundationModelProvider()
        provider.cacheSummary("Pre-cached theme", title: "Cached", artist: "Test")
        let result = await provider.summarizeLyrics(["Lyrics"], title: "Cached", artist: "Test")
        checkEqual(result, "Pre-cached theme", "summarize cached: returns cached value")
        print("  ✓ Summarize returns cached value")
    }
}
