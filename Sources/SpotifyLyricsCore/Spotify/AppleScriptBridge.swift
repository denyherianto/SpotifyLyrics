import Foundation
import AppKit

/// Stateless bridge to Spotify via AppleScript. Holds no mutable state, so it is safe to
/// invoke from any thread — callers run `getPlaybackInfo()` off the main thread to avoid
/// blocking SwiftUI rendering while the (slow) Apple-event round-trip completes.
public final class AppleScriptBridge: @unchecked Sendable {
    public enum PlayerState: String, Sendable {
        case playing, paused, stopped, unknown
    }

    public struct PlaybackInfo: Sendable {
        public let track: TrackInfo
        public let state: PlayerState
        public let position: TimeInterval
        public let artworkURLString: String?
        public let isShuffling: Bool
        public let isRepeating: Bool

        public init(track: TrackInfo, state: PlayerState, position: TimeInterval,
                     artworkURLString: String? = nil, isShuffling: Bool = false, isRepeating: Bool = false) {
            self.track = track
            self.state = state
            self.position = position
            self.artworkURLString = artworkURLString
            self.isShuffling = isShuffling
            self.isRepeating = isRepeating
        }
    }

    public init() {}

    /// Cheap, in-process check (no Apple event) for whether Spotify is running.
    public static var isSpotifyRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.spotify.client"
        }
    }

    public func getPlaybackInfo() -> PlaybackInfo? {
        // Skip the AppleScript entirely when Spotify isn't running. This avoids both the
        // Apple-event round-trip and any chance of launching Spotify, and is essentially free
        // compared to the old `tell System Events ... exists process` probe.
        guard Self.isSpotifyRunning else { return nil }

        // Single combined script reads everything in one round-trip.
        let script = """
        tell application "Spotify"
            if player state is stopped then
                return "stopped|||||||0|||0"
            end if
            set trackName to name of current track
            set trackArtist to artist of current track
            set trackAlbum to album of current track
            set trackDuration to duration of current track
            set playerPos to player position
            set pState to player state as string
            set artUrl to artwork url of current track
            set shuf to shuffling
            set rep to repeating
            return trackName & "|||" & trackArtist & "|||" & trackAlbum & "|||" & (trackDuration / 1000) & "|||" & playerPos & "|||" & pState & "|||" & artUrl & "|||" & shuf & "|||" & rep
        end tell
        """

        guard let result = runAppleScript(script) else { return nil }
        let parts = result.components(separatedBy: "|||")
        guard parts.count >= 6 else { return nil }

        let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let album = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        // AppleScript coerces numbers using system locale — comma decimal separators
        // (e.g. "120,5" instead of "120.5") cause TimeInterval() to return nil.
        let duration = Self.parseNumber(parts[3])
        let position = Self.parseNumber(parts[4])
        let stateStr = parts[5].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if stateStr == "stopped" && title.isEmpty {
            return PlaybackInfo(
                track: TrackInfo(title: "", artist: "", album: "", duration: 0),
                state: .stopped,
                position: 0
            )
        }

        let state: PlayerState = switch stateStr {
        case "playing", "kpsplaying": .playing
        case "paused", "kpsppaused": .paused
        case "stopped", "kpspstopped": .stopped
        default: .unknown
        }

        var artworkURLString: String? = nil
        var isShuffling = false
        var isRepeating = false

        if parts.count >= 7 {
            let url = parts[6].trimmingCharacters(in: .whitespacesAndNewlines)
            if !url.isEmpty { artworkURLString = url }
        }
        if parts.count >= 8 {
            isShuffling = parts[7].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
        }
        if parts.count >= 9 {
            isRepeating = parts[8].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
        }

        return PlaybackInfo(
            track: TrackInfo(title: title, artist: artist, album: album, duration: duration),
            state: state,
            position: position,
            artworkURLString: artworkURLString,
            isShuffling: isShuffling,
            isRepeating: isRepeating
        )
    }

    public func playPause() {
        _ = runAppleScript("tell application \"Spotify\" to playpause")
    }

    public func nextTrack() {
        _ = runAppleScript("tell application \"Spotify\" to next track")
    }

    public func previousTrack() {
        _ = runAppleScript("tell application \"Spotify\" to previous track")
    }

    public func setShuffling(_ enabled: Bool) {
        _ = runAppleScript("tell application \"Spotify\" to set shuffling to \(enabled)")
    }

    public func setRepeating(_ enabled: Bool) {
        _ = runAppleScript("tell application \"Spotify\" to set repeating to \(enabled)")
    }

    public func seekTo(_ position: TimeInterval) {
        let script = """
        tell application "Spotify"
            set player position to \(position)
        end tell
        """
        _ = runAppleScript(script)
    }

    public static func parseNumber(_ raw: String) -> TimeInterval {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return TimeInterval(cleaned) ?? 0
    }

    private func runAppleScript(_ source: String) -> String? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        if error != nil { return nil }
        return result?.stringValue
    }
}
