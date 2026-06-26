import Foundation

@MainActor
public final class LyricsManager: ObservableObject {
    @Published public var currentLines: [LyricLine] = []
    @Published public var currentLineIndex: Int = 0
    @Published public var isLoading = false
    @Published public var hasLyrics = false
    @Published public var enrichment: [Int: LineEnrichment] = [:]

    public var showRomanization = false
    public var showTranslation = false
    public var targetLanguage: String = "en"

    private let lrcLib = LRCLibProvider()
    private let musixmatch = MusixmatchProvider()
    private var cache: [String: [LyricLine]] = [:]
    private var enrichmentCache: [String: [Int: LineEnrichment]] = [:]
    private var enrichmentTask: Task<Void, Never>?
    private let enrichmentCoordinator = EnrichmentCoordinator()

    public init() {}

    public func fetchLyrics(for track: TrackInfo) async {
        let key = track.cacheKey

        // Cancel any in-flight enrichment work
        enrichmentTask?.cancel()
        enrichmentTask = nil

        if let cached = cache[key] {
            currentLines = cached
            hasLyrics = !cached.isEmpty
            currentLineIndex = 0
            startEnrichment(for: key)
            return
        }

        isLoading = true
        currentLines = []
        enrichment = [:]
        hasLyrics = false
        currentLineIndex = 0

        // Try LRCLIB first
        if let lines = await lrcLib.fetchLyrics(title: track.title, artist: track.artist), !lines.isEmpty {
            cache[key] = lines
            currentLines = lines
            hasLyrics = true
            isLoading = false
            startEnrichment(for: key)
            return
        }

        // Fallback to Musixmatch
        if let lines = await musixmatch.fetchLyrics(title: track.title, artist: track.artist), !lines.isEmpty {
            cache[key] = lines
            currentLines = lines
            hasLyrics = true
            isLoading = false
            startEnrichment(for: key)
            return
        }

        isLoading = false
    }

    /// Re-run enrichment for the current lyrics (e.g. when settings change).
    public func refreshEnrichment() {
        guard hasLyrics, !currentLines.isEmpty else { return }
        // Cancel any in-flight enrichment
        enrichmentTask?.cancel()
        enrichmentTask = nil
        // Clear all enrichment cache to avoid stale translations
        enrichmentCache.removeAll()
        enrichment = [:]
        // Find lyrics cache key and restart
        for (key, cached) in cache where cached == currentLines {
            startEnrichment(for: key)
            return
        }
    }

    private func startEnrichment(for lyricsKey: String) {
        let enrichKey = enrichmentCacheKey(for: lyricsKey)

        // Check enrichment cache
        if let cached = enrichmentCache[enrichKey] {
            enrichment = cached
            return
        }

        guard showRomanization || showTranslation else {
            enrichment = [:]
            return
        }

        let lines = currentLines.map(\.text)
        let romanize = showRomanization
        let translate = showTranslation
        let target = targetLanguage

        enrichmentTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.enrichmentCoordinator.enrich(
                lines: lines,
                romanize: romanize,
                translate: translate,
                targetLanguage: target
            )
            guard !Task.isCancelled else { return }
            self.enrichmentCache[enrichKey] = result
            self.enrichment = result
        }
    }

    private func enrichmentCacheKey(for lyricsKey: String) -> String {
        "\(lyricsKey)|r:\(showRomanization)|t:\(showTranslation)|\(targetLanguage)"
    }

    private func enrichmentCacheKey(from lines: [LyricLine]) -> String {
        // Reconstruct the lyrics cache key by finding it
        for (key, cached) in cache where cached == lines {
            return enrichmentCacheKey(for: key)
        }
        // Fallback: use hash of text content
        let hash = lines.map(\.text).joined(separator: "|").hashValue
        return enrichmentCacheKey(for: "hash:\(hash)")
    }

    public func updateCurrentLine(at position: TimeInterval) {
        guard !currentLines.isEmpty else { return }

        var index = 0
        for (i, line) in currentLines.enumerated() {
            if line.timestamp <= position {
                index = i
            } else {
                break
            }
        }

        if index != currentLineIndex {
            currentLineIndex = index
        }
    }

    public func clearCache() {
        cache.removeAll()
        enrichmentCache.removeAll()
        enrichment = [:]
    }
}
