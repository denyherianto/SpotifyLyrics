import Foundation

public final class LRCLibProvider {
    struct SearchResult: Codable {
        let id: Int
        let trackName: String
        let artistName: String
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    public init() {}

    public func fetchLyrics(title: String, artist: String) async -> [LyricLine]? {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]

        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("SpotifyLyrics/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            let results = try JSONDecoder().decode([SearchResult].self, from: data)

            // Prefer synced lyrics
            if let synced = results.first(where: { $0.syncedLyrics != nil })?.syncedLyrics {
                let lines = LRCParser.parse(synced)
                if !lines.isEmpty { return lines }
            }

            // Fall back to plain lyrics (unsynced)
            if let plain = results.first(where: { $0.plainLyrics != nil })?.plainLyrics {
                return plain.components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    .enumerated()
                    .map { LyricLine(timestamp: Double($0.offset) * 4.0, text: $0.element) }
            }

            return nil
        } catch {
            // Cancellation is expected when the track changes mid-fetch — not an error.
            if (error as? URLError)?.code == .cancelled || error is CancellationError {
                return nil
            }
            print("LRCLib error: \(error)")
            return nil
        }
    }
}
