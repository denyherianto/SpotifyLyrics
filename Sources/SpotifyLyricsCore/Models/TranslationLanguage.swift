import Foundation

public enum TranslationLanguage: String, CaseIterable, Equatable {
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

    public var displayName: String {
        switch self {
        case .indonesian: return "Indonesia"
        case .english: return "English"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .chinese: return "中文"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .portuguese: return "Português"
        case .thai: return "ไทย"
        case .vietnamese: return "Tiếng Việt"
        case .arabic: return "العربية"
        case .russian: return "Русский"
        case .hindi: return "हिन्दी"
        }
    }
}
