@testable import SpotifyLyricsCore

@MainActor
func testParseNumber() {
    print("--- Parse Number Tests ---")

    checkApprox(AppleScriptBridge.parseNumber("120.5"), 120.5, accuracy: 0.001)
    print("  ✓ Period decimal separator")

    checkApprox(AppleScriptBridge.parseNumber("120,5"), 120.5, accuracy: 0.001)
    print("  ✓ Comma decimal separator")

    checkApprox(AppleScriptBridge.parseNumber("60"), 60.0, accuracy: 0.001)
    print("  ✓ Integer value")

    checkApprox(AppleScriptBridge.parseNumber("0"), 0.0, accuracy: 0.001)
    print("  ✓ Zero")

    checkApprox(AppleScriptBridge.parseNumber("  42.5  "), 42.5, accuracy: 0.001)
    print("  ✓ Whitespace trimmed")

    checkApprox(AppleScriptBridge.parseNumber("  120,456  "), 120.456, accuracy: 0.001)
    print("  ✓ Comma with whitespace")

    checkApprox(AppleScriptBridge.parseNumber("abc"), 0.0, accuracy: 0.001)
    print("  ✓ Invalid returns zero")

    checkApprox(AppleScriptBridge.parseNumber(""), 0.0, accuracy: 0.001)
    print("  ✓ Empty returns zero")

    checkApprox(AppleScriptBridge.parseNumber("3600,123"), 3600.123, accuracy: 0.001)
    print("  ✓ Large number with comma")
}
