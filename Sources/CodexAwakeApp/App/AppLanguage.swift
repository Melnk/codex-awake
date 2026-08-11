import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english
    case russian

    var id: String { rawValue }

    var code: String {
        switch self {
        case .english: "EN"
        case .russian: "RU"
        }
    }

    var title: String {
        switch self {
        case .english: "English"
        case .russian: "Русский"
        }
    }

    var locale: Locale {
        Locale(identifier: self == .russian ? "ru_RU" : "en_US")
    }

    func text(_ english: String, _ russian: String) -> String {
        self == .russian ? russian : english
    }

    static var systemDefault: AppLanguage {
        Locale.preferredLanguages.first?.hasPrefix("ru") == true ? .russian : .english
    }
}
