import AppIntents
import SpotifyLyricsCore

enum OverlayAction: String, AppEnum {
    case show, hide, toggle

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Overlay Action")
    static var caseDisplayRepresentations: [OverlayAction: DisplayRepresentation] = [
        .show: "Show",
        .hide: "Hide",
        .toggle: "Toggle",
    ]
}

struct ShowLyricsIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Lyrics"
    static var description = IntentDescription("Show, hide, or toggle the lyrics overlay.")

    @Parameter(title: "Action", default: .toggle)
    var action: OverlayAction

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let controller = AppState.shared.overlayController else {
            throw IntentError.appNotReady
        }

        switch action {
        case .show:
            if !controller.isVisible,
               let lm = AppState.shared.lyricsManager,
               let pm = AppState.shared.playerManager {
                controller.show(lyricsManager: lm, playerManager: pm)
            }
        case .hide:
            controller.hide()
        case .toggle:
            if controller.isVisible {
                controller.hide()
            } else if let lm = AppState.shared.lyricsManager,
                      let pm = AppState.shared.playerManager {
                controller.show(lyricsManager: lm, playerManager: pm)
            }
        }

        return .result()
    }
}
