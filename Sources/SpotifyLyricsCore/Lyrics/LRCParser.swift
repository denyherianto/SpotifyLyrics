import Foundation

public struct LRCParser {
    public static func parse(_ lrcString: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let pattern = #"\[(\d{2}):(\d{2})\.(\d{2,3})\]\s*(.*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        for line in lrcString.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let range = NSRange(trimmed.startIndex..., in: trimmed)
            let matches = regex.matches(in: trimmed, range: range)

            for match in matches {
                guard match.numberOfRanges >= 5,
                      let minRange = Range(match.range(at: 1), in: trimmed),
                      let secRange = Range(match.range(at: 2), in: trimmed),
                      let msRange = Range(match.range(at: 3), in: trimmed),
                      let textRange = Range(match.range(at: 4), in: trimmed) else { continue }

                let minutes = Double(trimmed[minRange]) ?? 0
                let seconds = Double(trimmed[secRange]) ?? 0
                let msString = String(trimmed[msRange])
                let milliseconds: Double
                if msString.count == 2 {
                    milliseconds = (Double(msString) ?? 0) * 10
                } else {
                    milliseconds = Double(msString) ?? 0
                }

                let timestamp = minutes * 60 + seconds + milliseconds / 1000
                let text = String(trimmed[textRange]).trimmingCharacters(in: .whitespaces)

                if !text.isEmpty {
                    lines.append(LyricLine(timestamp: timestamp, text: text))
                }
            }
        }

        return lines.sorted { $0.timestamp < $1.timestamp }
    }
}
