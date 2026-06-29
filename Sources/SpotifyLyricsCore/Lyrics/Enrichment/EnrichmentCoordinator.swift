import Foundation
import NaturalLanguage
#if canImport(FoundationModels) && compiler(>=6.2)
import FoundationModels
#endif
#if canImport(Translation) && compiler(>=6.2)
import Translation
#endif

@MainActor
public final class EnrichmentCoordinator {
    private var providers: [LyricsEnrichmentProvider]

    public init() {
        var list: [LyricsEnrichmentProvider] = [ICURomanizationProvider()]
        #if canImport(Translation) && compiler(>=6.2)
        if #available(macOS 26.0, *) {
            list.append(AppleTranslationProvider())
        }
        #endif
        providers = list
    }

    /// Enrich lyrics lines with romanization and/or translation.
    /// The `onRefinement` callback fires asynchronously when AI-refined translations are ready.
    public func enrich(
        lines: [String],
        romanize: Bool,
        translate: Bool,
        targetLanguage: String = "en",
        aiTranslationMode: AITranslationMode = .refine,
        onRefinement: (([Int: LineEnrichment]) -> Void)? = nil
    ) async -> [Int: LineEnrichment] {
        guard !lines.isEmpty, romanize || translate else { return [:] }

        let sourceLanguage = detectLanguage(from: lines)
        print("[Enrichment] Starting enrichment: \(lines.count) lines, source=\(sourceLanguage ?? "nil"), target=\(targetLanguage), romanize=\(romanize), translate=\(translate), aiMode=\(aiTranslationMode.rawValue)")
        var result: [Int: LineEnrichment] = [:]

        // Romanization
        if romanize, let provider = provider(for: .romanization) {
            do {
                let romanized = try await provider.romanize(lines, from: sourceLanguage)
                for (i, rom) in romanized.enumerated() {
                    if let rom, !rom.isEmpty {
                        var enrichment = result[i] ?? LineEnrichment()
                        enrichment.romanization = rom
                        result[i] = enrichment
                    }
                }
            } catch {
                // Best-effort
            }
        }

        // Translation
        if translate, sourceLanguage != targetLanguage {
            switch aiTranslationMode {
            case .primary:
                // AI translates first, Apple Translation fills gaps
                print("[Enrichment] AI Primary mode: translating with Foundation Model")
                let aiTranslations = await translateWithFoundationModel(lines, targetLanguage: targetLanguage)
                for (i, trans) in aiTranslations {
                    var enrichment = result[i] ?? LineEnrichment()
                    enrichment.translation = fixPostCommaCapitalization(trans)
                    result[i] = enrichment
                    print("[Enrichment]   [\(i)] AI: \"\(lines[i])\" → \"\(trans)\"")
                }

                // Fill gaps with Apple Translation
                if let provider = provider(for: .translation) {
                    let missingIndices = lines.indices.filter { i in
                        let trimmed = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                        return !trimmed.isEmpty && result[i]?.translation == nil
                    }
                    if !missingIndices.isEmpty {
                        print("[Enrichment] Apple Translation fallback for \(missingIndices.count) lines")
                        if let translated = try? await provider.translate(lines, to: targetLanguage, from: sourceLanguage) {
                            for i in missingIndices {
                                if let trans = translated[i], !trans.isEmpty {
                                    var enrichment = result[i] ?? LineEnrichment()
                                    enrichment.translation = fixPostCommaCapitalization(trans)
                                    result[i] = enrichment
                                }
                            }
                        }
                    }
                }

            case .refine:
                // Apple Translation first, AI refines in background
                if let provider = provider(for: .translation) {
                    print("[Enrichment] Refine mode: Apple Translation first")
                    do {
                        let translated = try await provider.translate(lines, to: targetLanguage, from: sourceLanguage)
                        for (i, trans) in translated.enumerated() {
                            if let trans, !trans.isEmpty {
                                var enrichment = result[i] ?? LineEnrichment()
                                enrichment.translation = fixPostCommaCapitalization(trans)
                                result[i] = enrichment
                                print("[Enrichment]   [\(i)] \"\(lines[i])\" → \"\(trans)\"")
                            }
                        }
                    } catch {
                        print("[Enrichment] Apple Translation error: \(error)")
                    }
                }

                if let onRefinement {
                    let baseResult = result
                    let target = targetLanguage
                    let capturedLines = lines
                    Task { [weak self] in
                        guard let self else { return }
                        let aiTranslations = await self.translateWithFoundationModel(capturedLines, targetLanguage: target)
                        guard !aiTranslations.isEmpty, !Task.isCancelled else {
                            print("[Enrichment] AI refinement: no improvements")
                            return
                        }
                        var updated = baseResult
                        for (index, trans) in aiTranslations {
                            var enrichment = updated[index] ?? LineEnrichment()
                            enrichment.translation = fixPostCommaCapitalization(trans)
                            updated[index] = enrichment
                        }
                        print("[Enrichment] AI refinement: replaced \(aiTranslations.count) translations")
                        onRefinement(updated)
                    }
                }

            case .off:
                // Apple Translation only
                if let provider = provider(for: .translation) {
                    print("[Enrichment] Off mode: Apple Translation only")
                    do {
                        let translated = try await provider.translate(lines, to: targetLanguage, from: sourceLanguage)
                        for (i, trans) in translated.enumerated() {
                            if let trans, !trans.isEmpty {
                                var enrichment = result[i] ?? LineEnrichment()
                                enrichment.translation = fixPostCommaCapitalization(trans)
                                result[i] = enrichment
                            }
                        }
                    } catch {
                        print("[Enrichment] Apple Translation error: \(error)")
                    }
                }
            }
        } else if translate {
            print("[Enrichment] Skipping translation: source (\(sourceLanguage ?? "nil")) == target (\(targetLanguage))")
        }

        return result
    }

    /// Detect the dominant language from a sample of lyric lines.
    func detectLanguage(from lines: [String]) -> String? {
        let recognizer = NLLanguageRecognizer()
        let sample = lines
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(20)
            .joined(separator: "\n")
        recognizer.processString(sample)
        return recognizer.dominantLanguage?.rawValue
    }

    private func provider(for capability: EnrichmentCapabilities) -> LyricsEnrichmentProvider? {
        providers.first { $0.capabilities.contains(capability) }
    }

    /// Lowercase words after commas that were incorrectly capitalized by translation APIs.
    /// e.g. "Ya, Ah" → "Ya, ah"
    private func fixPostCommaCapitalization(_ text: String) -> String {
        var result = text
        let pattern = try! NSRegularExpression(pattern: #",\s+([A-Z])"#)
        let matches = pattern.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let capRange = Range(match.range(at: 1), in: result) else { continue }
            result.replaceSubrange(capRange, with: result[capRange].lowercased())
        }
        return result
    }

    /// Check if the translation language pair is available and return a user-facing notice if not.
    public func checkTranslationAvailability(lines: [String], targetLanguage: String) async -> String? {
        #if canImport(Translation) && compiler(>=6.2)
        guard #available(macOS 26.0, *) else { return nil }

        let sourceLanguage = detectLanguage(from: lines)
        guard let srcLang = sourceLanguage else { return nil }

        let src = Locale.Language(identifier: srcLang)
        let target = Locale.Language(identifier: targetLanguage)

        let srcCode = src.languageCode?.identifier ?? srcLang
        let targetCode = target.languageCode?.identifier ?? targetLanguage
        guard srcCode != targetCode else { return nil }

        let availability = LanguageAvailability()
        let status = await availability.status(from: src, to: target)

        switch status {
        case .installed:
            return nil
        case .supported:
            let srcName = Locale.current.localizedString(forLanguageCode: srcLang) ?? srcLang
            let targetName = Locale.current.localizedString(forLanguageCode: targetLanguage) ?? targetLanguage
            return "Download \(srcName) → \(targetName) language pack in Settings → Translation & Languages."
        case .unsupported:
            let srcName = Locale.current.localizedString(forLanguageCode: srcLang) ?? srcLang
            let targetName = Locale.current.localizedString(forLanguageCode: targetLanguage) ?? targetLanguage
            return "\(srcName) → \(targetName) translation is not supported."
        @unknown default:
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Translate song lyrics using Foundation Models (on-device AI).
    /// Returns a dictionary of line index → translated text.
    private func translateWithFoundationModel(
        _ lines: [String],
        targetLanguage: String
    ) async -> [Int: String] {
        #if canImport(FoundationModels) && compiler(>=6.2)
        guard #available(macOS 26, *) else {
            print("[AI-Translate] macOS 26 not available")
            return [:]
        }
        guard SystemLanguageModel.default.availability == .available else {
            print("[AI-Translate] Apple Intelligence not enabled")
            return [:]
        }

        // Filter to non-empty lines
        let indexedLines = lines.enumerated().compactMap { (i, line) -> (Int, String)? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : (i, trimmed)
        }
        guard !indexedLines.isEmpty else { return [:] }

        let langName = Locale.current.localizedString(forLanguageCode: targetLanguage) ?? targetLanguage

        // Split into batches to reduce guardrail violations
        let batchSize = 10
        let batches = stride(from: 0, to: indexedLines.count, by: batchSize).map {
            Array(indexedLines[$0..<min($0 + batchSize, indexedLines.count)])
        }

        print("[AI-Translate] Sending \(indexedLines.count) lines in \(batches.count) batches to Foundation Model")

        var translations: [Int: String] = [:]

        let session = LanguageModelSession {
            "You are a professional song lyric translator. Translate lyrics accurately with correct contextual meaning for slang, idioms, and figurative language. Output only numbered translations."
        }

        for (batchIndex, batch) in batches.enumerated() {
                guard !Task.isCancelled else { break }

                let numberedLyrics = batch.enumerated().map { (n, pair) in
                    "\(n + 1). \(pair.1)"
                }.joined(separator: "\n")

                let prompt = """
                Translate these song lyrics to \(langName). Use correct contextual meaning (e.g. "high" = mabuk/melayang, "blue" = sedih).
                Output ONLY: NUMBER. translation

                \(numberedLyrics)
                """

                do {
                    let response: String? = try await withThrowingTaskGroup(of: String?.self) { group in
                        group.addTask {
                            let resp = try await session.respond(to: prompt)
                            return resp.content.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        group.addTask {
                            try await Task.sleep(for: .seconds(15))
                            return nil
                        }
                        if let first = try await group.next() {
                            group.cancelAll()
                            return first
                        }
                        return nil
                    }

                    guard let response, !response.isEmpty else {
                        print("[AI-Translate] Batch \(batchIndex + 1): no response or timed out")
                        continue
                    }

                    // Parse "NUMBER. translation" lines
                    for line in response.components(separatedBy: .newlines) {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }
                        guard let dotIndex = trimmed.firstIndex(of: ".") else { continue }
                        let numStr = trimmed[trimmed.startIndex..<dotIndex].trimmingCharacters(in: .whitespaces)
                        guard let num = Int(numStr), num >= 1, num <= batch.count else { continue }
                        let translatedText = trimmed[trimmed.index(after: dotIndex)...].trimmingCharacters(in: .whitespaces)
                        if !translatedText.isEmpty {
                            let originalIndex = batch[num - 1].0
                            translations[originalIndex] = translatedText
                        }
                    }
                    print("[AI-Translate] Batch \(batchIndex + 1): translated \(batch.count) lines")
                } catch {
                    // Guardrail violation or other error — skip this batch silently
                    print("[AI-Translate] Batch \(batchIndex + 1) skipped (guardrail/error): \(error)")
                    continue
                }
            }

        print("[AI-Translate] Total: \(translations.count)/\(indexedLines.count) lines translated")
        return translations
        #else
        print("[AI-Translate] FoundationModels not available at compile time")
        return [:]
        #endif
    }
}
