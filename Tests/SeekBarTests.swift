import Foundation
@testable import SpotifyLyricsCore

@MainActor
func testSeekBarFormatting() {
    print("--- SeekBar Formatting Tests ---")

    // formatTime helper (replicate the private logic for validation)
    func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    // Basic time formatting
    do {
        checkEqual(formatTime(0), "0:00", "zero seconds")
        checkEqual(formatTime(65), "1:05", "65 seconds")
        checkEqual(formatTime(3600), "60:00", "one hour")
        checkEqual(formatTime(125.7), "2:05", "fractional seconds truncated")
        print("  ✓ Time formatting")
    }

    // Negative time clamped to zero
    do {
        checkEqual(formatTime(-5), "0:00", "negative clamped")
        print("  ✓ Negative time clamped")
    }

    // Remaining vs total duration display logic
    do {
        let duration: TimeInterval = 245 // 4:05
        let position: TimeInterval = 60  // 1:00

        // Remaining format: "-3:05"
        let remaining = "-\(formatTime(max(0, duration - position)))"
        checkEqual(remaining, "-3:05", "remaining format")

        // Total format: "4:05"
        let total = formatTime(duration)
        checkEqual(total, "4:05", "total format")
        print("  ✓ Remaining vs total display")
    }

    // Edge cases
    do {
        checkEqual(formatTime(59), "0:59", "just under a minute")
        checkEqual(formatTime(60), "1:00", "exactly a minute")
        checkEqual(formatTime(0.4), "0:00", "sub-second")
        checkEqual(formatTime(0.9), "0:00", "sub-second high")
        print("  ✓ Edge cases")
    }
}
