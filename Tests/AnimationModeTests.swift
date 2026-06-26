import Foundation
@testable import SpotifyLyricsCore


@MainActor
func testAnimationMode() {
    print("--- Animation Mode Tests ---")

    // Enum round-trip via UserDefaults (mirrors OverlaySize)
    do {
        let defaults = UserDefaults.standard
        let key = "test_animationMode"
        for mode in AnimationMode.allCases {
            defaults.set(mode.rawValue, forKey: key)
            let restored = defaults.string(forKey: key).flatMap { AnimationMode(rawValue: $0) }
            checkEqual(restored, mode, "animationMode persistence \(mode.rawValue)")
        }
        defaults.removeObject(forKey: key)
        checkEqual(AnimationMode.allCases.count, 4, "four animation modes")
        print("  ✓ AnimationMode UserDefaults round-trip")
    }

    // Display names non-empty and unique
    do {
        let names = AnimationMode.allCases.map { $0.displayName }
        check(names.allSatisfy { !$0.isEmpty }, "display names non-empty")
        checkEqual(Set(names).count, names.count, "display names unique")
        print("  ✓ Display names")
    }

    // fillFraction: line interpolation (no word timings)
    do {
        let line = LyricLine(timestamp: 10.0, text: "test line")
        checkApprox(line.fillFraction(at: 10.0, lineEnd: 14.0), 0.0)
        checkApprox(line.fillFraction(at: 12.0, lineEnd: 14.0), 0.5)
        checkApprox(line.fillFraction(at: 14.0, lineEnd: 14.0), 1.0)
        checkApprox(line.fillFraction(at: 9.0, lineEnd: 14.0), 0.0)   // before start clamps
        checkApprox(line.fillFraction(at: 20.0, lineEnd: 14.0), 1.0)  // after end clamps
        print("  ✓ Line-interpolated fill fraction")
    }

    // fillFraction: word-level
    do {
        let words = [
            LyricWord(text: "AB", start: 10.0, end: 11.0),
            LyricWord(text: "CD", start: 11.0, end: 12.0)
        ]
        let line = LyricLine(timestamp: 10.0, text: "ABCD", words: words, endTime: 12.0)
        checkApprox(line.fillFraction(at: 10.0, lineEnd: 12.0), 0.0)
        checkApprox(line.fillFraction(at: 11.0, lineEnd: 12.0), 0.5)  // first word complete
        checkApprox(line.fillFraction(at: 11.5, lineEnd: 12.0), 0.75) // half through second word
        checkApprox(line.fillFraction(at: 12.0, lineEnd: 12.0), 1.0)
        print("  ✓ Word-level fill fraction")
    }
}
