import Foundation

public final class LRCLibProvider {
    struct SearchResult: Codable {
        let id: Int
        let trackName: String
        let artistName: String
        let albumName: String?
        let duration: Double?
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    public init() {}

    /// Fetch every usable lyrics candidate for a track, ranked best-first.
    ///
    /// Ranking: synced results before plain ones; within each group the result
    /// whose duration is closest to the playing track wins (when `trackDuration`
    /// is known), falling back to LRCLIB's own ordering.
    public func fetchOptions(
        title: String,
        artist: String,
        trackDuration: TimeInterval? = nil
    ) async -> [LyricsOption] {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]

        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("SpotifyLyrics/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return [] }

            let results = try JSONDecoder().decode([SearchResult].self, from: data)
            let options = results.compactMap(Self.makeOption)
            return Self.rank(options, trackDuration: trackDuration)
        } catch {
            // Cancellation is expected when the track changes mid-fetch — not an error.
            if (error as? URLError)?.code == .cancelled || error is CancellationError {
                return []
            }
            print("LRCLib error: \(error)")
            return []
        }
    }

    /// Convenience: the single best option's lines, or nil if none.
    public func fetchLyrics(title: String, artist: String) async -> [LyricLine]? {
        let options = await fetchOptions(title: title, artist: artist)
        return options.first?.lines
    }

    private static func makeOption(from r: SearchResult) -> LyricsOption? {
        // Prefer synced lyrics for this result.
        if let synced = r.syncedLyrics, !synced.isEmpty {
            let lines = LRCParser.parse(synced)
            if !lines.isEmpty {
                return LyricsOption(
                    id: r.id, trackName: r.trackName, artistName: r.artistName,
                    albumName: r.albumName, duration: r.duration,
                    isSynced: true, lines: lines
                )
            }
        }

        // Fall back to plain (unsynced) lyrics with evenly-spaced placeholder timing.
        if let plain = r.plainLyrics, !plain.isEmpty {
            let lines = plain.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .enumerated()
                .map { LyricLine(timestamp: Double($0.offset) * 4.0, text: $0.element) }
            if !lines.isEmpty {
                return LyricsOption(
                    id: r.id, trackName: r.trackName, artistName: r.artistName,
                    albumName: r.albumName, duration: r.duration,
                    isSynced: false, lines: lines
                )
            }
        }

        return nil
    }

    private static func rank(_ options: [LyricsOption], trackDuration: TimeInterval?) -> [LyricsOption] {
        options.enumerated().sorted { a, b in
            // Synced beats plain.
            if a.element.isSynced != b.element.isSynced { return a.element.isSynced }
            // Then closest duration to the playing track.
            if let target = trackDuration, target > 0 {
                let da = a.element.duration.map { abs($0 - target) } ?? .greatestFiniteMagnitude
                let db = b.element.duration.map { abs($0 - target) } ?? .greatestFiniteMagnitude
                if da != db { return da < db }
            }
            // Stable: preserve LRCLIB's ordering.
            return a.offset < b.offset
        }.map(\.element)
    }
}
