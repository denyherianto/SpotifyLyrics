import Foundation

@MainActor
public final class LyricsManager: ObservableObject {
    @Published public var currentLines: [LyricLine] = []
    @Published public var currentLineIndex: Int = 0
    @Published public var isLoading = false
    @Published public var hasLyrics = false
    @Published public var enrichment: [Int: LineEnrichment] = [:]
    @Published public var songSummary: String?
    @Published public var translationNotice: String?
    @Published public var isInstrumentalBreak = false
    @Published public var instrumentalBreakCountdown: TimeInterval = 0
    @Published public var nextVocalLineText: String?

    /// Minimum gap (seconds) between current line end and next line start to trigger a break.
    public static let instrumentalBreakThreshold: TimeInterval = 8.0
    /// Seconds before the next vocal line to dismiss the break view.
    public static let breakDismissLeadTime: TimeInterval = 1.0

    public var showRomanization = false
    public var showTranslation = false
    public var showSongSummary = false
    public var aiTranslationMode: AITranslationMode = .refine
    public var targetLanguage: String = "en"

    private let lrcLib = LRCLibProvider()
    private let musixmatch = MusixmatchProvider()
    private let speechProvider = SpeechRecognitionProvider()
    private var cache: [String: [LyricLine]] = [:]
    private var enrichmentCache: [String: [Int: LineEnrichment]] = [:]
    private var enrichmentTask: Task<Void, Never>?
    private var summaryTask: Task<Void, Never>?
    private let enrichmentCoordinator = EnrichmentCoordinator()
    private let foundationModelProvider = FoundationModelProvider()
    private var fetchTask: Task<Void, any Error>?

    // MARK: - Disk Cache

    private nonisolated static let diskCacheDirectory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("SpotifyLyrics/lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private nonisolated func diskCacheURL(for key: String) -> URL {
        let safe = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        return Self.diskCacheDirectory.appendingPathComponent("\(safe).json")
    }

    private nonisolated func loadFromDisk(key: String) -> [LyricLine]? {
        let safe = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let url = caches.appendingPathComponent("SpotifyLyrics/lyrics/\(safe).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([LyricLine].self, from: data)
    }

    private nonisolated func saveToDisk(lines: [LyricLine], key: String) {
        let url = diskCacheURL(for: key)
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(lines) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    public init() {}

    public func fetchLyrics(for track: TrackInfo) {
        let key = track.cacheKey

        // Cancel any in-flight fetch and enrichment work
        fetchTask?.cancel()
        enrichmentTask?.cancel()
        enrichmentTask = nil
        summaryTask?.cancel()
        summaryTask = nil

        // L1: In-memory cache (synchronous, no race)
        if let cached = cache[key] {
            isLoading = false
            currentLines = cached
            hasLyrics = !cached.isEmpty
            currentLineIndex = 0
            startEnrichment(for: key)
            startSummary(track: track)
            return
        }

        // Reset state immediately for the new song
        isLoading = true
        currentLines = []
        enrichment = [:]
        songSummary = nil
        hasLyrics = false
        currentLineIndex = 0

        // Launch a cancellable fetch task
        fetchTask = Task { [weak self] in
            guard let self else { return }

            // L2: Disk cache
            if let diskCached = await Task.detached(priority: .userInitiated, operation: { [self] in
                self.loadFromDisk(key: key)
            }).value, !diskCached.isEmpty {
                try Task.checkCancellation()
                self.cache[key] = diskCached
                self.currentLines = diskCached
                self.hasLyrics = true
                self.isLoading = false
                self.currentLineIndex = 0
                self.startEnrichment(for: key)
                self.startSummary(track: track)
                return
            }

            try Task.checkCancellation()

            // Fetch from both providers in parallel
            let title = track.title
            let artist = track.artist

            let lines = await withTaskGroup(of: (source: String, lines: [LyricLine]?).self) { group -> [LyricLine]? in
                group.addTask { [lrcLib = self.lrcLib] in
                    let result = await lrcLib.fetchLyrics(title: title, artist: artist)
                    return ("lrclib", result)
                }
                group.addTask { [musixmatch = self.musixmatch] in
                    let result = await musixmatch.fetchLyrics(title: title, artist: artist)
                    return ("musixmatch", result)
                }

                var lrcLibResult: [LyricLine]?
                var musixmatchResult: [LyricLine]?

                for await result in group {
                    switch result.source {
                    case "lrclib":
                        lrcLibResult = result.lines
                    case "musixmatch":
                        musixmatchResult = result.lines
                    default: break
                    }
                }

                if let lines = lrcLibResult, !lines.isEmpty { return lines }
                if let lines = musixmatchResult, !lines.isEmpty { return lines }
                return nil
            }

            try Task.checkCancellation()

            if let lines {
                self.cache[key] = lines
                self.saveToDisk(lines: lines, key: key)
                self.currentLines = lines
                self.hasLyrics = true
                self.startEnrichment(for: key)
                self.startSummary(track: track)
            }

            self.isLoading = false
        }
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
            guard !Task.isCancelled else { return }
            cache[cacheKey] = lines
            currentLines = lines
            hasLyrics = true
            startEnrichment(for: cacheKey)
        }
        guard !Task.isCancelled else { return }
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
        let aiMode = aiTranslationMode

        // Check translation language availability
        if translate {
            Task { [weak self] in
                guard let self else { return }
                let notice = await self.enrichmentCoordinator.checkTranslationAvailability(
                    lines: lines, targetLanguage: target
                )
                self.translationNotice = notice
            }
        } else {
            translationNotice = nil
        }

        enrichmentTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.enrichmentCoordinator.enrich(
                lines: lines,
                romanize: romanize,
                translate: translate,
                targetLanguage: target,
                aiTranslationMode: aiMode,
                onRefinement: aiMode != .off ? { [weak self] refined in
                    guard let self, !Task.isCancelled else { return }
                    self.enrichmentCache[enrichKey] = refined
                    self.enrichment = refined
                } : nil
            )
            guard !Task.isCancelled else { return }
            self.enrichmentCache[enrichKey] = result
            self.enrichment = result
        }
    }

