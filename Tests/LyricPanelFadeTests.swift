import CoreGraphics
@testable import SpotifyLyricsCore

func testLyricPanelFadeStops() {
    print("--- Lyric Panel Fade Tests ---")

    let stops = LyricPanelFadeStops()

    checkEqual(stops.topClear, 0, "fade: starts transparent at top edge")
    check(stops.topOpaque > stops.topClear, "fade: top ramps into visible content")
    check(stops.bottomOpaque > stops.topOpaque, "fade: center remains visible")
    checkEqual(stops.bottomClear, 1, "fade: ends transparent at bottom edge")
    checkApprox(Double(stops.topOpaque), Double(1 - stops.bottomOpaque), accuracy: 0.001)

    print("  ✓ Top and bottom fade stops are symmetrical")
}
