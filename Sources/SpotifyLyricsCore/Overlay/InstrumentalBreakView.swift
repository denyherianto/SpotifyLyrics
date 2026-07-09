import SwiftUI

/// Overlay view shown during instrumental breaks (gaps > 8s between lyric lines).
/// Displays a countdown to the next vocal line with a preview of the upcoming text.
public struct InstrumentalBreakView: View {
    @ObservedObject var lyricsManager: LyricsManager
    @ObservedObject var playerManager: SpotifyPlayerManager
    let showsUpcomingLinePreview: Bool

    public init(
        lyricsManager: LyricsManager,
        playerManager: SpotifyPlayerManager,
        showsUpcomingLinePreview: Bool = true
    ) {
        self.lyricsManager = lyricsManager
        self.playerManager = playerManager
        self.showsUpcomingLinePreview = showsUpcomingLinePreview
    }

    public var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // Musical note icon with render-server breathing (no per-frame main-thread cost).
            Image(systemName: "music.note")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
                .breathing(duration: 2.0, maxScale: 1.08, minOpacity: 0.6)

            // Countdown text
            Text(countdownText)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .contentTransition(.numericText())

            // Upcoming line preview
            if showsUpcomingLinePreview, let nextText = lyricsManager.nextVocalLineText {
                Text(nextText)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.25))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var countdownText: String {
        LyricLineVisualStyle.instrumentalCountdownText(seconds: lyricsManager.instrumentalBreakCountdown)
    }
}

/// Inline break indicator rendered in the lyrics list during full-overlay instrumental gaps.
public struct InlineInstrumentalBreakLineView: View {
    @ObservedObject var lyricsManager: LyricsManager

    public init(lyricsManager: LyricsManager) {
        self.lyricsManager = lyricsManager
    }

    public var body: some View {
        let countdownText = LyricLineVisualStyle.instrumentalCountdownText(seconds: lyricsManager.instrumentalBreakCountdown)
        HStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(0.72))
                .breathing(duration: 2.0, maxScale: 1.08, minOpacity: 0.6)

            if !countdownText.isEmpty {
                Text(countdownText)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .accessibilityLabel(accessibilityText(countdownText: countdownText))
    }

    private func accessibilityText(countdownText: String) -> String {
        if !countdownText.isEmpty {
            return "Instrumental break, \(countdownText) until next line"
        }
        return "Instrumental break"
    }
}

/// Compact break indicator for mini overlay mode.
public struct MiniInstrumentalBreakView: View {
    @ObservedObject var lyricsManager: LyricsManager

    public init(lyricsManager: LyricsManager) {
        self.lyricsManager = lyricsManager
    }

    public var body: some View {
        let countdownText = LyricLineVisualStyle.instrumentalCountdownText(seconds: lyricsManager.instrumentalBreakCountdown)
        HStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .breathing(duration: 1.5, maxScale: 1.0, minOpacity: 0.4)

            if !countdownText.isEmpty {
                Text(countdownText)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .contentTransition(.numericText())
            }
        }
    }
}
