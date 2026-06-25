import Foundation
@testable import SpotifyLyricsCore

@MainActor
var passed = 0
@MainActor
var failed = 0
@MainActor
var failures: [(String, String)] = []

@MainActor
func check(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) {
    if condition {
        passed += 1
    } else {
        failed += 1
        let label = message.isEmpty ? "\(file):\(line)" : message
        failures.append(("L\(line)", label))
    }
}

@MainActor
func checkEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #file, line: Int = #line) {
    if a == b {
        passed += 1
    } else {
        failed += 1
        let label = message.isEmpty ? "Expected \(a) == \(b)" : "\(message) — got \(a), expected \(b)"
        failures.append(("L\(line)", label))
    }
}

@MainActor
func checkApprox(_ a: Double, _ b: Double, accuracy: Double = 0.01, file: String = #file, line: Int = #line) {
    if abs(a - b) < accuracy {
        passed += 1
    } else {
        failed += 1
        failures.append(("L\(line)", "Expected \(a) ≈ \(b) (±\(accuracy))"))
    }
}

@main
struct TestMain {
    @MainActor
    static func main() {
        print("Running SpotifyLyrics Tests...\n")

        testLRCParser()
        testParseNumber()
        testLyricsManager()
        testModels()
        testPlaybackInfo()
        testOverlaySize()
        testSettingsPersistence()
        testSeekBarFormatting()

        print("\n========================================")
        if failures.isEmpty {
            print("  ✅ ALL TESTS PASSED: \(passed) assertions")
        } else {
            print("  ❌ RESULTS: \(passed) passed, \(failed) failed")
            print("  FAILURES:")
            for (loc, msg) in failures {
                print("    ✗ \(loc): \(msg)")
            }
        }
        print("========================================\n")

        if failed > 0 {
            exit(1)
        }
    }
}
