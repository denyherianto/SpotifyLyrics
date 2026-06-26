import Foundation
@testable import SpotifyLyricsCore

nonisolated(unsafe) var passed = 0
nonisolated(unsafe) var failed = 0
nonisolated(unsafe) var failures: [(String, String)] = []

func check(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) {
    if condition {
        passed += 1
    } else {
        failed += 1
        let label = message.isEmpty ? "\(file):\(line)" : message
        failures.append(("L\(line)", label))
    }
}

func checkEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #file, line: Int = #line) {
    if a == b {
        passed += 1
    } else {
        failed += 1
        let label = message.isEmpty ? "Expected \(a) == \(b)" : "\(message) — got \(a), expected \(b)"
        failures.append(("L\(line)", label))
    }
}

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
    static func main() async {
        setbuf(stdout, nil)
        await MainActor.run {
        print("Running SpotifyLyrics Tests...\n")

        testLRCParser()
        testParseNumber()
        testLyricsManager()
        testModels()
        testPlaybackInfo()
        testOverlaySize()
        testSettingsPersistence()
        testSeekBarFormatting()
        testMenuBarTrackInfo()
        testAnimationMode()
        testEnrichment()
        testOverlayTrackInfo()

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

        fflush(stdout)
        }
        exit(failed > 0 ? 1 : 0)
    }
}
