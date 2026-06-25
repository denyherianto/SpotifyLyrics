import SwiftUI
import AppKit

public enum ControlsStyle {
    case compact
    case full
}

private struct HoverableCircleButton: View {
    let size: CGFloat
    let isPressed: Bool
    let label: AnyView

    @State private var isHovered = false

    var body: some View {
        label
            .frame(width: size, height: size)
            .contentShape(Circle())
            .background(
                Circle().fill(.white.opacity(isHovered ? 0.15 : 0.001))
            )
            .scaleEffect(isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

struct ControlButtonStyle: ButtonStyle {
    let size: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        HoverableCircleButton(
            size: size,
            isPressed: configuration.isPressed,
            label: AnyView(configuration.label)
        )
    }
}

private struct HoverablePillButton: View {
    let isPressed: Bool
    let label: AnyView

    @State private var isHovered = false

    var body: some View {
        label
            .background(
                Capsule().fill(.white.opacity(isHovered ? 0.1 : 0))
                    .padding(.horizontal, -4)
                    .padding(.vertical, -2)
            )
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .opacity(isPressed ? 0.8 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverablePillButton(
            isPressed: configuration.isPressed,
            label: AnyView(configuration.label)
        )
    }
}

public struct MusicControlsView: View {
    @ObservedObject var playerManager: SpotifyPlayerManager

    let style: ControlsStyle
    let tint: Color

    public init(playerManager: SpotifyPlayerManager, style: ControlsStyle = .full, tint: Color = .white) {
        self.playerManager = playerManager
        self.style = style
        self.tint = tint
    }

    private var iconSize: CGFloat {
        style == .compact ? 14 : 18
    }

    private var playPauseSize: CGFloat {
        style == .compact ? 20 : 26
    }

    private var spacing: CGFloat {
        style == .compact ? 12 : 16
    }

    private var hitSize: CGFloat {
        style == .compact ? 30 : 36
    }

    public var body: some View {
        HStack(spacing: spacing) {
            // Shuffle
            Button { playerManager.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(playerManager.isShuffling ? .green : tint.opacity(0.7))
            }
            .buttonStyle(ControlButtonStyle(size: hitSize))

            // Previous
            Button { playerManager.previousTrack() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(tint)
            }
            .buttonStyle(ControlButtonStyle(size: hitSize))

            // Play / Pause
            Button { playerManager.playPause() } label: {
                Image(systemName: playerManager.playerState == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: playPauseSize, weight: .medium))
                    .foregroundStyle(tint)
            }
            .buttonStyle(ControlButtonStyle(size: hitSize + 4))

            // Next
            Button { playerManager.nextTrack() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(tint)
            }
            .buttonStyle(ControlButtonStyle(size: hitSize))

            // Repeat
            Button { playerManager.toggleRepeat() } label: {
                Image(systemName: "repeat")
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(playerManager.isRepeating ? .green : tint.opacity(0.7))
            }
            .buttonStyle(ControlButtonStyle(size: hitSize))
        }
    }
}
