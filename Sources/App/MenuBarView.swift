import SwiftUI
import SpotifyLyricsCore

struct MenuBarView: View {
    @EnvironmentObject var playerManager: SpotifyPlayerManager
    @EnvironmentObject var lyricsManager: LyricsManager
    @EnvironmentObject var overlayController: OverlayController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let track = playerManager.currentTrack {
                Text(track.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Divider().padding(.vertical, 4)
            } else {
                Text("No track playing")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Divider().padding(.vertical, 4)
            }

            Toggle("Show Lyrics", isOn: Binding(
                get: { overlayController.isVisible },
                set: { _ in overlayController.toggle() }
            ))

            Toggle("Always on Top", isOn: $overlayController.alwaysOnTop)

            Divider().padding(.vertical, 4)

            HStack {
                Text("Opacity")
                Slider(value: $overlayController.overlayOpacity, in: 0.3...1.0)
                    .frame(width: 120)
            }

            Divider().padding(.vertical, 4)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(8)
    }
}
