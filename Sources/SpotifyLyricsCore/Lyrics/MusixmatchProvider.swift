import Foundation

public final class MusixmatchProvider {
    // Musixmatch requires an API key. Users can set this in UserDefaults.
    private var apiKey: String? {
        UserDefaults.standard.string(forKey: "musixmatchApiKey")
    }

    public init() {}

    public func fetchLyrics(title: String, artist: String) async -> [LyricLine]? {
        guard let apiKey, !apiKey.isEmpty else { return nil }

        // Prefer word-level richsync (requires a commercial key); fall back to plain.
        if let richsync = await fetchRichsync(title: title, artist: artist, apiKey: apiKey), !richsync.isEmpty {
            return richsync
        }
        return await fetchPlain(title: title, artist: artist, apiKey: apiKey)
    }

    // MARK: - Word-level richsync

    private func fetchRichsync(title: String, artist: String, apiKey: String) async -> [LyricLine]? {
        guard let trackId = await fetchTrackId(title: title, artist: artist, apiKey: apiKey) else { return nil }

        var components = URLComponents(string: "https://api.musixmatch.com/ws/1.1/track.richsync.get")!
        components.queryItems = [
            URLQueryItem(name: "track_id", value: trackId),
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let body = (json?["message"] as? [String: Any])?["body"] as? [String: Any]
            let richsync = body?["richsync"] as? [String: Any]
            guard let richsyncBody = richsync?["richsync_body"] as? String,
                  let bodyData = richsyncBody.data(using: .utf8) else { return nil }

            return parseRichsync(bodyData)
        } catch {
            print("Musixmatch richsync error: \(error)")
            return nil
        }
    }

    private func fetchTrackId(title: String, artist: String, apiKey: String) async -> String? {
        var components = URLComponents(string: "https://api.musixmatch.com/ws/1.1/matcher.track.get")!
        components.queryItems = [
            URLQueryItem(name: "q_track", value: title),
            URLQueryItem(name: "q_artist", value: artist),
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let body = (json?["message"] as? [String: Any])?["body"] as? [String: Any]
            let track = body?["track"] as? [String: Any]
            if let id = track?["track_id"] as? Int { return String(id) }
            return nil
        } catch {
            print("Musixmatch matcher.track error: \(error)")
            return nil
        }
    }

    /// Richsync body is a JSON array of line entries:
    /// `[{ "ts": <start>, "te": <end>, "x": <line text>, "l": [{ "c": <fragment>, "o": <offset from ts> }] }]`
    private func parseRichsync(_ data: Data) -> [LyricLine]? {
        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }

        var lines: [LyricLine] = []
        for entry in entries {
            guard let ts = (entry["ts"] as? NSNumber)?.doubleValue else { continue }
            let te = (entry["te"] as? NSNumber)?.doubleValue
            let lineText = (entry["x"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""

            var words: [LyricWord] = []
            if let fragments = entry["l"] as? [[String: Any]] {
                for (i, fragment) in fragments.enumerated() {
                    guard let text = fragment["c"] as? String,
                          let offset = (fragment["o"] as? NSNumber)?.doubleValue else { continue }
                    let start = ts + offset
                    let end: TimeInterval
                    if i + 1 < fragments.count, let nextOffset = (fragments[i + 1]["o"] as? NSNumber)?.doubleValue {
                        end = ts + nextOffset
                    } else {
                        end = te ?? start
                    }
                    if !text.isEmpty {
                        words.append(LyricWord(text: text, start: start, end: end))
                    }
                }
            }

            let text = lineText.isEmpty ? words.map(\.text).joined().trimmingCharacters(in: .whitespaces) : lineText
            guard !text.isEmpty else { continue }
            lines.append(LyricLine(timestamp: ts, text: text, words: words.isEmpty ? nil : words, endTime: te))
        }

        return lines.isEmpty ? nil : lines.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Plain (free tier) fallback

    private func fetchPlain(title: String, artist: String, apiKey: String) async -> [LyricLine]? {
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
