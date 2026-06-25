import SwiftUI
import AppKit
import SpotifyLyricsCore

// Removes the default rounded corners from the MenuBarExtra window
private struct SquareCornersModifier: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.hasShadow = true
                // Remove the rounded corner mask on the visual effect view
                if let contentView = window.contentView?.superview {
                    contentView.wantsLayer = true
                    contentView.layer?.cornerRadius = 0
                    contentView.layer?.masksToBounds = true
                }
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct MenuBarView: View {
    @EnvironmentObject var playerManager: SpotifyPlayerManager
    @EnvironmentObject var lyricsManager: LyricsManager
    @EnvironmentObject var overlayController: OverlayController

    @StateObject private var colorExtractor = DominantColorExtractor()
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            miniPlayerSection
                .frame(width: 300, height: 300)
                .clipped()
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isHovering = hovering
                    }
                }

            Spacer().frame(height: 8)

            Divider()

            settingsSection
        }
        .frame(width: 300)
        .background(SquareCornersModifier())
        .onChange(of: playerManager.artworkURL) { url in
            colorExtractor.extractColor(from: url)
        }
        .onAppear {
            colorExtractor.extractColor(from: playerManager.artworkURL)
        }
    }

    // MARK: - Mini Player Section

    private var miniPlayerSection: some View {
        ZStack {
            if let track = playerManager.currentTrack {
                // Album art - always visible
                AsyncImage(url: playerManager.artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholder
                    case .empty:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
                .frame(width: 300, height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Hover overlay: blurred background + controls
                if isHovering {
                    // Blurred version of album art
                    AsyncImage(url: playerManager.artworkURL) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .blur(radius: 30)
                                .scaleEffect(1.3)
                        }
                    }
                    .frame(width: 300, height: 300)
                    .transition(.opacity)

                    // Dark overlay
                    Color.black.opacity(0.35)
                        .transition(.opacity)

                    // Controls
                    VStack(spacing: 0) {
                        Spacer()

                        // Artist name
                        Text(track.artist)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.5), radius: 4, y: 1)

                        Spacer().frame(height: 20)

                        // Large playback controls
                        HStack(spacing: 40) {
                            Button { playerManager.previousTrack() } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(colorExtractor.dominantColor)
                            }
                            .buttonStyle(.plain)

                            Button { playerManager.playPause() } label: {
                                ZStack {
                                    Circle()
                                        .fill(colorExtractor.dominantColor.opacity(0.85))
                                        .frame(width: 64, height: 64)
                                        .shadow(color: colorExtractor.dominantColor.opacity(0.3), radius: 10, y: 4)

                                    Image(systemName: playerManager.playerState == .playing ? "pause.fill" : "play.fill")
                                        .font(.system(size: 28, weight: .medium))
                                        .foregroundStyle(.white)
                                        .offset(x: playerManager.playerState == .playing ? 0 : 2)
                                }
                            }
                            .buttonStyle(.plain)

                            Button { playerManager.nextTrack() } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(colorExtractor.dominantColor)
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer().frame(height: 16)

                        // Song title
                        Text(track.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.5), radius: 4, y: 1)

                        Spacer()

                        // Seek bar
                        SeekBarView(playerManager: playerManager, showTotalDuration: true)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                    }
                    .transition(.opacity)
                }
            } else {
                placeholder
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

    private var placeholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.2), Color(white: 0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        VStack(spacing: 10) {
            // Toggles
            VStack(spacing: 6) {
                settingsRow("Show Lyrics") {
                    Toggle("", isOn: Binding(
                        get: { overlayController.isVisible },
                        set: { _ in overlayController.toggle() }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                }
                settingsRow("Always on Top") {
                    Toggle("", isOn: $overlayController.alwaysOnTop)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
            }

            Divider()

            // Opacity
            settingsRow("Opacity") {
                Slider(value: $overlayController.overlayOpacity, in: 0.3...1.0)
                    .controlSize(.small)
                    .frame(maxWidth: 120)
                Text("\(Int(overlayController.overlayOpacity * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }

            // Size
            settingsRow("Size") {
                Picker("", selection: $overlayController.overlaySize) {
                    ForEach(OverlaySize.allCases, id: \.self) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
            }

            Divider()

            // Quit
            HStack {
                Spacer()
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    HStack(spacing: 6) {
                        Text("Exit")
                            .font(.system(size: 12))
                        Image(systemName: "power")
                            .font(.system(size: 14))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func settingsRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            content()
        }
    }
}
