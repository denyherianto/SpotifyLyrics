import Foundation

public struct EnrichmentCapabilities: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let romanization = EnrichmentCapabilities(rawValue: 1 << 0)
    public static let translation = EnrichmentCapabilities(rawValue: 1 << 1)
}

public protocol LyricsEnrichmentProvider: Sendable {
    var capabilities: EnrichmentCapabilities { get }
    func romanize(_ lines: [String], from sourceLanguage: String?) async throws -> [String?]
    func translate(_ lines: [String], to targetLanguage: String, from sourceLanguage: String?) async throws -> [String?]
}

extension LyricsEnrichmentProvider {
    public func romanize(_ lines: [String], from sourceLanguage: String?) async throws -> [String?] {
        Array(repeating: nil, count: lines.count)
    }

    public func translate(_ lines: [String], to targetLanguage: String, from sourceLanguage: String?) async throws -> [String?] {
        Array(repeating: nil, count: lines.count)
    }
}
