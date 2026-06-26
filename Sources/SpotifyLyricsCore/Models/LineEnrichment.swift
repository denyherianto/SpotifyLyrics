import Foundation

public struct LineEnrichment: Equatable {
    public var romanization: String?
    public var translation: String?

    public init(romanization: String? = nil, translation: String? = nil) {
        self.romanization = romanization
        self.translation = translation
    }

    public var isEmpty: Bool {
        romanization == nil && translation == nil
    }
}
