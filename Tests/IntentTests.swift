@testable import SpotifyLyricsCore


@MainActor
func testIntents() {
    print("--- Intent Tests ---")

    // OverlaySize raw value round-trip (used by OverlaySizeEnum)
    do {
        for size in OverlaySize.allCases {
            let restored = OverlaySize(rawValue: size.rawValue)
            checkEqual(restored, size, "OverlaySize round-trip: \(size)")
        }
        print("  ✓ OverlaySize raw value round-trip")
    }

    // AnimationMode raw value round-trip (used by AnimationModeEnum)
    do {
        for mode in AnimationMode.allCases {
            let restored = AnimationMode(rawValue: mode.rawValue)
            checkEqual(restored, mode, "AnimationMode round-trip: \(mode)")
        }
        print("  ✓ AnimationMode raw value round-trip")
    }

    // TranslationLanguage raw value round-trip (used by TranslationLanguageEnum)
    do {
        for lang in TranslationLanguage.allCases {
            let restored = TranslationLanguage(rawValue: lang.rawValue)
            checkEqual(restored, lang, "TranslationLanguage round-trip: \(lang)")
        }
        print("  ✓ TranslationLanguage raw value round-trip")
    }

    // CurrentSong result formatting
    do {
        let manager = LyricsManager()
        manager.currentLines = [
            LyricLine(timestamp: 0.0, text: "Hello world"),
            LyricLine(timestamp: 5.0, text: "Second line"),
        ]
        manager.updateCurrentLine(at: 0.0)
        check(manager.currentLineIndex < manager.currentLines.count, "Intent: line index valid")
        let line = manager.currentLines[manager.currentLineIndex]
        checkEqual(line.text, "Hello world", "Intent: correct current line text")
        print("  ✓ CurrentSong result formatting")
    }

    // Empty state handling
    do {
        let manager = LyricsManager()
        check(!manager.hasLyrics, "Intent: no lyrics by default")
        check(manager.currentLines.isEmpty, "Intent: empty lines by default")
        print("  ✓ Empty state handling")
    }

    // Line index stays in bounds after updateCurrentLine
    do {
        let manager = LyricsManager()
        manager.currentLines = [
            LyricLine(timestamp: 0.0, text: "First"),
            LyricLine(timestamp: 5.0, text: "Second"),
            LyricLine(timestamp: 10.0, text: "Third"),
        ]
        manager.updateCurrentLine(at: 7.0)
        check(manager.currentLineIndex < manager.currentLines.count, "Intent: index in bounds mid-song")
        checkEqual(manager.currentLines[manager.currentLineIndex].text, "Second", "Intent: correct line at 7s")
        print("  ✓ Line index tracks correctly")
    }

    // OverlaySize has all expected cases
    do {
        let cases = OverlaySize.allCases
        check(cases.count >= 4, "OverlaySize: at least 4 cases (mini, small, medium, large)")
        print("  ✓ OverlaySize has expected cases")
    }

    // AnimationMode has all expected cases
    do {
        let cases = AnimationMode.allCases
        check(cases.count >= 4, "AnimationMode: at least 4 cases")
        print("  ✓ AnimationMode has expected cases")
    }

    // TranslationLanguage has all expected cases
    do {
        let cases = TranslationLanguage.allCases
        check(cases.count >= 14, "TranslationLanguage: at least 14 languages")
        print("  ✓ TranslationLanguage has expected cases")
    }

    // hasLyrics reflects line population
    do {
        let manager = LyricsManager()
        check(!manager.hasLyrics, "hasLyrics: false initially")
        manager.currentLines = [LyricLine(timestamp: 0.0, text: "Test")]
        manager.hasLyrics = true
        check(manager.hasLyrics, "hasLyrics: true after setting lines")
        print("  ✓ hasLyrics reflects state")
    }
}
