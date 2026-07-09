import SwiftUI
import AppKit
import SpotifyLyricsCore

// Keeps the popover window in sync with the SwiftUI drawer height.
private struct PopoverWindowModifier: NSViewRepresentable {
    let contentSize: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }

            window.hasShadow = true
            if window.contentView?.frame.size != contentSize {
                window.setContentSize(contentSize)
            }

            // Remove the rounded corner mask on the visual effect view.
            if let contentView = window.contentView?.superview {
                contentView.wantsLayer = true
                contentView.layer?.cornerRadius = 0
                contentView.layer?.masksToBounds = true
            }
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var playerManager: SpotifyPlayerManager
    @EnvironmentObject var lyricsManager: LyricsManager
    @EnvironmentObject var overlayController: OverlayController
    @EnvironmentObject var soundClassifier: SoundClassifier

    @StateObject private var colorExtractor = DominantColorExtractor()
    @State private var isHovering = false
    @State private var showClearCacheConfirmation = false
    @AppStorage("menuBarSettingsExpanded") private var isSettingsExpanded = false
    private let appVersionText = AppVersionDisplay.currentMarketingVersion()
    private let popupWidth: CGFloat = 300
    private let artworkSize: CGFloat = 300
    private let expandedSettingsHeight: CGFloat = 346
    private let collapsedPopupHeight: CGFloat = 374
    private let expandedPopupHeight: CGFloat = 728

    var body: some View {
        VStack(spacing: 0) {
            miniPlayerSection
                .frame(width: artworkSize, height: artworkSize)
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
        .frame(width: popupWidth, height: isSettingsExpanded ? expandedPopupHeight : collapsedPopupHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(
            PopoverWindowModifier(
                contentSize: CGSize(
                    width: popupWidth,
                    height: isSettingsExpanded ? expandedPopupHeight : collapsedPopupHeight
                )
            )
        )
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
                .frame(width: artworkSize, height: artworkSize)
                .clipped()

                LinearGradient(
                    colors: [
                        .black.opacity(0),
                        .black.opacity(isHovering ? 0.55 : 0.68)
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )

                trackCaption(track)

                if isHovering {
                    AsyncImage(url: playerManager.artworkURL) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .blur(radius: 30)
                                .scaleEffect(1.3)
                        }
                    }
                    .frame(width: artworkSize, height: artworkSize)
                    .transition(.opacity)

                    Color.black.opacity(0.42)
                        .transition(.opacity)

                    VStack(spacing: 0) {
                        Spacer()

                        Text(track.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.65), radius: 4, y: 1)
                            .padding(.horizontal, 22)

                        Text(track.artist)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.65), radius: 4, y: 1)
                            .padding(.horizontal, 22)
                            .padding(.top, 3)

                        Spacer().frame(height: 22)

                        HStack(spacing: 34) {
                            hoverPlaybackButton(
                                systemName: "backward.fill",
                                size: 18,
                                label: "Previous track",
                                action: playerManager.previousTrack
                            )

                            Button { playerManager.playPause() } label: {
                                ZStack {
                                    Circle()
                                        .fill(colorExtractor.dominantColor.opacity(0.9))
                                        .frame(width: 64, height: 64)
                                        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)

                                    Image(systemName: playerManager.playerState == .playing ? "pause.fill" : "play.fill")
                                        .font(.system(size: 27, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .offset(x: playerManager.playerState == .playing ? 0 : 2)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(playerManager.playerState == .playing ? "Pause" : "Play")
                            .help(playerManager.playerState == .playing ? "Pause" : "Play")

                            hoverPlaybackButton(
                                systemName: "forward.fill",
                                size: 18,
                                label: "Next track",
                                action: playerManager.nextTrack
                            )
                        }

                        Spacer()

                        SeekBarView(playerManager: playerManager, showTotalDuration: true)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 18)
                    }
                    .transition(.opacity)
                }
            } else {
                placeholder
                VStack(spacing: 10) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.white.opacity(0.42))
                    Text("No track playing")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                    Text("Open Spotify to control lyrics")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.42))
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("No track playing. Open Spotify to control lyrics.")
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
        VStack(spacing: 8) {
            if isSettingsExpanded {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 10) {
                        overlaySettingsGroup
                        lyricsSettingsGroup
                        enrichmentSettingsGroup
                        appSettingsGroup
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 2)
                }
                .frame(width: popupWidth, height: expandedSettingsHeight)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSettingsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12))
                        Image(systemName: "chevron.up")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(isSettingsExpanded ? 0 : 180))
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(isSettingsExpanded ? "Collapse settings" : "Expand settings")
                .help(isSettingsExpanded ? "Collapse settings" : "Expand settings")

                Spacer()

                Text(appVersionText)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .accessibilityLabel("App version \(appVersionText)")

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
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
                .accessibilityLabel("Quit SpotifyLyrics")
                .help("Quit SpotifyLyrics")
            }
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .confirmationDialog("Clear cached lyrics?", isPresented: $showClearCacheConfirmation) {
            Button("Clear Cache", role: .destructive) {
                lyricsManager.clearCache()
                if let track = playerManager.currentTrack {
                    lyricsManager.fetchLyrics(for: track)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Cached lyrics will be removed and the current track will be fetched again.")
        }
    }

    private func settingsRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            content()
        }
        .frame(minHeight: 26)
    }

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 2)

            VStack(spacing: 5) {
                content()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.42))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
        }
    }

    private var overlaySettingsGroup: some View {
        settingsGroup("Overlay") {
            settingsRow("Show Lyrics") {
                Toggle("", isOn: Binding(
                    get: { overlayController.isVisible },
                    set: { _ in overlayController.toggle() }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel("Show Lyrics")
                .help("Show or hide the lyrics overlay")
            }

            settingsRow("Always on Top") {
                Toggle("", isOn: $overlayController.alwaysOnTop)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityLabel("Always on Top")
                    .help("Keep the lyrics overlay above other windows")
            }

            settingsRow("Opacity") {
                HStack(spacing: 8) {
                    Slider(value: $overlayController.overlayOpacity, in: 0.3...1.0)
                        .controlSize(.small)
                        .frame(width: 112)
                        .onChange(of: overlayController.overlayOpacity) { _ in
                            overlayController.commitOpacity()
                        }
                        .accessibilityLabel("Overlay opacity")

                    Text("\(Int(overlayController.overlayOpacity * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                        .accessibilityHidden(true)
                }
            }

            settingsRow("Size") {
                Picker("", selection: $overlayController.overlaySize) {
                    ForEach(OverlaySize.allCases, id: \.self) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 128, alignment: .trailing)
                .accessibilityLabel("Overlay size")
            }

            settingsRow("Animation") {
                Picker("", selection: $overlayController.animationMode) {
                    ForEach(AnimationMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 128, alignment: .trailing)
                .accessibilityLabel("Animation")
            }
        }
    }

    private var lyricsSettingsGroup: some View {
        settingsGroup("Lyrics") {
            if lyricsManager.lyricsOptions.count > 1 {
                settingsRow("Source") {
                    Picker("", selection: Binding(
                        get: {
                            lyricsManager.selectedOptionID
                                ?? lyricsManager.lyricsOptions.first?.id
                                ?? -1
                        },
                        set: { lyricsManager.selectOption($0) }
                    )) {
                        ForEach(lyricsManager.lyricsOptions) { option in
                            Text(option.menuLabel)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .tag(option.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 148, alignment: .trailing)
                    .accessibilityLabel("Lyrics source")
                }
            }

            settingsRow("Translation") {
                Toggle("", isOn: $overlayController.showTranslation)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityLabel("Translation")
                    .help("Show translated lyrics")
            }

            if overlayController.showTranslation {
                settingsRow("Language") {
                    Picker("", selection: $overlayController.targetLanguage) {
                        ForEach(TranslationLanguage.allCases, id: \.self) { lang in
                            Text(lang.displayName)
                                .lineLimit(1)
                                .tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 128, alignment: .trailing)
                    .accessibilityLabel("Translation language")
                }

                if let notice = lyricsManager.translationNotice {
                    noticeRow(systemName: "exclamationmark.triangle", tint: .orange, text: notice)
                }
            }
        }
    }

    private var enrichmentSettingsGroup: some View {
        settingsGroup("Enrichment") {
            settingsRow("Romanization") {
                Toggle("", isOn: $overlayController.showRomanization)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityLabel("Romanization")
                    .help("Show romanized lyrics where available")
            }

            if AITranslationMode.isAIAvailable {
                settingsRow("AI Summary") {
                    Toggle("", isOn: $overlayController.showSongSummary)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        .accessibilityLabel("AI Summary")
                        .help("Show the song summary when available")
                }

                if overlayController.showTranslation {
                    settingsRow("AI Translation") {
                        Picker("", selection: $overlayController.aiTranslationMode) {
                            ForEach(AITranslationMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: 128, alignment: .trailing)
                        .accessibilityLabel("AI Translation mode")
                        .help(
                            "Primary: AI translates directly. Refine: standard translation first, then AI improves it. Off: standard translation only."
                        )
                    }
                }
            } else {
                noticeRow(
                    systemName: "info.circle",
                    tint: .secondary,
                    text: "AI features require Apple Intelligence. Enable it in Settings > Apple Intelligence & Siri."
                )
            }

            if soundClassifier.currentMood != .unknown {
                settingsRow("Mood") {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(
                                Color(
                                    hue: soundClassifier.currentMood.themeHue,
                                    saturation: 0.7,
                                    brightness: 0.9
                                )
                            )
                            .frame(width: 8, height: 8)
                        Text(soundClassifier.currentMood.rawValue.capitalized)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Mood \(soundClassifier.currentMood.rawValue.capitalized)")
                }
            }
        }
    }

    private var appSettingsGroup: some View {
        settingsGroup("App") {
            settingsRow("Lyrics Cache") {
                Button(role: .destructive) {
                    showClearCacheConfirmation = true
                } label: {
                    Label("Clear", systemImage: "trash")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Clear lyrics cache")
                .help("Clear cached lyrics and refetch the current track")
            }
        }
    }

    private func trackCaption(_ track: TrackInfo) -> some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
            .shadow(color: .black.opacity(0.7), radius: 4, y: 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 15)
            .opacity(isHovering ? 0 : 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.title) by \(track.artist)")
    }

    private func hoverPlaybackButton(
        systemName: String,
        size: CGFloat,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 42, height: 42)
                .background(Circle().fill(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    private func noticeRow(systemName: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(tint)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

}
