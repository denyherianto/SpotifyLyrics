import AppIntents
import SpotifyLyricsCore

struct CurrentSongIntent: AppIntent {
    static var title: LocalizedStringResource = "What's Playing"
    static var description = IntentDescription("Returns the current track info and active lyric line.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let pm = AppState.shared.playerManager else {
            throw IntentError.appNotReady
        }

        guard let track = pm.currentTrack else {
            return .result(value: "Nothing is playing.")
        }

        var result = "\(track.title) by \(track.artist)"

        if let lm = AppState.shared.lyricsManager,
           lm.hasLyrics,
           lm.currentLineIndex < lm.currentLines.count {
            let line = lm.currentLines[lm.currentLineIndex]
            result += "\n\"\(line.text)\""
        }

        return .result(value: result)
    }
}
