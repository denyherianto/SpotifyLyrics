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
                    .foregroundStyle(.white.opacity(LyricLineVisualStyle.enrichmentOpacity(isActive: isActive)))
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
                    .foregroundStyle(.white.opacity(LyricLineVisualStyle.enrichmentOpacity(isActive: isActive)))
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.95)),
                        removal: .opacity
                    ))
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
        // Depth blur is applied innermost and its transaction animation is cleared, so changes
        // to the radius snap instantly. Animating a Gaussian blur radius is GPU-expensive and
        // stutters; several far lines crossing a blur threshold on every line change was a
        // major source of jank. Scale/opacity/offset below still animate with the spring.
        .blur(radius: lineBlur)
        .transaction { $0.animation = nil }
        .opacity(lineOpacity)
        .scaleEffect(scale)
        .offset(y: lineYOffset)
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

    /// A single, identity-stable view tree for every line in every mode. The active⇄inactive
    /// difference is expressed purely through animatable values (color, opacity, shadow, mask
    /// width) rather than swapping between different view types — swapping breaks SwiftUI
    /// identity and makes the line *pop* instead of transitioning.
    private var content: some View {
        let isGlowActive = isActive && mode == .glow
        let glowPulse = (sin(position * 3) + 1) / 2 // 0…1

        return baseText(textBaseColor)
            // Glow: a white halo that fades in/out via radius+opacity (0 when inactive).
            .shadow(
                color: .white.opacity(isGlowActive ? 0.25 + 0.45 * glowPulse : 0),
                radius: isGlowActive ? 3 + 9 * glowPulse : 0
            )
            // Karaoke fill: a bright copy revealed left-to-right. Present in every karaoke-mode
            // line (not just the active one) so activation animates the overlay's opacity
            // instead of inserting/removing a whole subtree.
            .overlay(alignment: .leading) {
                if mode == .karaoke {
                    let fraction = line.fillFraction(at: position, lineEnd: lineEnd)
                    baseText(.white)
                        .mask(alignment: .leading) {
                            GeometryReader { geo in
                                Rectangle().frame(width: geo.size.width * fraction)
                            }
                        }
                        .opacity(isActive ? 1 : 0)
                }
            }
    }

    private func baseText(_ color: Color) -> some View {
        Text(line.text)
            .font(.system(size: fontSize, weight: fontWeight, design: .rounded))
            .foregroundStyle(color)
            .shadow(color: .black.opacity(0.5), radius: isActive ? 4 : 2, x: 0, y: 1)
    }

    /// Base text color. Karaoke's active line is dimmed because its brightness comes from the
    /// fill overlay; every other case uses the standard foreground color.
    private var textBaseColor: Color {
        if isActive && mode == .karaoke { return .white }
        return foregroundColor
    }

    /// Constant font size — size differentiation is handled by animatable `scaleEffect`
    /// so transitions between active/inactive are smooth (font size changes can't animate).
    private var fontSize: CGFloat { 21 }

    /// Constant weight — weight changes can't animate and cause visible jumps.
    /// Opacity + scale provide sufficient visual distinction.
    private var fontWeight: Font.Weight { .semibold }

    private var enrichmentFontSize: CGFloat { 13 }

    private var scale: CGFloat {
        CGFloat(LyricLineVisualStyle.scale(isActive: isActive, mode: mode))
    }

    private var foregroundColor: Color {
        if isHovered && !isActive {
            return .white.opacity(0.9)
        }
        return .white.opacity(LyricLineVisualStyle.mainTextOpacity(isActive: isActive))
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
