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

    /// All lyrics candidates for the current track, ranked best-first.
    @Published public var lyricsOptions: [LyricsOption] = []
    /// The id of the option currently shown (matches one of `lyricsOptions`).
    @Published public var selectedOptionID: Int?

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
    private let speechProvider = SpeechRecognitionProvider()
    private var optionsCache: [String: [LyricsOption]] = [:]
    private var enrichmentCache: [String: [Int: LineEnrichment]] = [:]
    /// Cache key + track for the lyrics currently displayed (needed when switching source).
    private var currentKey: String?
    private var currentTrack: TrackInfo?
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

    private nonisolated func loadFromDisk(key: String) -> [LyricsOption]? {
        let safe = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let url = caches.appendingPathComponent("SpotifyLyrics/lyrics/\(safe).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([LyricsOption].self, from: data)
    }

    private nonisolated func saveToDisk(options: [LyricsOption], key: String) {
        let url = diskCacheURL(for: key)
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(options) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Per-track source selection (persisted)

    private nonisolated func selectionDefaultsKey(for key: String) -> String {
        let safe = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        return "lyricsSelection.\(safe)"
    }

    private func persistedSelection(for key: String) -> Int? {
        let dk = selectionDefaultsKey(for: key)
        guard UserDefaults.standard.object(forKey: dk) != nil else { return nil }
        return UserDefaults.standard.integer(forKey: dk)
    }

    private func persistSelection(_ id: Int, for key: String) {
        UserDefaults.standard.set(id, forKey: selectionDefaultsKey(for: key))
    }

    public init() {}

    public func fetchLyrics(for track: TrackInfo) {
        let key = track.cacheKey
        currentTrack = track

        // Cancel any in-flight fetch and enrichment work
        fetchTask?.cancel()
        enrichmentTask?.cancel()
        enrichmentTask = nil
        summaryTask?.cancel()
        summaryTask = nil

        // L1: In-memory cache (synchronous, no race)
        if let cached = optionsCache[key], !cached.isEmpty {
            isLoading = false
            applyOptions(cached, key: key, track: track)
            return
        }

        // Reset state immediately for the new song
        isLoading = true
        currentLines = []
        lyricsOptions = []
        selectedOptionID = nil
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
                self.optionsCache[key] = diskCached
                self.applyOptions(diskCached, key: key, track: track)
                self.isLoading = false
                return
            }

            try Task.checkCancellation()

            let options = await lrcLib.fetchOptions(
                title: track.title, artist: track.artist, trackDuration: track.duration
            )

            try Task.checkCancellation()

            if !options.isEmpty {
                self.optionsCache[key] = options
                self.saveToDisk(options: options, key: key)
                self.applyOptions(options, key: key, track: track)
            }

            self.isLoading = false
        }
    }

    /// Publish a freshly-fetched (or cached) option list and display the preferred one.
    private func applyOptions(_ options: [LyricsOption], key: String, track: TrackInfo) {
        lyricsOptions = options
        currentKey = key
        apply(preferredOption(in: options, key: key), key: key, track: track)
    }

    /// The option to show by default: the user's last choice for this track if it
    /// still exists, otherwise the top-ranked candidate.
    private func preferredOption(in options: [LyricsOption], key: String) -> LyricsOption {
        if let savedID = persistedSelection(for: key),
           let match = options.first(where: { $0.id == savedID }) {
            return match
        }
        return options[0]
    }

    /// Display a specific option and kick off enrichment/summary for it.
    private func apply(_ option: LyricsOption, key: String, track: TrackInfo) {
        selectedOptionID = option.id
        currentLines = option.lines
        hasLyrics = !option.lines.isEmpty
        currentLineIndex = 0
        startEnrichment(for: key)
        startSummary(track: track)
    }

    /// Switch the displayed lyrics to another candidate and remember the choice.
    public func selectOption(_ id: Int) {
        guard id != selectedOptionID,
              let key = currentKey,
              let track = currentTrack,
              let option = lyricsOptions.first(where: { $0.id == id }) else { return }

        enrichmentTask?.cancel()
        enrichmentTask = nil
        enrichment = [:]
        summaryTask?.cancel()
        summaryTask = nil

        persistSelection(id, for: key)
        apply(option, key: key, track: track)
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
            let option = LyricsOption(
                id: -1, trackName: "", artistName: "", albumName: nil,
                duration: nil, isSynced: true, lines: lines
            )
            optionsCache[cacheKey] = [option]
            lyricsOptions = [option]
            selectedOptionID = option.id
            currentKey = cacheKey
            currentLines = lines
            hasLyrics = true
            startEnrichment(for: cacheKey)
        }
        guard !Task.isCancelled else { return }
        isLoading = false
    }

    /// Re-run enrichment for the current lyrics (e.g. when settings change).
    public func refreshEnrichment() {
        guard hasLyrics, !currentLines.isEmpty, let key = currentKey else { return }
        // Cancel any in-flight enrichment
        enrichmentTask?.cancel()
        enrichmentTask = nil
        enrichment = [:]
        // Restart — the new enrichment cache key (which encodes current settings)
        // will naturally miss stale entries.
        startEnrichment(for: key)
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

    public func updateCurrentLine(at position: TimeInterval) {
        guard !currentLines.isEmpty else { return }

        // Incremental search from the current index. Normal playback advances by one line,
        // so this is O(1) per call instead of re-scanning from the start; seeks walk a few
        // steps either direction. (Called several times per second from the position timer.)
        var index = min(currentLineIndex, currentLines.count - 1)
        while index + 1 < currentLines.count && currentLines[index + 1].timestamp <= position {
            index += 1
        }
        while index > 0 && currentLines[index].timestamp > position {
            index -= 1
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
        optionsCache.removeAll()
        enrichmentCache.removeAll()
        enrichment = [:]
        lyricsOptions = []
        selectedOptionID = nil
        // Forget persisted per-track source selections.
        let defaults = UserDefaults.standard
        for dkey in defaults.dictionaryRepresentation().keys where dkey.hasPrefix("lyricsSelection.") {
            defaults.removeObject(forKey: dkey)
        }
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
