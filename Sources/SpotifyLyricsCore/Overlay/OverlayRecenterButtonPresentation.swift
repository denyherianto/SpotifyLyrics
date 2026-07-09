public enum OverlayRecenterButtonPresentation {
    public static let accessibilityLabel = "Current"

    public static func showsTitle(for overlaySize: OverlaySize) -> Bool {
        overlaySize != .squareAlbum
    }
}
