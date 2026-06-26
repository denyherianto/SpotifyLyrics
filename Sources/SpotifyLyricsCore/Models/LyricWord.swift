import Foundation

/// A single word (or syllable) with absolute start/end times, used for
/// word-level karaoke fill. Sourced from enhanced-LRC inline tags or
/// Musixmatch richsync when available.
public struct LyricWord: Equatable, Codable {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }
}
