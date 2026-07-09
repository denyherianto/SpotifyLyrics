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
}
