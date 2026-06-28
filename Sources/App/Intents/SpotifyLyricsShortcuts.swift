import AppIntents

struct SpotifyLyricsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowLyricsIntent(),
            phrases: [
                "Show lyrics in \(.applicationName)",
                "Toggle lyrics in \(.applicationName)",
                "Hide lyrics in \(.applicationName)",
            ],
            shortTitle: "Show Lyrics",
            systemImageName: "music.note.list"
        )
        AppShortcut(
            intent: CurrentSongIntent(),
            phrases: [
                "What song is playing in \(.applicationName)",
                "Current lyrics in \(.applicationName)",
            ],
            shortTitle: "What's Playing",
            systemImageName: "music.quarternote.3"
        )
        AppShortcut(
            intent: ToggleTranslationIntent(),
            phrases: [
                "Translate lyrics in \(.applicationName)",
            ],
            shortTitle: "Toggle Translation",
            systemImageName: "character.book.closed"
        )
    }
}
