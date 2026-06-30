import Foundation

/// One candidate lyrics result from LRCLIB for a given track.
///
/// A search usually returns several matches (different albums, versions, or
/// synced vs. plain). The provider ranks them best-first; the user can switch
/// between them from the menu bar. `id` is the stable LRCLIB result id, used
/// both for the picker selection and for persisting the user's choice.
public struct LyricsOption: Identifiable, Equatable, Codable {
    public let id: Int
    public let trackName: String
    public let artistName: String
    public let albumName: String?
    public let duration: TimeInterval?
    /// True when these lines carry real timestamps (synced), false for plain text.
    public let isSynced: Bool
    public let lines: [LyricLine]

    public init(
        id: Int,
        trackName: String,
        artistName: String,
        albumName: String?,
        duration: TimeInterval?,
        isSynced: Bool,
        lines: [LyricLine]
    ) {
        self.id = id
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
        self.duration = duration
        self.isSynced = isSynced
        self.lines = lines
    }

    /// Short label for the picker, e.g. "Synced · Album · 3:42".
    public var menuLabel: String {
        var parts: [String] = [isSynced ? "Synced" : "Plain"]
        if let albumName, !albumName.isEmpty { parts.append(albumName) }
        if let duration, duration > 0 { parts.append(Self.formatDuration(duration)) }
        return parts.joined(separator: " · ")
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
