import SwiftUI
import AppKit

public struct SeekBarView: View {
    @ObservedObject var playerManager: SpotifyPlayerManager

    let tint: Color
    let showTotalDuration: Bool

    @State private var isDragging = false
    @State private var dragProgress: Double = 0

    public init(playerManager: SpotifyPlayerManager, tint: Color = .white, showTotalDuration: Bool = false) {
        self.playerManager = playerManager
        self.tint = tint
        self.showTotalDuration = showTotalDuration
    }

    private var duration: TimeInterval {
        playerManager.currentTrack?.duration ?? 0
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            content
        }
    }

    private var content: some View {
        let position = isDragging ? dragProgress * duration : playerManager.playbackPosition
        let progress = duration > 0 ? (isDragging ? dragProgress : playerManager.playbackPosition / duration) : 0

        return VStack(spacing: 4) {
            // Track bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(tint.opacity(0.2))
                        .frame(height: 4)

                    // Filled track
                    Capsule()
                        .fill(tint.opacity(0.8))
                        .frame(width: max(0, geo.size.width * min(1, progress)), height: 4)
                }
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            dragProgress = max(0, min(1, value.location.x / geo.size.width))
                        }
                        .onEnded { value in
                            let finalProgress = max(0, min(1, value.location.x / geo.size.width))
                            let seekPosition = finalProgress * duration
                            playerManager.seekTo(seekPosition)
                            isDragging = false
                        }
                )
            }
            .frame(height: 4)

            // Time labels
            HStack {
                Text(formatTime(position))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(tint.opacity(0.7))
                Spacer()
                Text(showTotalDuration ? formatTime(duration) : "-\(formatTime(max(0, duration - position)))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(tint.opacity(0.7))
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
