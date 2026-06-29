import Foundation
#if canImport(FoundationModels) && compiler(>=6.2)
import FoundationModels
#endif

/// On-device AI lyrics summary using Apple Foundation Models (macOS 26+).
/// Generates a one-line theme summary of a song's lyrics, cached per (title, artist).
///
/// When Foundation Models is not available (macOS < 26 or unsupported hardware),
/// `summarizeLyrics` returns nil gracefully.
@MainActor
public final class FoundationModelProvider {
    private var cache: [String: String] = [:]

    public init() {}

    private func cacheKey(title: String, artist: String) -> String {
        "\(title.lowercased())|\(artist.lowercased())"
    }

    /// Build the prompt for lyrics summarization.
    public func buildPrompt(lines: [String], title: String, artist: String) -> String {
        let lyricsText = lines.prefix(40).joined(separator: "\n")
        return "Song: \(title) by \(artist)\nLyrics:\n\(lyricsText)"
    }

    /// Summarize lyrics into a one-line theme description.
    /// Returns nil if Foundation Models is unavailable or the request times out.
    public func summarizeLyrics(_ lines: [String], title: String, artist: String) async -> String? {
        let key = cacheKey(title: title, artist: artist)
        if let cached = cache[key] { return cached }
        guard !lines.isEmpty else { return nil }

        guard let summary = await invokeFoundationModel(lines: lines, title: title, artist: artist) else {
            return nil
        }

        cache[key] = summary
        return summary
    }

    /// Cache a summary directly (useful for testing or manual input).
    public func cacheSummary(_ summary: String, title: String, artist: String) {
        cache[cacheKey(title: title, artist: artist)] = summary
    }

    /// Check if a summary is cached for the given track.
    public func hasCachedSummary(title: String, artist: String) -> Bool {
        cache[cacheKey(title: title, artist: artist)] != nil
    }

    private func invokeFoundationModel(lines: [String], title: String, artist: String) async -> String? {
        #if canImport(FoundationModels) && compiler(>=6.2)
        guard #available(macOS 26, *) else { return nil }
        guard SystemLanguageModel.default.availability == .available else {
            print("[AI-Summary] Apple Intelligence not enabled")
            return nil
        }

        let prompt = buildPrompt(lines: lines, title: title, artist: artist)

        do {
            let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
            let session = LanguageModelSession(model: model) {
                "You summarize song themes in one short sentence (max 15 words). Output only the summary sentence, nothing else."
            }

            // Race the model call against a 10-second timeout
            let summary: String? = try await withThrowingTaskGroup(of: String?.self) { group in
                group.addTask {
                    let response = try await session.respond(to: prompt)
                    return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(10))
                    return nil
                }

                if let first = try await group.next() {
                    group.cancelAll()
                    return first
                }
                return nil
            }

            if let summary, !summary.isEmpty {
                return summary
            }
            return nil
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}
