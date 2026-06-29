import Foundation

public struct TrackInfo: Equatable, Sendable {
    public let title: String
    public let artist: String
    public let album: String
    public let duration: TimeInterval

    public var cacheKey: String {
        "\(artist.lowercased())|\(title.lowercased())"
    }

    public init(title: String, artist: String, album: String, duration: TimeInterval) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }
}
