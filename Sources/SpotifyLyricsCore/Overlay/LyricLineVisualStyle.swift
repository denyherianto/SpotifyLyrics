public enum LyricLineVisualStyle {
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
