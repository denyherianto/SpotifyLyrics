import Foundation
@testable import SpotifyLyricsCore


@MainActor
func testEnrichment() {
    print("--- Enrichment Tests ---")

    // ICU romanization: Japanese (synchronous via CFStringTransform)
    do {
        let provider = ICURomanizationProvider()
        // Test the isLatin helper directly
        check(!provider.isLatin("こんにちは"), "Japanese is not Latin")
        check(!provider.isLatin("你好"), "Chinese is not Latin")
        check(!provider.isLatin("안녕"), "Korean is not Latin")
        check(!provider.isLatin("Привет"), "Cyrillic is not Latin")
        check(provider.isLatin("Hello World"), "English is Latin")
        check(provider.isLatin("Café résumé"), "French diacritics are Latin")
        check(provider.isLatin(""), "Empty string is Latin (vacuously)")
        print("  ✓ isLatin detection")
    }

    // Japanese romanization via CFStringTokenizer (correct readings)
    do {
        let provider = ICURomanizationProvider()
        let jaLines = try! awaitSync { try await provider.romanize(["大丈夫", "こんにちは", "憧れ"], from: "ja") }
        check(jaLines[0] != nil, "大丈夫 should be romanized")
        check(jaLines[0]?.lowercased().contains("daijoubu") == true || jaLines[0]?.lowercased().contains("daijobu") == true,
              "大丈夫 should be 'daijoubu' not Chinese pinyin (got: \(jaLines[0] ?? "nil"))")
        check(jaLines[1] != nil, "こんにちは should be romanized")
        check(jaLines[1]?.lowercased().contains("konnichiha") == true || jaLines[1]?.lowercased().contains("konnichiwa") == true || jaLines[1]?.lowercased().contains("kon'nichiha") == true,
              "こんにちは romanization (got: \(jaLines[1] ?? "nil"))")
        check(jaLines[2] != nil, "憧れ should be romanized")
        check(jaLines[2]?.lowercased().contains("akogare") == true,
              "憧れ should be 'akogare' (got: \(jaLines[2] ?? "nil"))")
        print("  ✓ Japanese romanization (CFStringTokenizer)")

        // Chinese should still use CFStringTransform (pinyin)
        let zhLines = try! awaitSync { try await provider.romanize(["你好世界"], from: "zh-Hans") }
        check(zhLines[0] != nil, "Chinese should be romanized")
        check(zhLines[0]?.lowercased().contains("ni") == true, "Chinese should use pinyin")
        print("  ✓ Chinese romanization (pinyin)")
    }

    // ICU transliteration via CFStringTransform directly
    do {
        let ja = NSMutableString(string: "こんにちは")
        let transformed = CFStringTransform(ja, nil, kCFStringTransformToLatin, false)
        check(transformed, "CFStringTransform should succeed for Japanese")
        check((ja as String) != "こんにちは", "Japanese should be transformed")
        print("  ✓ CFStringTransform works for Japanese")

        let zh = NSMutableString(string: "你好世界")
        CFStringTransform(zh, nil, kCFStringTransformToLatin, false)
        CFStringTransform(zh, nil, kCFStringTransformStripCombiningMarks, false)
        let zhResult = zh as String
        check(zhResult.lowercased().contains("ni"), "Chinese toLatin should contain 'ni'")
        print("  ✓ CFStringTransform works for Chinese")

        let ko = NSMutableString(string: "안녕하세요")
        CFStringTransform(ko, nil, kCFStringTransformToLatin, false)
        let koResult = ko as String
        check(koResult != "안녕하세요", "Korean should be transformed")
        print("  ✓ CFStringTransform works for Korean")

        // Latin text should remain unchanged
        let en = NSMutableString(string: "Hello")
        CFStringTransform(en, nil, kCFStringTransformToLatin, false)
        checkEqual(en as String, "Hello", "Latin text unchanged")
        print("  ✓ CFStringTransform no-ops on Latin")
    }

    // LineEnrichment model
    do {
        let empty = LineEnrichment()
        check(empty.isEmpty, "Empty enrichment is empty")
        check(empty.romanization == nil, "No romanization by default")
        check(empty.translation == nil, "No translation by default")

        let withRom = LineEnrichment(romanization: "konnichiha")
        check(!withRom.isEmpty, "Enrichment with romanization is not empty")
        checkEqual(withRom.romanization, "konnichiha", "romanization value")

        let full = LineEnrichment(romanization: "ni hao", translation: "hello")
        check(!full.isEmpty, "Full enrichment is not empty")
        checkEqual(full.romanization, "ni hao", "romanization value")
        checkEqual(full.translation, "hello", "translation value")

        // Equatable
        let a = LineEnrichment(romanization: "test")
        let b = LineEnrichment(romanization: "test")
        let c = LineEnrichment(romanization: "other")
        check(a == b, "Equal enrichments are equal")
        check(a != c, "Different enrichments are not equal")
        print("  ✓ LineEnrichment model")
    }

    // EnrichmentCapabilities
    do {
        let rom: EnrichmentCapabilities = .romanization
        let trans: EnrichmentCapabilities = .translation
        let both: EnrichmentCapabilities = [.romanization, .translation]

        check(rom.contains(.romanization), "rom contains romanization")
        check(!rom.contains(.translation), "rom does not contain translation")
        check(both.contains(.romanization), "both contains romanization")
        check(both.contains(.translation), "both contains translation")
        check(!trans.contains(.romanization), "trans does not contain romanization")
        print("  ✓ EnrichmentCapabilities")
    }

    // EnrichmentCoordinator: language detection (synchronous NLLanguageRecognizer)
    do {
        let coordinator = EnrichmentCoordinator()

        let jaLines = ["こんにちは世界", "桜の花が咲いている", "夜空に星が光る"]
        let jaLang = coordinator.detectLanguage(from: jaLines)
        checkEqual(jaLang, "ja", "Japanese detected")

        let enLines = ["Hello world", "This is a test", "How are you doing today"]
        let enLang = coordinator.detectLanguage(from: enLines)
        checkEqual(enLang, "en", "English detected")

        let zhLines = ["你好世界", "今天天气很好", "我喜欢音乐"]
        let zhLang = coordinator.detectLanguage(from: zhLines)
        check(zhLang?.hasPrefix("zh") == true, "Chinese detected (got \(zhLang ?? "nil"))")

        let emptyLang = coordinator.detectLanguage(from: [])
        check(emptyLang == nil, "Empty lines returns nil language")

        print("  ✓ Language detection")
    }

    // ICURomanizationProvider capabilities
    do {
        let provider = ICURomanizationProvider()
        check(provider.capabilities.contains(.romanization), "ICU has romanization")
        check(!provider.capabilities.contains(.translation), "ICU has no translation")
        print("  ✓ ICURomanizationProvider capabilities")
    }
}

/// Blocks the current thread to run an async throwing closure.
/// Safe in tests since we know the async work is CPU-bound, not suspending.
private func awaitSync<T>(_ block: @Sendable @escaping () async throws -> T) rethrows -> T {
    let box = UnsafeMutablePointer<Result<T, Error>>.allocate(capacity: 1)
    defer { box.deallocate() }
    let sema = DispatchSemaphore(value: 0)
    Task.detached {
        do {
            box.pointee = .success(try await block())
        } catch {
            box.pointee = .failure(error)
        }
        sema.signal()
    }
    sema.wait()
    return try! box.pointee.get()
}
