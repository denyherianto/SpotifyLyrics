import Foundation

public final class MusixmatchProvider {
    // Musixmatch requires an API key. Users can set this in UserDefaults.
    private var apiKey: String? {
        UserDefaults.standard.string(forKey: "musixmatchApiKey")
    }

    public init() {}

    public func fetchLyrics(title: String, artist: String) async -> [LyricLine]? {
        guard let apiKey, !apiKey.isEmpty else { return nil }

        var components = URLComponents(string: "https://api.musixmatch.com/ws/1.1/matcher.lyrics.get")!
        components.queryItems = [
            URLQueryItem(name: "q_track", value: title),
            URLQueryItem(name: "q_artist", value: artist),
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "format", value: "json")
        ]

        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = json?["message"] as? [String: Any]
            let body = message?["body"] as? [String: Any]
            let lyrics = body?["lyrics"] as? [String: Any]
            let lyricsBody = lyrics?["lyrics_body"] as? String

            guard let text = lyricsBody, !text.isEmpty else { return nil }

            // Musixmatch free tier returns plain text, not synced
            return text.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .filter { !$0.contains("******* This Lyrics is NOT") } // Remove watermark
                .enumerated()
                .map { LyricLine(timestamp: Double($0.offset) * 4.0, text: $0.element) }
        } catch {
            print("Musixmatch error: \(error)")
            return nil
        }
    }
}
