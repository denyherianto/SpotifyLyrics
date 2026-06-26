@testable import SpotifyLyricsCore


@MainActor
func testOverlaySize() {
    print("--- OverlaySize Tests ---")

    // Mini dimensions
    do {
        let size = OverlaySize.mini
        let (w, h) = size.dimensions
        checkApprox(Double(w), 600.0, accuracy: 0.1)
        checkApprox(Double(h), 48.0, accuracy: 0.1)
        checkEqual(size.displayName, "Mini", "mini name")
        checkEqual(size.rawValue, "mini", "mini raw")
        check(size.isMini, "mini isMini")
        print("  ✓ Mini dimensions")
    }

    // Small dimensions
    do {
        let size = OverlaySize.small
        let (w, h) = size.dimensions
        checkApprox(Double(w), 500.0, accuracy: 0.1)
        checkApprox(Double(h), 200.0, accuracy: 0.1)
        checkEqual(size.displayName, "Small", "small name")
        checkEqual(size.rawValue, "small", "small raw")
        print("  ✓ Small dimensions")
    }

    // Medium dimensions
    do {
        let size = OverlaySize.medium
        let (w, h) = size.dimensions
        checkApprox(Double(w), 700.0, accuracy: 0.1)
        checkApprox(Double(h), 260.0, accuracy: 0.1)
        checkEqual(size.displayName, "Medium", "medium name")
        checkEqual(size.rawValue, "medium", "medium raw")
        print("  ✓ Medium dimensions")
    }

    // Large dimensions
    do {
        let size = OverlaySize.large
        let (w, h) = size.dimensions
        checkApprox(Double(w), 900.0, accuracy: 0.1)
        checkApprox(Double(h), 360.0, accuracy: 0.1)
        checkEqual(size.displayName, "Large", "large name")
        checkEqual(size.rawValue, "large", "large raw")
        print("  ✓ Large dimensions")
    }

    // All cases
    do {
        let all = OverlaySize.allCases
        checkEqual(all.count, 4, "allCases count")
        print("  ✓ All cases count")
    }

    // Raw value round-trip
    do {
        for size in OverlaySize.allCases {
            let restored = OverlaySize(rawValue: size.rawValue)
            check(restored != nil, "round-trip \(size.rawValue) not nil")
            check(restored == size, "round-trip \(size.rawValue) matches")
        }
        print("  ✓ Raw value round-trip")
    }

    // Invalid raw value
    do {
        let invalid = OverlaySize(rawValue: "huge")
        check(invalid == nil, "invalid raw value returns nil")
        print("  ✓ Invalid raw value")
    }
}
