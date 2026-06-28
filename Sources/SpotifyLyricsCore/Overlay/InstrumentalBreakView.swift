import SwiftUI

/// Overlay view shown during instrumental breaks (gaps > 8s between lyric lines).
/// Displays a countdown to the next vocal line with a preview of the upcoming text.
public struct InstrumentalBreakView: View {
    @ObservedObject var lyricsManager: LyricsManager
    @ObservedObject var playerManager: SpotifyPlayerManager

    public init(lyricsManager: LyricsManager, playerManager: SpotifyPlayerManager) {
        self.lyricsManager = lyricsManager
        self.playerManager = playerManager
    }

    public var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // Musical note icon with breathing animation
            TimelineView(.animation) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate
                let scale = 1.0 + 0.08 * sin(phase * 1.5)
                let opacity = 0.4 + 0.2 * sin(phase * 1.5)

                Image(systemName: "music.note")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.white.opacity(opacity))
                    .scaleEffect(scale)
            }

            // Countdown text
            Text(countdownText)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .contentTransition(.numericText())

            // Upcoming line preview
            if let nextText = lyricsManager.nextVocalLineText {
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
        let seconds = Int(ceil(lyricsManager.instrumentalBreakCountdown))
        if seconds <= 0 { return "" }
        return "Next line in \(seconds)s..."
    }
}

/// Compact break indicator for mini overlay mode.
public struct MiniInstrumentalBreakView: View {
    @ObservedObject var lyricsManager: LyricsManager

    public init(lyricsManager: LyricsManager) {
        self.lyricsManager = lyricsManager
    }

    public var body: some View {
        let seconds = Int(ceil(lyricsManager.instrumentalBreakCountdown))
        HStack(spacing: 6) {
            TimelineView(.animation) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate
                let opacity = 0.4 + 0.3 * sin(phase * 2.0)

                Image(systemName: "music.note")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(opacity))
            }

            if seconds > 0 {
                Text("\(seconds)s")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .contentTransition(.numericText())
            }
        }
    }
}
