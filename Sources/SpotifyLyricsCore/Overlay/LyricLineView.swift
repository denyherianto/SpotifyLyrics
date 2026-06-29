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
    /// Callback for "Share as Card" context menu action.
    public var onShareAsCard: ((LyricLine, LineEnrichment?) -> Void)?

    public init(line: LyricLine, isActive: Bool, offset: Int, mode: AnimationMode, position: TimeInterval, lineEnd: TimeInterval, enrichment: LineEnrichment? = nil, onShareAsCard: ((LyricLine, LineEnrichment?) -> Void)? = nil) {
        self.line = line
        self.isActive = isActive
        self.offset = offset
        self.mode = mode
        self.position = position
        self.lineEnd = lineEnd
        self.enrichment = enrichment
        self.onShareAsCard = onShareAsCard
    }

    @State private var isHovered = false

    public var body: some View {
        VStack(spacing: 4) {
            if let rom = enrichment?.romanization {
                Text(rom)
                    .font(.system(size: enrichmentFontSize, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(isActive ? 0.6 : 0.4))
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.95)),
                        removal: .opacity
                    ))
            }

            content

            if let trans = enrichment?.translation {
                Text(trans)
                    .font(.system(size: enrichmentFontSize, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(isActive ? 0.55 : 0.35))
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.95)),
                        removal: .opacity
                    ))
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
        .opacity(lineOpacity)
        .scaleEffect(scale)
        .blur(radius: lineBlur)
        .offset(y: lineYOffset)
        .animation(mode.transition, value: isActive)
        .animation(mode.transition, value: offset)
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
        .contextMenu {
            Button("Share as Card") {
                onShareAsCard?(line, enrichment)
            }
            Button("Copy Line") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(line.text, forType: .string)
            }
        }
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
            .font(.system(size: fontSize, weight: fontWeight, design: .rounded))
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
        if mode == .smooth {
            return 22
        }
        return isActive ? 24 : 18
    }

    private var fontWeight: Font.Weight {
        if mode == .smooth {
            return .semibold
        }
        return isActive ? .bold : .regular
    }

    private var enrichmentFontSize: CGFloat {
        if mode == .smooth {
            return 13
        }
        return isActive ? 14 : 12
    }

    private var scale: CGFloat {
        if mode == .smooth {
            return isActive ? 1.03 : 0.92
        }
        guard isActive else { return 0.97 }
        return mode == .spring ? 1.04 : 1.0
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
        case 1: return 0.75
        case 2: return 0.55
        case 3: return 0.4
        default: return 0.3
        }
    }

    /// Depth-of-field blur for distant lines (disabled for smooth mode — too expensive to animate)
    private var lineBlur: CGFloat {
        if mode == .smooth { return 0 }
        if isHovered { return 0 }
        switch abs(offset) {
        case 0...2: return 0
        case 3: return 1.0
        case 4: return 2.0
        default: return 3.0
        }
    }

    /// Subtle vertical offset for inactive lines, creating a parallax feel
    private var lineYOffset: CGFloat {
        guard !isActive else { return 0 }
        let direction: CGFloat = offset > 0 ? 1 : -1
        let distance = min(abs(offset), 5)
        return direction * CGFloat(distance) * 0.5
    }
}
