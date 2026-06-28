import Foundation
import NaturalLanguage

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
    public func enrich(
        lines: [String],
        romanize: Bool,
        translate: Bool,
        targetLanguage: String = "en"
    ) async -> [Int: LineEnrichment] {
        guard !lines.isEmpty, romanize || translate else { return [:] }

        let sourceLanguage = detectLanguage(from: lines)
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
        if translate, let provider = provider(for: .translation) {
            if sourceLanguage != targetLanguage {
                do {
                    let translated = try await provider.translate(lines, to: targetLanguage, from: sourceLanguage)
                    for (i, trans) in translated.enumerated() {
                        if let trans, !trans.isEmpty {
                            var enrichment = result[i] ?? LineEnrichment()
                            enrichment.translation = trans
                            result[i] = enrichment
                        }
                    }
                } catch {
                    print("[Enrichment] Translation error: \(error)")
                }
            }
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
}
