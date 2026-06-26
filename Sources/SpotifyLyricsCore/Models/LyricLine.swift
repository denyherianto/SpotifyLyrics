import Foundation

public struct LyricLine: Identifiable, Equatable {
    public let id = UUID()
    public let timestamp: TimeInterval
    public let text: String
    /// Per-word timings for karaoke fill, when available (enhanced-LRC / richsync).
    public let words: [LyricWord]?
    /// Absolute end time of this line, when known.
    public let endTime: TimeInterval?

    public init(timestamp: TimeInterval, text: String, words: [LyricWord]? = nil, endTime: TimeInterval? = nil) {
        self.timestamp = timestamp
        self.text = text
        self.words = words
        self.endTime = endTime
    }

    public static func == (lhs: LyricLine, rhs: LyricLine) -> Bool {
        lhs.timestamp == rhs.timestamp && lhs.text == rhs.text && lhs.words == rhs.words
    }

    /// 0…1 karaoke fill fraction at the given absolute playback position.
    ///
    /// When per-word timings exist the fill follows word boundaries (completed
    /// words fully filled, the in-progress word filled proportionally), measured
    /// by character count so the visual sweep matches the text width. Otherwise it
    /// interpolates linearly from this line's `timestamp` to `lineEnd`.
    public func fillFraction(at position: TimeInterval, lineEnd: TimeInterval) -> Double {
        if let words, !words.isEmpty {
            return wordFillFraction(at: position, words: words, lineEnd: lineEnd)
        }
        let end = endTime ?? lineEnd
        guard end > timestamp else { return position >= timestamp ? 1 : 0 }
        let raw = (position - timestamp) / (end - timestamp)
        return min(max(raw, 0), 1)
    }

    private func wordFillFraction(at position: TimeInterval, words: [LyricWord], lineEnd: TimeInterval) -> Double {
        let totalChars = words.reduce(0) { $0 + max($1.text.count, 1) }
        guard totalChars > 0 else { return 0 }

        var filledChars = 0.0
        for word in words {
            let count = Double(max(word.text.count, 1))
            // The last word's end is often unknown (inline tags); fall back to lineEnd.
            let effectiveEnd = word.end > word.start ? word.end : lineEnd
            if position >= effectiveEnd {
                filledChars += count
            } else if position <= word.start {
                break
            } else if effectiveEnd > word.start {
                let wordProgress = (position - word.start) / (effectiveEnd - word.start)
                filledChars += count * wordProgress
                break
            } else {
                filledChars += count
                break
            }
        }
        return min(max(filledChars / Double(totalChars), 0), 1)
    }
}
