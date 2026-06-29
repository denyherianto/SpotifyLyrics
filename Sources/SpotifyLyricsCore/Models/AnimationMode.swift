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
    /// Snappy response with moderate damping — fast enough to feel responsive, damped enough
    /// to settle cleanly. (Very long response + very high damping reads as "stiff/laggy".)
    public var transition: Animation {
        switch self {
        case .karaoke: return .spring(response: 0.40, dampingFraction: 0.82)
        case .smooth:  return .spring(response: 0.38, dampingFraction: 0.85)
        case .spring:  return .spring(response: 0.42, dampingFraction: 0.68)
        case .glow:    return .easeInOut(duration: 0.35)
        }
    }
}
