import CoreGraphics
@testable import SpotifyLyricsCore

func testSummaryMarqueeMetrics() {
    print("--- Summary Marquee Tests ---")

    do {
        let metrics = SummaryMarqueeMetrics(containerWidth: 240, contentWidth: 180)
        check(!metrics.shouldScroll, "summary: fitting text does not scroll")
        checkEqual(metrics.scrollDistance, 0, "summary: fitting text has no travel")
        checkEqual(metrics.duration, 0, "summary: fitting text has no animation duration")
        print("  ✓ Fitting summary remains still")
    }

    do {
        let metrics = SummaryMarqueeMetrics(containerWidth: 240, contentWidth: 360)
        check(metrics.shouldScroll, "summary: overflowing text scrolls")
        checkEqual(metrics.scrollDistance, 120, "summary: travels by overflow width")
        check(metrics.duration >= SummaryMarqueeMetrics.minimumDuration, "summary: duration has readable minimum")
        print("  ✓ Overflowing summary scrolls through hidden text")
    }

    do {
        let metrics = SummaryMarqueeMetrics(containerWidth: 240, contentWidth: 241)
        check(!metrics.shouldScroll, "summary: ignores sub-pixel measurement jitter")
        print("  ✓ Measurement jitter is ignored")
    }
}
