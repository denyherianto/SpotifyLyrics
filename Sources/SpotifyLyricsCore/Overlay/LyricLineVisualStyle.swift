import Foundation

public enum LyricLineVisualStyle {
    public static func isLineActive(index: Int, activeIndex: Int, isInstrumentalBreak: Bool) -> Bool {
        !isInstrumentalBreak && index == activeIndex
    }

    public static func showsInlineInstrumentalBreak(index: Int, activeIndex: Int, isInstrumentalBreak: Bool) -> Bool {
        isInstrumentalBreak && index == activeIndex
    }

    public static func showsLyricLine(index: Int, activeIndex: Int, isInstrumentalBreak: Bool) -> Bool {
        true
    }

    public static func instrumentalCountdownText(seconds: Double) -> String {
        let totalSeconds = Int(ceil(seconds))
        guard totalSeconds > 0 else { return "" }
        return String(format: "-%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    public static func mainTextOpacity(isActive: Bool) -> Double {
        isActive ? 1.0 : 0.7
    }

    public static func enrichmentOpacity(isActive: Bool) -> Double {
        isActive ? 1.0 : 0.4
    }

    public static func scale(isActive: Bool, mode: AnimationMode) -> Double {
        if mode == .smooth {
            return isActive ? 1.14 : 0.88
        }
        guard isActive else { return 0.86 }
        return mode == .spring ? 1.28 : 1.22
    }
}
