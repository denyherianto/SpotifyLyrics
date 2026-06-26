import SwiftUI

public struct LyricLineView: View {
    public let line: LyricLine
    public let isActive: Bool
    public let offset: Int
    public let mode: AnimationMode
    /// Live playback position; only meaningful for the active line (karaoke/glow).
    public let position: TimeInterval
    /// Effective end time of this line, used for the karaoke sweep.
    public let lineEnd: TimeInterval
    /// Optional enrichment (romanization / translation) for this line.
    public let enrichment: LineEnrichment?

    public init(line: LyricLine, isActive: Bool, offset: Int, mode: AnimationMode, position: TimeInterval, lineEnd: TimeInterval, enrichment: LineEnrichment? = nil) {
        self.line = line
        self.isActive = isActive
        self.offset = offset
        self.mode = mode
        self.position = position
        self.lineEnd = lineEnd
        self.enrichment = enrichment
    }

    @State private var isHovered = false

    public var body: some View {
        VStack(spacing: 4) {
            if let rom = enrichment?.romanization {
                Text(rom)
                    .font(.system(size: enrichmentFontSize, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(isActive ? 0.6 : 0.4))
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                    .transition(.opacity)
            }

            content

            if let trans = enrichment?.translation {
                Text(trans)
                    .font(.system(size: enrichmentFontSize, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(isActive ? 0.55 : 0.35))
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                    .transition(.opacity)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
        .opacity(lineOpacity)
        .scaleEffect(scale)
        .padding(.vertical, enrichment != nil ? 6 : 2)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(isHovered ? 0.1 : 0))
        )
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .animation(mode.transition, value: isActive)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    @ViewBuilder
    private var content: some View {
        if isActive && mode == .karaoke {
            karaokeText
        } else if isActive && mode == .glow {
            glowText
        } else {
            baseText(foregroundColor)
        }
    }

    private func baseText(_ color: Color) -> some View {
        Text(line.text)
            .font(.system(size: fontSize, weight: isActive ? .bold : .regular, design: .rounded))
            .foregroundStyle(color)
            .shadow(color: .black.opacity(0.5), radius: isActive ? 4 : 2, x: 0, y: 1)
    }

    /// Japanese-karaoke fill: a dim base with a bright copy revealed left-to-right.
    private var karaokeText: some View {
        let fraction = line.fillFraction(at: position, lineEnd: lineEnd)
        return baseText(.white.opacity(0.4))
            .overlay(alignment: .leading) {
                baseText(.white)
                    .mask(alignment: .leading) {
                        GeometryReader { geo in
                            Rectangle().frame(width: geo.size.width * fraction)
                        }
                    }
            }
    }

    /// Calm pulsing glow driven by the playback position.
    private var glowText: some View {
        let pulse = (sin(position * 3) + 1) / 2 // 0…1
        return baseText(.white)
            .shadow(color: .white.opacity(0.25 + 0.45 * pulse), radius: 3 + 9 * pulse)
    }

    private var fontSize: CGFloat {
        isActive ? 24 : 18
    }

    private var enrichmentFontSize: CGFloat {
        isActive ? 14 : 12
    }

    private var scale: CGFloat {
        guard isActive else { return 0.95 }
        return mode == .spring ? 1.06 : 1.0
    }

    private var foregroundColor: Color {
        if isHovered && !isActive {
            return .white.opacity(0.9)
        }
        return isActive ? .white : .white.opacity(0.7)
    }

    private var lineOpacity: Double {
        if isHovered { return 1.0 }
        switch abs(offset) {
        case 0: return 1.0
        case 1: return 0.7
        case 2: return 0.5
        case 3: return 0.35
        default: return 0.25
        }
    }
}
