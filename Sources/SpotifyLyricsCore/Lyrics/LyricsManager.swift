import Foundation

@MainActor
public final class LyricsManager: ObservableObject {
    @Published public var currentLines: [LyricLine] = []
    @Published public var currentLineIndex: Int = 0
    @Published public var isLoading = false
    @Published public var hasLyrics = false

    private let lrcLib = LRCLibProvider()
    private let musixmatch = MusixmatchProvider()
    private var cache: [String: [LyricLine]] = [:]

    public init() {}

    public func fetchLyrics(for track: TrackInfo) async {
        let key = track.cacheKey

        if let cached = cache[key] {
            currentLines = cached
            hasLyrics = !cached.isEmpty
            currentLineIndex = 0
            return
        }

        isLoading = true
        currentLines = []
        hasLyrics = false
        currentLineIndex = 0

        // Try LRCLIB first
        if let lines = await lrcLib.fetchLyrics(title: track.title, artist: track.artist), !lines.isEmpty {
            cache[key] = lines
            currentLines = lines
            hasLyrics = true
            isLoading = false
            return
        }

        // Fallback to Musixmatch
        if let lines = await musixmatch.fetchLyrics(title: track.title, artist: track.artist), !lines.isEmpty {
            cache[key] = lines
            currentLines = lines
            hasLyrics = true
            isLoading = false
            return
        }

        isLoading = false
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
    }
}
