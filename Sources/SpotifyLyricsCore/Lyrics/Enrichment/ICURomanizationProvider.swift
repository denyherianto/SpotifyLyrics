import Foundation

public struct ICURomanizationProvider: LyricsEnrichmentProvider {
    public let capabilities: EnrichmentCapabilities = .romanization

    public init() {}

    public func romanize(_ lines: [String], from sourceLanguage: String?) async throws -> [String?] {
        let isJapanese = sourceLanguage == "ja"
        return lines.map { line in
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            guard !isLatin(line) else { return nil }
            if isJapanese || containsJapanese(line) {
                return transliterateJapanese(line)
            }
            return transliterate(line)
        }
    }

    /// Japanese-aware romanization using CFStringTokenizer which provides
    /// correct readings (e.g. 大丈夫 → daijoubu, not da zhang fu).
    private func transliterateJapanese(_ text: String) -> String? {
        let cfText = text as CFString
        let tokenizer = CFStringTokenizerCreate(
            nil, cfText, CFRangeMake(0, CFStringGetLength(cfText)),
            kCFStringTokenizerUnitWord, Locale(identifier: "ja") as CFLocale
        )

        var parts: [String] = []
        var tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)

        while tokenType != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let tokenText = CFStringCreateWithSubstring(nil, cfText, range) as String

            if let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String {
                parts.append(latin)
            } else {
                // Keep non-transliterable tokens (punctuation, Latin text) as-is
                parts.append(tokenText)
            }
            tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }

        let result = parts.joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !result.isEmpty, result != text else { return nil }
        return result
    }

    private func transliterate(_ text: String) -> String? {
        let mutable = NSMutableString(string: text)
        // toLatin converts CJK, Cyrillic, Arabic, etc. to Latin script
        guard CFStringTransform(mutable, nil, kCFStringTransformToLatin, false) else { return nil }
        // Strip combining marks (diacritics) for cleaner output
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        let result = mutable as String
        // If the result is identical to input, no useful transform happened
        guard result != text else { return nil }
        return result
    }

    /// Detects if text contains Hiragana, Katakana, or CJK characters in Japanese context.
    private func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            // Hiragana
            (0x3040...0x309F).contains(scalar.value) ||
            // Katakana
            (0x30A0...0x30FF).contains(scalar.value)
        }
    }

    /// Returns true if the string is predominantly Latin script (ASCII letters + common Latin Extended).
    func isLatin(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return true }
        let latinCount = letters.filter { scalar in
            // Basic Latin + Latin Extended-A/B + Latin Extended Additional
            (0x0041...0x024F).contains(scalar.value) ||
            (0x1E00...0x1EFF).contains(scalar.value)
        }.count
        return Double(latinCount) / Double(letters.count) > 0.5
    }
}
