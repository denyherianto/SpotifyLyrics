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
    private let speechProvider = SpeechRecognitionProvider()
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

    /// Attempt speech recognition on captured audio as a last-resort lyrics source.
    /// Called by the alignment coordinator when lyrics fetch returned empty.
    public func attemptSpeechRecognition(
        audioBuffer: [Float],
        captureStartPosition: TimeInterval,
        cacheKey: String
    ) async {
        guard !hasLyrics else { return }

        isLoading = true
        if let lines = await speechProvider.recognizeLyrics(
            from: audioBuffer,
            captureStartPosition: captureStartPosition
        ) {
            cache[cacheKey] = lines
            currentLines = lines
            hasLyrics = true
            startEnrichment(for: cacheKey)
        }
        isLoading = false
    }

    /// Re-run enrichment for the current lyrics (e.g. when settings change).
    public func refreshEnrichment() {
        guard hasLyrics, !currentLines.isEmpty else { return }
        // Cancel any in-flight enrichment
        enrichmentTask?.cancel()
        enrichmentTask = nil
        enrichment = [:]
        // Find lyrics cache key and restart — the new enrichment cache key
        // (which encodes current settings) will naturally miss stale entries.
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

    /// Returns the timestamp of the next lyric line after the current one,
    /// or nil if at the last line or no lyrics are loaded.
    public var nextLineTimestamp: TimeInterval? {
        let nextIndex = currentLineIndex + 1
        guard nextIndex < currentLines.count else { return nil }
        return currentLines[nextIndex].timestamp
    }

    public func clearCache() {
        cache.removeAll()
        enrichmentCache.removeAll()
        enrichment = [:]
    }
}