    private func startSummary(track: TrackInfo) {
        guard showSongSummary, !currentLines.isEmpty else {
            songSummary = nil
            return
        }

        let lines = currentLines.map(\.text)
        let title = track.title
        let artist = track.artist

        summaryTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.foundationModelProvider.summarizeLyrics(lines, title: title, artist: artist)
            guard !Task.isCancelled else { return }
            self.songSummary = result
        }
    }

    private func enrichmentCacheKey(for lyricsKey: String) -> String {
        "\(lyricsKey)|r:\(showRomanization)|t:\(showTranslation)|ai:\(aiTranslationMode.rawValue)|\(targetLanguage)"
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

    /// Update instrumental break state based on current playback position.
    /// Call this alongside `updateCurrentLine(at:)` from the polling loop.
    public func updateInstrumentalBreak(at position: TimeInterval) {
        guard !currentLines.isEmpty, currentLineIndex < currentLines.count else {
            if isInstrumentalBreak { isInstrumentalBreak = false }
            return
        }

        let currentLine = currentLines[currentLineIndex]
        let currentEnd = currentLine.endTime ?? (currentLineIndex + 1 < currentLines.count
            ? currentLines[currentLineIndex + 1].timestamp
            : currentLine.timestamp + 5)

        guard currentLineIndex + 1 < currentLines.count else {
            if isInstrumentalBreak { isInstrumentalBreak = false }
            return
        }

        let nextLine = currentLines[currentLineIndex + 1]
        let gap = nextLine.timestamp - currentEnd

        // Only consider it a break if gap exceeds threshold and we're past the current line's end
        if gap >= Self.instrumentalBreakThreshold && position >= currentEnd {
            let countdown = nextLine.timestamp - Self.breakDismissLeadTime - position
            if countdown > 0 {
                isInstrumentalBreak = true
                instrumentalBreakCountdown = countdown
                nextVocalLineText = nextLine.text
            } else {
                // Within lead time — dismiss break
                isInstrumentalBreak = false
                instrumentalBreakCountdown = 0
                nextVocalLineText = nil
            }
        } else {
            if isInstrumentalBreak {
                isInstrumentalBreak = false
                instrumentalBreakCountdown = 0
                nextVocalLineText = nil
            }
        }
    }

    public func clearCache() {
        cache.removeAll()
        enrichmentCache.removeAll()
        enrichment = [:]
        // Clear disk cache
        Task.detached(priority: .utility) {
            let dir = Self.diskCacheDirectory
            if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for file in files {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }
}
