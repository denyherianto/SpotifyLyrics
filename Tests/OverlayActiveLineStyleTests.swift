@testable import SpotifyLyricsCore

func testOverlayActiveLineStyle() {
    print("--- Overlay Active Line Style Tests ---")

    do {
        checkApprox(LyricLineVisualStyle.mainTextOpacity(isActive: true), 1.0, accuracy: 0.001)
        checkApprox(LyricLineVisualStyle.enrichmentOpacity(isActive: true), 1.0, accuracy: 0.001)
        print("  ✓ Active line text is fully white")
    }

    do {
        check(LyricLineVisualStyle.mainTextOpacity(isActive: false) < 1.0, "inactive main text remains dimmed")
        check(LyricLineVisualStyle.enrichmentOpacity(isActive: false) < 1.0, "inactive enrichment remains dimmed")
        print("  ✓ Inactive line text remains dimmed")
    }

    do {
        checkApprox(LyricLineVisualStyle.scale(isActive: true, mode: .karaoke), 1.22, accuracy: 0.001)
        check(LyricLineVisualStyle.scale(isActive: true, mode: .karaoke) > LyricLineVisualStyle.scale(isActive: false, mode: .karaoke), "active line scale is larger")
        check(LyricLineVisualStyle.scale(isActive: true, mode: .smooth) > LyricLineVisualStyle.scale(isActive: false, mode: .smooth), "active smooth line scale is larger")
        print("  ✓ Active line scale is larger")
    }

    do {
        check(LyricLineVisualStyle.isLineActive(index: 2, activeIndex: 2, isInstrumentalBreak: false), "matching line is active outside instrumental break")
        check(!LyricLineVisualStyle.isLineActive(index: 2, activeIndex: 2, isInstrumentalBreak: true), "instrumental break suppresses active line")
        print("  ✓ Instrumental break suppresses active line styling")
    }

    do {
        check(LyricLineVisualStyle.showsInlineInstrumentalBreak(index: 2, activeIndex: 2, isInstrumentalBreak: true), "instrumental break appears in current lyric row")
        check(!LyricLineVisualStyle.showsInlineInstrumentalBreak(index: 1, activeIndex: 2, isInstrumentalBreak: true), "instrumental break does not appear in other rows")
        check(!LyricLineVisualStyle.showsInlineInstrumentalBreak(index: 2, activeIndex: 2, isInstrumentalBreak: false), "instrumental break row is hidden outside breaks")
        check(LyricLineVisualStyle.showsLyricLine(index: 2, activeIndex: 2, isInstrumentalBreak: true), "instrumental break keeps the current lyric row visible")
        print("  ✓ Instrumental break renders after the current lyric row")
    }

    do {
        checkEqual(LyricLineVisualStyle.instrumentalCountdownText(seconds: 5), "-00:05", "instrumental countdown: seconds")
        checkEqual(LyricLineVisualStyle.instrumentalCountdownText(seconds: 64.2), "-01:05", "instrumental countdown: rounds up")
        checkEqual(LyricLineVisualStyle.instrumentalCountdownText(seconds: 0), "", "instrumental countdown: hidden at zero")
        print("  ✓ Instrumental countdown uses -mm:ss")
    }
}
