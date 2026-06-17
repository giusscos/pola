import Foundation
import ObjectiveC
import SwiftUI

@Observable
final class LanguageManager {
    static let shared = LanguageManager()

    var languageRefreshID: UUID = UUID()

    var selectedCode: String = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"

    let supportedLanguages: [(code: String, localName: String)] = [
        ("system", "System Default"),
        ("en", "English"),
        ("it", "Italiano"),
        ("es", "Español"),
        ("fr", "Français"),
        ("de", "Deutsch"),
    ]

    private init() {
        let stored = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        let code = resolved(stored)
        Bundle.setLanguage(code)
    }

    func setLanguage(_ code: String) {
        selectedCode = code
        UserDefaults.standard.set(code, forKey: "appLanguage")
        let lang = resolved(code)
        // Write AppleLanguages so iOS native localization picks up the right .lproj on restart
        if code == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([lang], forKey: "AppleLanguages")
        }
        Bundle.setLanguage(lang)
        languageRefreshID = UUID()
    }

    private func resolved(_ code: String) -> String {
        code == "system" ? (Locale.current.language.languageCode?.identifier ?? "en") : code
    }
}

// MARK: - Bundle swizzling

private var bundleLanguageKey: UInt8 = 0

extension Bundle {
    static func setLanguage(_ language: String) {
        defer { object_setClass(Bundle.main, LanguageBundle.self) }
        objc_setAssociatedObject(
            Bundle.main,
            &bundleLanguageKey,
            language,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }
}

private final class LanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        guard
            let language = objc_getAssociatedObject(Bundle.main, &bundleLanguageKey) as? String,
            let path = Bundle.main.path(forResource: language, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
        return bundle.localizedString(forKey: key, value: value, table: tableName)
    }
}
