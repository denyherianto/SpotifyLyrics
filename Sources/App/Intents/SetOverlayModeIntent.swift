import AppIntents
import SpotifyLyricsCore

/// AppEnum wrapper for OverlaySize.
enum OverlaySizeEnum: String, AppEnum {
    case mini, small, medium, large, squareAlbum

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Overlay Size")
    static var caseDisplayRepresentations: [OverlaySizeEnum: DisplayRepresentation] = [
        .mini: "Mini",
        .small: "Small",
        .medium: "Medium",
        .large: "Large",
        .squareAlbum: "Square Album",
    ]

    var toOverlaySize: OverlaySize {
        OverlaySize(rawValue: rawValue) ?? .medium
    }
}

/// AppEnum wrapper for AnimationMode.
enum AnimationModeEnum: String, AppEnum {
    case karaoke, smooth, spring, glow

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Animation Mode")
    static var caseDisplayRepresentations: [AnimationModeEnum: DisplayRepresentation] = [
        .karaoke: "Karaoke",
        .smooth: "Smooth",
        .spring: "Spring",
        .glow: "Glow",
    ]

    var toAnimationMode: AnimationMode {
        AnimationMode(rawValue: rawValue) ?? .karaoke
    }
}

struct SetOverlayModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Overlay Mode"
    static var description = IntentDescription("Change the overlay size and/or animation mode.")

    @Parameter(title: "Size")
    var size: OverlaySizeEnum?

    @Parameter(title: "Animation")
    var animation: AnimationModeEnum?

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let controller = AppState.shared.overlayController else {
            throw IntentError.appNotReady
        }

        if let size {
            controller.overlaySize = size.toOverlaySize
        }
        if let animation {
            controller.animationMode = animation.toAnimationMode
        }

        return .result()
    }
}
