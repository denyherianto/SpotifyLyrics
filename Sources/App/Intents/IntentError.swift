import Foundation

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case appNotReady

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appNotReady:
            return "SpotifyLyrics is not ready. Please launch the app first."
        }
    }
}
