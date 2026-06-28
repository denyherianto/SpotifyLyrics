import AppIntents
import SpotifyLyricsCore

/// AppEnum wrapper for TranslationLanguage so Shortcuts can display a picker.
enum TranslationLanguageEnum: String, AppEnum {
    case indonesian = "id"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case chinese = "zh-Hans"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case portuguese = "pt"
    case thai = "th"
    case vietnamese = "vi"
    case arabic = "ar"
    case russian = "ru"
    case hindi = "hi"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Translation Language")
    static var caseDisplayRepresentations: [TranslationLanguageEnum: DisplayRepresentation] = [
        .indonesian: "Indonesia",
        .english: "English",
        .japanese: "日本語",
        .korean: "한국어",
        .chinese: "中文",
        .spanish: "Español",
        .french: "Français",
        .german: "Deutsch",
        .portuguese: "Português",
        .thai: "ไทย",
        .vietnamese: "Tiếng Việt",
        .arabic: "العربية",
        .russian: "Русский",
        .hindi: "हिन्दी",
    ]

    var toTranslationLanguage: TranslationLanguage {
        TranslationLanguage(rawValue: rawValue) ?? .english
    }
}

struct ToggleTranslationIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Translation"
    static var description = IntentDescription("Enable or disable lyrics translation with optional language choice.")

    @Parameter(title: "Enabled")
    var enabled: Bool

    @Parameter(title: "Language")
    var language: TranslationLanguageEnum?

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let controller = AppState.shared.overlayController else {
            throw IntentError.appNotReady
        }

        controller.showTranslation = enabled
        if let language {
            controller.targetLanguage = language.toTranslationLanguage
        }

        return .result()
    }
}
