@testable import SpotifyLyricsCore

func testOverlayRecenterButtonPresentation() {
    print("--- Overlay Recenter Button Tests ---")

    do {
        check(!OverlayRecenterButtonPresentation.showsTitle(for: .squareAlbum), "Square Album recenter button is icon-only")
        checkEqual(OverlayRecenterButtonPresentation.accessibilityLabel, "Current", "icon-only button keeps accessible label")
        print("  ✓ Square Album recenter button is icon-only")
    }

    do {
        check(OverlayRecenterButtonPresentation.showsTitle(for: .small), "Small recenter button keeps title")
        check(OverlayRecenterButtonPresentation.showsTitle(for: .medium), "Medium recenter button keeps title")
        check(OverlayRecenterButtonPresentation.showsTitle(for: .large), "Large recenter button keeps title")
        print("  ✓ Full recenter buttons keep title")
    }
}
