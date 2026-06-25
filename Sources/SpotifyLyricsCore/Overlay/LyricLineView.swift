import SwiftUI

public struct LyricLineView: View {
    public let text: String
    public let isActive: Bool
    public let offset: Int

    public init(text: String, isActive: Bool, offset: Int) {
        self.text = text
        self.isActive = isActive
        self.offset = offset
    }

    @State private var isHovered = false

    public var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: isActive ? .bold : .regular, design: .rounded))
            .foregroundStyle(foregroundColor)
            .opacity(lineOpacity)
            .scaleEffect(isActive ? 1.0 : 0.95)
            .shadow(color: .black.opacity(0.5), radius: isActive ? 4 : 2, x: 0, y: 1)
            .padding(.vertical, 2)
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
            .animation(.easeInOut(duration: 0.3), value: isActive)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private var fontSize: CGFloat {
        isActive ? 24 : 18
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
