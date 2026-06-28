import SwiftUI

/// User-selectable animation style for the lyrics overlay.
public enum AnimationMode: String, CaseIterable {
    /// Japanese-karaoke style: the active line fills with color as it plays.
    case karaoke
    /// Polished default: gentle scale/opacity on the active line.
    case smooth
    /// Bouncy spring pop on the active line.
    case spring
    /// Calm pulsing glow on the active line.
    case glow

    public var displayName: String {
        switch self {
        case .karaoke: return "Karaoke"
        case .smooth:  return "Smooth"
        case .spring:  return "Spring"
        case .glow:    return "Glow"
        }
    }

    /// Animation used for active-state changes and auto-scroll transitions.
    public var transition: Animation {
        switch self {
        case .karaoke: return .spring(response: 0.45, dampingFraction: 0.82)
        case .smooth:  return .easeOut(duration: 0.3)
        case .spring:  return .spring(response: 0.35, dampingFraction: 0.65)
        case .glow:    return .easeOut(duration: 0.4)
        }
    }
}
