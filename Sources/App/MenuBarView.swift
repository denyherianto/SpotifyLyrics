import SwiftUI
import SpotifyLyricsCore

struct MenuBarView: View {
    @EnvironmentObject var playerManager: SpotifyPlayerManager
    @EnvironmentObject var lyricsManager: LyricsManager
    @EnvironmentObject var overlayController: OverlayController

    var body: some View {
        VStack(spacing: 0) {
            // Album art + controls section
            albumArtSection
                .frame(height: 280)
                .clipped()

            Divider()

            // Settings section
            settingsSection
        }
        .frame(width: 300)
    }

    // MARK: - Album Art Section

    private var albumArtSection: some View {
        ZStack {
            if let track = playerManager.currentTrack {
                // Album artwork background
                AsyncImage(url: playerManager.artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        artPlaceholder
                    case .empty:
                        artPlaceholder
                            .overlay(ProgressView().tint(.white))
                    @unknown default:
                        artPlaceholder
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Gradient scrim at bottom for readability
                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 180)
                }

                // Track info + controls — always visible
                VStack(spacing: 8) {
                    Spacer()

                    Text(track.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)

                    Text(track.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)

                    Spacer().frame(height: 4)

                    MusicControlsView(playerManager: playerManager, style: .full)

                    SeekBarView(playerManager: playerManager)
                        .padding(.horizontal, 4)

                    Spacer().frame(height: 10)
                }
                .padding(.horizontal, 20)
            } else {
                // No track playing
                artPlaceholder
                VStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("No track playing")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    private var artPlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.15), Color(white: 0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle("Show Lyrics", isOn: Binding(
                get: { overlayController.isVisible },
                set: { _ in overlayController.toggle() }
            ))
            .padding(.vertical, 2)

            Toggle("Always on Top", isOn: $overlayController.alwaysOnTop)
                .padding(.vertical, 2)

            Divider().padding(.vertical, 4)

            HStack {
                Text("Opacity")
                Slider(value: $overlayController.overlayOpacity, in: 0.3...1.0)
                    .frame(width: 120)
            }

            Divider().padding(.vertical, 4)

            HStack {
                Text("Size")
                    .frame(width: 50, alignment: .leading)
                Picker("", selection: $overlayController.overlaySize) {
                    ForEach(OverlaySize.allCases, id: \.self) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
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
