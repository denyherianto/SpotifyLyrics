import CoreGraphics

public enum OverlaySize: String, CaseIterable {
    case mini, small, medium, large, squareAlbum

    public var dimensions: (width: CGFloat, height: CGFloat) {
        switch self {
        case .mini:   return (600, 48)
        case .small:  return (500, 200)
        case .medium: return (700, 260)
        case .large:  return (900, 360)
        case .squareAlbum: return (360, 360)
        }
    }

    public var displayName: String {
        switch self {
        case .mini:   return "Mini"
        case .small:  return "Small"
        case .medium: return "Medium"
        case .large:  return "Large"
        case .squareAlbum: return "Square Album"
        }
    }

    public var isMini: Bool { self == .mini }

    public var frameAutosaveName: String {
        switch self {
        case .mini: return "LyricsOverlayMini"
        case .squareAlbum: return "LyricsOverlaySquareAlbum"
        case .small, .medium, .large: return "LyricsOverlay"
        }
    }
}
