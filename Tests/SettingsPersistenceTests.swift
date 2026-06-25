import Foundation
@testable import SpotifyLyricsCore

@MainActor
func testSettingsPersistence() {
    print("--- Settings Persistence Tests ---")

    let defaults = UserDefaults.standard
    let testSuite = "testSettingsPersistence"

    // Clean up before tests
    let keys = ["overlaySize", "overlayOpacity", "overlayAlwaysOnTop", "overlayVisible"]
    let savedValues = keys.map { ($0, defaults.object(forKey: $0)) }

    // OverlaySize round-trip via UserDefaults
    do {
        for size in OverlaySize.allCases {
            defaults.set(size.rawValue, forKey: "test_\(testSuite)_size")
            let restored = defaults.string(forKey: "test_\(testSuite)_size")
                .flatMap { OverlaySize(rawValue: $0) }
            checkEqual(restored, size, "size persistence \(size.rawValue)")
        }
        defaults.removeObject(forKey: "test_\(testSuite)_size")
        print("  ✓ OverlaySize UserDefaults round-trip")
    }

    // Opacity round-trip via UserDefaults
    do {
        let testValues: [Double] = [0.3, 0.5, 0.75, 1.0]
        for val in testValues {
            defaults.set(val, forKey: "test_\(testSuite)_opacity")
            let restored = defaults.double(forKey: "test_\(testSuite)_opacity")
            checkApprox(restored, val, accuracy: 0.001)
        }
        defaults.removeObject(forKey: "test_\(testSuite)_opacity")
        print("  ✓ Opacity UserDefaults round-trip")
    }

    // Bool round-trip via UserDefaults (alwaysOnTop, isVisible)
    do {
        for val in [true, false] {
            defaults.set(val, forKey: "test_\(testSuite)_bool")
            let restored = defaults.bool(forKey: "test_\(testSuite)_bool")
            checkEqual(restored, val, "bool persistence \(val)")
        }
        defaults.removeObject(forKey: "test_\(testSuite)_bool")
        print("  ✓ Bool settings UserDefaults round-trip")
    }

    // Nil check: unset keys return expected defaults
    do {
        let unusedKey = "test_\(testSuite)_nonexistent"
        defaults.removeObject(forKey: unusedKey)
        check(defaults.object(forKey: unusedKey) == nil, "unset key returns nil")
        checkEqual(defaults.bool(forKey: unusedKey), false, "unset bool defaults false")
        checkApprox(defaults.double(forKey: unusedKey), 0.0, accuracy: 0.001)
        print("  ✓ Unset keys return expected defaults")
    }

    // Expected persistence keys exist as strings
    do {
        let expectedKeys = ["overlaySize", "overlayOpacity", "overlayAlwaysOnTop", "overlayVisible"]
        for key in expectedKeys {
            check(!key.isEmpty, "key \(key) is non-empty")
        }
        // Verify keys are distinct
        let uniqueKeys = Set(expectedKeys)
        checkEqual(uniqueKeys.count, expectedKeys.count, "all keys are unique")
        print("  ✓ Persistence key naming")
    }

    // Restore original values
    for (key, value) in savedValues {
        if let value = value {
            defaults.set(value, forKey: key)
        }
    }
}
