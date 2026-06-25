import Foundation

public struct LyricLine: Identifiable, Equatable {
    public let id = UUID()
    public let timestamp: TimeInterval
    public let text: String

    public init(timestamp: TimeInterval, text: String) {
        self.timestamp = timestamp
        self.text = text
    }

    public static func == (lhs: LyricLine, rhs: LyricLine) -> Bool {
        lhs.timestamp == rhs.timestamp && lhs.text == rhs.text
    }
}
