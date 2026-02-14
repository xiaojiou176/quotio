//
//  LanguageManager.swift
//  Quotio
//
//  Modern SwiftUI localization using String Catalogs (.xcstrings)
//

import SwiftUI

enum LanguageSelectionMode: String, Codable {
    case automatic
    case manual
}

// MARK: - Supported Languages

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case vietnamese = "vi"
    case chinese = "zh-Hans"
    case french = "fr"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .vietnamese: return "Tiếng Việt"
        case .chinese: return "简体中文"
        case .french: return "Français"
        }
    }

    var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .vietnamese: return "🇻🇳"
        case .chinese: return "🇨🇳"
        case .french: return "🇫🇷"
        }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    var bundle: Bundle {
        if let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        #if DEBUG
        Log.debug("LanguageManager: Bundle not found for \\(rawValue), falling back to main bundle")
        #endif
        return .main
    }

    nonisolated static func fromStoredPreference(_ value: String?) -> AppLanguage? {
        guard let value else { return nil }
        return fromLanguageIdentifier(value)
    }

    nonisolated static func fromLanguageIdentifier(_ identifier: String) -> AppLanguage? {
        let normalized = identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")

        guard !normalized.isEmpty else { return nil }

        if normalized.hasPrefix("zh-hans")
            || normalized.hasPrefix("zh-cn")
            || normalized.hasPrefix("zh-sg")
            || normalized.hasPrefix("zh-hant")
            || normalized.hasPrefix("zh-tw")
            || normalized.hasPrefix("zh-hk")
            || normalized.hasPrefix("zh-mo")
            || normalized == "zh"
            || normalized.hasPrefix("zh-") {
            return .chinese
        }
        if normalized.hasPrefix("vi") {
            return .vietnamese
        }
        if normalized.hasPrefix("fr") {
            return .french
        }
        if normalized.hasPrefix("en") {
            return .english
        }
        return nil
    }

    nonisolated static func preferredFromSystem() -> AppLanguage {
        for preferred in Locale.preferredLanguages {
            if let language = fromLanguageIdentifier(preferred) {
                return language
            }
        }
        return .english
    }
}

private struct LanguagePreferenceResolution {
    let mode: LanguageSelectionMode
    let language: AppLanguage
    let needsMigration: Bool
}

private enum LanguagePreferenceResolver {
    nonisolated static func resolve(userDefaults: UserDefaults = .standard) -> LanguagePreferenceResolution {
        let rawLanguage = userDefaults.string(forKey: "appLanguage")
        let normalizedLanguage = AppLanguage.fromStoredPreference(rawLanguage)

        let rawMode = userDefaults.string(forKey: "appLanguageMode")
        let storedMode = rawMode.flatMap(LanguageSelectionMode.init(rawValue:))

        let mode: LanguageSelectionMode
        switch storedMode {
        case .manual where normalizedLanguage != nil:
            mode = .manual
        case .manual:
            mode = .automatic
        case .automatic:
            mode = .automatic
        case nil:
            mode = normalizedLanguage == nil ? .automatic : .manual
        }

        let language: AppLanguage
        switch mode {
        case .manual:
            language = normalizedLanguage ?? .english
        case .automatic:
            language = AppLanguage.preferredFromSystem()
        }

        let languageNeedsNormalization = rawLanguage != nil && normalizedLanguage?.rawValue != rawLanguage
        let modeNeedsNormalization = rawMode != mode.rawValue
        let shouldClearStoredLanguage = mode == .automatic && rawLanguage != nil

        return LanguagePreferenceResolution(
            mode: mode,
            language: language,
            needsMigration: languageNeedsNormalization || modeNeedsNormalization || shouldClearStoredLanguage
        )
    }
}

// MARK: - Language Manager

@MainActor
@Observable
final class LanguageManager {

    static let shared = LanguageManager()

    private(set) var currentLanguage: AppLanguage
    private(set) var selectionMode: LanguageSelectionMode

    private let userDefaults: UserDefaults
    private var systemLocaleObserver: NSObjectProtocol?

    var locale: Locale { currentLanguage.locale }
    var bundle: Bundle { currentLanguage.bundle }
    var isUsingSystemLanguage: Bool { selectionMode == .automatic }

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let resolution = LanguagePreferenceResolver.resolve(userDefaults: userDefaults)
        self.currentLanguage = resolution.language
        self.selectionMode = resolution.mode

        if resolution.needsMigration {
            persistCurrentSelection()
        }

        observeSystemLocaleChanges()
    }

    func setLanguage(_ language: AppLanguage) {
        selectionMode = .manual
        currentLanguage = language
        persistCurrentSelection()
    }

    func useSystemLanguage() {
        selectionMode = .automatic
        currentLanguage = AppLanguage.preferredFromSystem()
        persistCurrentSelection()
    }

    func localized(_ key: String) -> String {
        NSLocalizedString(key, bundle: currentLanguage.bundle, comment: "")
    }

    private func persistCurrentSelection() {
        userDefaults.set(selectionMode.rawValue, forKey: "appLanguageMode")

        switch selectionMode {
        case .manual:
            userDefaults.set(currentLanguage.rawValue, forKey: "appLanguage")
        case .automatic:
            userDefaults.removeObject(forKey: "appLanguage")
        }
    }

    private func observeSystemLocaleChanges() {
        systemLocaleObserver = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncWithSystemLanguageIfNeeded()
            }
        }
    }

    private func syncWithSystemLanguageIfNeeded() {
        guard selectionMode == .automatic else { return }

        let preferred = AppLanguage.preferredFromSystem()
        guard preferred != currentLanguage else { return }

        currentLanguage = preferred
        persistCurrentSelection()
    }

}

// MARK: - String Extension

extension String {
    @MainActor
    func localized() -> String {
        LanguageManager.shared.localized(self)
    }
    
    /// Localization with fallback for keys that may not exist yet.
    /// Returns the fallback if the localized string equals the key (i.e., not found).
    @MainActor
    func localized(fallback: String) -> String {
        let result = LanguageManager.shared.localized(self)
        // If the result equals the key, the localization wasn't found
        return result == self ? fallback : result
    }
    
    /// Nonisolated localization for use in computed properties on enums/structs.
    /// Reads stored preference directly without MainActor isolation.
    nonisolated func localizedStatic() -> String {
        let resolution = LanguagePreferenceResolver.resolve()
        let resolvedLanguage = resolution.language

        if let path = Bundle.main.path(forResource: resolvedLanguage.rawValue, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return NSLocalizedString(self, bundle: bundle, comment: "")
        }
        return NSLocalizedString(self, bundle: .main, comment: "")
    }
}
