import Foundation

// Язык интерфейса: "system" (по языку macOS), "ru" или "en".
enum Language: String, CaseIterable {
    case system, ru, en

    static let key = "language"

    static var current: Language {
        Language(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system
    }

    static var isRussian: Bool {
        switch current {
        case .ru: return true
        case .en: return false
        case .system: return Locale.preferredLanguages.first?.hasPrefix("ru") ?? false
        }
    }
}

extension Notification.Name {
    static let languageChanged = Notification.Name("ShotCapLanguageChanged")
}

// Строка интерфейса на текущем языке.
func L(_ ru: String, _ en: String) -> String {
    Language.isRussian ? ru : en
}
