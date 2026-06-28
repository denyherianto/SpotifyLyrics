import Foundation
import NaturalLanguage

#if canImport(Translation) && compiler(>=6.2)
import Translation

@available(macOS 26.0, *)
public struct AppleTranslationProvider: LyricsEnrichmentProvider, Sendable {
    public let capabilities: EnrichmentCapabilities = .translation

    public init() {}

    public func translate(_ lines: [String], to targetLanguage: String, from sourceLanguage: String?) async throws -> [String?] {
        let target = Locale.Language(identifier: targetLanguage)
        let targetCode = target.languageCode?.identifier ?? targetLanguage
        let availability = LanguageAvailability()

        var sessions: [String: TranslationSession] = [:]

        func session(for srcLang: String) async -> TranslationSession? {
            if let existing = sessions[srcLang] { return existing }
            let src = Locale.Language(identifier: srcLang)
            let status = await availability.status(from: src, to: target)
            guard status == .installed else { return nil }
            let s = TranslationSession(installedSource: src, target: target)
            sessions[srcLang] = s
            return s
        }

        var results = [String?](repeating: nil, count: lines.count)
        let recognizer = NLLanguageRecognizer()

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Detect dominant language of the whole line
            recognizer.reset()
            recognizer.processString(trimmed)
            let lineLang = recognizer.dominantLanguage?.rawValue

            // Skip if line is already in target language
            if let lineLang {
                let lineCode = Locale.Language(identifier: lineLang).languageCode?.identifier ?? lineLang
                if lineCode == targetCode { continue }
            }

            // Check if line has mixed languages (multiple scripts)
            let segments = segmentByLanguage(trimmed, recognizer: recognizer)

            if segments.count > 1 {
                // Mixed-language line: translate each foreign segment independently
                var translatedParts: [String] = []
                var anyTranslated = false

                for segment in segments {
                    let segCode = Locale.Language(identifier: segment.language).languageCode?.identifier ?? segment.language
                    if segCode == targetCode {
                        // Already in target language, keep as-is
                        translatedParts.append(segment.text)
                    } else if let sess = await session(for: segment.language) {
                        if let response = try? await sess.translate(segment.text),
                           response.targetText != segment.text {
                            translatedParts.append(response.targetText)
                            anyTranslated = true
                        } else {
                            translatedParts.append(segment.text)
                        }
                    } else {
                        translatedParts.append(segment.text)
                    }
                }

                if anyTranslated {
                    results[i] = translatedParts.joined(separator: " ")
                }
            } else {
                // Single-language line: translate directly
                guard let lang = lineLang ?? sourceLanguage else { continue }
                guard let sess = await session(for: lang) else { continue }

                do {
                    let response = try await sess.translate(trimmed)
                    if response.targetText != trimmed {
                        results[i] = response.targetText
                    }
                } catch {
                    if let fallbackLang = sourceLanguage, fallbackLang != lang,
                       let fallbackSess = await session(for: fallbackLang) {
                        if let response = try? await fallbackSess.translate(trimmed),
                           response.targetText != trimmed {
                            results[i] = response.targetText
                        }
                    }
                }
            }
        }

        return results
    }

    /// Splits text into segments by detected language using NLTagger.
    private func segmentByLanguage(_ text: String, recognizer: NLLanguageRecognizer) -> [LangSegment] {
        let tagger = NLTagger(tagSchemes: [.language])
        tagger.string = text

        var segments: [LangSegment] = []
        var lastLang: String?
        var currentText = ""

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .language) { tag, range in
            let word = String(text[range])
            let lang = tag?.rawValue ?? "und"

            if lang == lastLang || lastLang == nil {
                currentText += word
                lastLang = lang
            } else {
                if !currentText.isEmpty, let prevLang = lastLang {
                    segments.append(LangSegment(text: currentText.trimmingCharacters(in: .whitespaces), language: prevLang))
                }
                currentText = word
                lastLang = lang
            }
            return true
        }

        // Flush remaining
        if !currentText.isEmpty, let lang = lastLang {
            segments.append(LangSegment(text: currentText.trimmingCharacters(in: .whitespaces), language: lang))
        }

        // Merge adjacent segments with the same language
        var merged: [LangSegment] = []
        for seg in segments where !seg.text.isEmpty {
            if let last = merged.last, last.language == seg.language {
                merged[merged.count - 1] = LangSegment(text: last.text + " " + seg.text, language: seg.language)
            } else {
                merged.append(seg)
            }
        }

        // Filter out "und" (undetermined) — attach to nearest neighbor
        if merged.count > 1 {
            var resolved: [LangSegment] = []
            for seg in merged {
                if seg.language == "und" {
                    // Attach to previous segment if exists, else next
                    if var prev = resolved.last {
                        prev = LangSegment(text: prev.text + " " + seg.text, language: prev.language)
                        resolved[resolved.count - 1] = prev
                    } else {
                        resolved.append(seg)
                    }
                } else {
                    resolved.append(seg)
                }
            }
            return resolved
        }

        return merged
    }
}

private struct LangSegment {
    let text: String
    let language: String
}
#endif
