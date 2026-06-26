import Foundation

public struct LRCParser {
    private static let lineTagPattern = try? NSRegularExpression(pattern: #"\[(\d{2}):(\d{2})\.(\d{2,3})\]"#)
    private static let wordTagPattern = try? NSRegularExpression(pattern: #"<(\d{2}):(\d{2})\.(\d{2,3})>"#)

    public static func parse(_ lrcString: String) -> [LyricLine] {
        guard let lineTagPattern, let wordTagPattern else { return [] }

        var lines: [LyricLine] = []

        for raw in lrcString.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let fullRange = NSRange(line.startIndex..., in: line)
            let tagMatches = lineTagPattern.matches(in: line, range: fullRange)
            guard !tagMatches.isEmpty else { continue }

            // Collect the run of contiguous leading `[mm:ss.xx]` timestamps.
            var timestamps: [TimeInterval] = []
            var contentStart = line.startIndex
            var expectedStart = line.startIndex
            for tag in tagMatches {
                guard let range = Range(tag.range, in: line), range.lowerBound == expectedStart else { break }
                timestamps.append(time(from: tag, in: line))
                expectedStart = range.upperBound
                contentStart = range.upperBound
            }
            guard !timestamps.isEmpty else { continue }

            let content = String(line[contentStart...])
            let (text, words) = parseWords(content, lineStart: timestamps[0], wordTagPattern: wordTagPattern)
            guard !text.isEmpty else { continue }

            for ts in timestamps {
                lines.append(LyricLine(timestamp: ts, text: text, words: words))
            }
        }

        return lines.sorted { $0.timestamp < $1.timestamp }
    }

    /// Parses inline enhanced-LRC word tags (`<mm:ss.xx>word`). Returns the plain
    /// line text and, when word tags are present, the per-word timings.
    private static func parseWords(_ content: String, lineStart: TimeInterval, wordTagPattern: NSRegularExpression) -> (text: String, words: [LyricWord]?) {
        let fullRange = NSRange(content.startIndex..., in: content)
        let tagMatches = wordTagPattern.matches(in: content, range: fullRange)

        guard !tagMatches.isEmpty else {
            return (content.trimmingCharacters(in: .whitespaces), nil)
        }

        var words: [LyricWord] = []

        // Any text before the first word tag belongs to the line start.
        if let firstRange = Range(tagMatches[0].range, in: content), firstRange.lowerBound != content.startIndex {
            let leading = String(content[content.startIndex..<firstRange.lowerBound])
            if !leading.trimmingCharacters(in: .whitespaces).isEmpty {
                let end = time(from: tagMatches[0], in: content)
                words.append(LyricWord(text: leading, start: lineStart, end: end))
            }
        }

        for (index, tag) in tagMatches.enumerated() {
            guard let tagRange = Range(tag.range, in: content) else { continue }
            let start = time(from: tag, in: content)
            let textStart = tagRange.upperBound
            let textEnd: String.Index
            let end: TimeInterval
            if index + 1 < tagMatches.count, let nextRange = Range(tagMatches[index + 1].range, in: content) {
                textEnd = nextRange.lowerBound
                end = time(from: tagMatches[index + 1], in: content)
            } else {
                textEnd = content.endIndex
                end = start // unknown; resolved against the line end at fill time
            }
            let wordText = String(content[textStart..<textEnd])
            if !wordText.trimmingCharacters(in: .whitespaces).isEmpty {
                words.append(LyricWord(text: wordText, start: start, end: end))
            }
        }

        let text = words.map(\.text).joined().trimmingCharacters(in: .whitespaces)
        return (text, words.isEmpty ? nil : words)
    }

    private static func time(from match: NSTextCheckingResult, in string: String) -> TimeInterval {
        guard match.numberOfRanges >= 4,
              let minRange = Range(match.range(at: 1), in: string),
              let secRange = Range(match.range(at: 2), in: string),
              let msRange = Range(match.range(at: 3), in: string) else { return 0 }

        let minutes = Double(string[minRange]) ?? 0
        let seconds = Double(string[secRange]) ?? 0
        let msString = String(string[msRange])
        let milliseconds = msString.count == 2 ? (Double(msString) ?? 0) * 10 : (Double(msString) ?? 0)
        return minutes * 60 + seconds + milliseconds / 1000
    }
}
