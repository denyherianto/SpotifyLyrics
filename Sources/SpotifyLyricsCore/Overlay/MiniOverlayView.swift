import SwiftUI
import AppKit

/// Single-line subtitle bar overlay showing only the current lyric with karaoke fill.
/// Minimal screen real estate alternative to the full lyrics overlay.
public struct MiniOverlayView: View {
    @ObservedObject var lyricsManager: LyricsManager
    @ObservedObject var playerManager: SpotifyPlayerManager
    @Binding var backgroundOpacity: Double
    @Binding var animationMode: AnimationMode
    var onSwitchToFull: (() -> Void)?
    var onClose: (() -> Void)?

    public init(
        lyricsManager: LyricsManager,
        playerManager: SpotifyPlayerManager,
        backgroundOpacity: Binding<Double> = .constant(0.85),
        animationMode: Binding<AnimationMode> = .constant(.karaoke),
        onSwitchToFull: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.lyricsManager = lyricsManager
        self.playerManager = playerManager
        self._backgroundOpacity = backgroundOpacity
        self._animationMode = animationMode
        self.onSwitchToFull = onSwitchToFull
        self.onClose = onClose
    }

    @State private var isHovered = false

    public var body: some View {
        ZStack {
            // Background pill
            Capsule()
                .fill(.ultraThinMaterial)
                .opacity(backgroundOpacity)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 2)

            if !playerManager.isSpotifyRunning {
                miniStatusText("Waiting for Spotify...")
            } else if lyricsManager.isLoading {
                miniStatusText("Loading lyrics...")
            } else if !lyricsManager.hasLyrics {
                miniStatusText("No lyrics available")
            } else {
                currentLineContent
            }

            // Hover controls
            if isHovered {
                HStack(spacing: 6) {
                    Spacer()

                    Button(action: { onSwitchToFull?() }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(.white.opacity(0.15)))
                    }
                    .buttonStyle(MiniButtonStyle())
                    .help("Switch to full overlay")

                    Button(action: { onClose?() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(.white.opacity(0.15)))
                    }
                    .buttonStyle(MiniButtonStyle())
                    .help("Hide overlay")
                }
                .padding(.trailing, 10)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onWindowHover { isHovered = $0 }
    }

    @ViewBuilder
    private var currentLineContent: some View {
        let lines = lyricsManager.currentLines
        let index = lyricsManager.currentLineIndex
        if index < lines.count {
            let line = lines[index]
            let enrichment = lyricsManager.enrichment[index]
            let hasEnrichment = enrichment?.isEmpty == false

            if hasEnrichment {
                miniEnrichedLine(line: line, enrichment: enrichment!)
            } else {
                miniLine(line: line)
            }
        }
    }

    /// Single line with karaoke fill, no enrichment
    @ViewBuilder
    private func miniLine(line: LyricLine) -> some View {
        let isKaraokeOrGlow = animationMode == .karaoke || animationMode == .glow
        if isKaraokeOrGlow {
            TimelineView(.animation) { _ in
                miniLyricText(line: line)
            }
        } else {
            miniLyricText(line: line)
        }
    }

    /// Single line with enrichment text stacked
    @ViewBuilder
    private func miniEnrichedLine(line: LyricLine, enrichment: LineEnrichment) -> some View {
        let isKaraokeOrGlow = animationMode == .karaoke || animationMode == .glow
        if isKaraokeOrGlow {
            TimelineView(.animation) { _ in
                VStack(spacing: 2) {
                    if let rom = enrichment.romanization {
                        Text(rom)
                            .font(.system(size: 10, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    miniLyricText(line: line)
                    if let trans = enrichment.translation {
                        Text(trans)
                            .font(.system(size: 10, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
        } else {
            VStack(spacing: 2) {
                if let rom = enrichment.romanization {
                    Text(rom)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
                miniLyricText(line: line)
                if let trans = enrichment.translation {
                    Text(trans)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
    }

    @ViewBuilder
    private func miniLyricText(line: LyricLine) -> some View {
        let lineEnd = effectiveLineEnd(for: lyricsManager.currentLineIndex)
        if animationMode == .karaoke {
            let fraction = line.fillFraction(at: playerManager.playbackPosition, lineEnd: lineEnd)
            baseText(line.text, color: .white.opacity(0.4))
                .overlay(alignment: .leading) {
                    baseText(line.text, color: .white)
                        .mask(alignment: .leading) {
                            GeometryReader { geo in
                                Rectangle().frame(width: geo.size.width * fraction)
                            }
                        }
                }
        } else if animationMode == .glow {
            let pulse = (sin(playerManager.playbackPosition * 3) + 1) / 2
            baseText(line.text, color: .white)
                .shadow(color: .white.opacity(0.25 + 0.45 * pulse), radius: 3 + 9 * pulse)
        } else {
            baseText(line.text, color: .white)
        }
    }

    private func baseText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .lineLimit(1)
            .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
    }

    private func miniStatusText(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.5))
    }

    private func effectiveLineEnd(for index: Int) -> TimeInterval {
        let lines = lyricsManager.currentLines
        guard index < lines.count else { return 0 }
        if let end = lines[index].endTime { return end }
        if index + 1 < lines.count { return lines[index + 1].timestamp }
        return lines[index].timestamp + 5
    }
}

// MARK: - Mini button style

private struct MiniButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
    }
}
