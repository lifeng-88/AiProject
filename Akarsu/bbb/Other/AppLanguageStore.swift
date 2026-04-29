//
//  AppLanguageStore.swift
//  bbb
//
//  应用内语言偏好 + SwiftUI Locale；与模板接口 `locale` 参数对齐。
//

import Combine
import Foundation
import SwiftUI
import UIKit

/// 用户可选的应用界面语言（跟随系统 / 多语言）
enum AppLanguagePreference: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    /// 繁體中文（String Catalog `zh-Hant`）
    case traditionalChinese = "zh-Hant"
    case portuguese = "pt"
    case spanish = "es"
    case japanese = "ja"
    case french = "fr"
    case german = "de"

    var id: String { rawValue }

    var storageValue: String {
        switch self {
        case .system: return "system"
        default: return rawValue
        }
    }

    static func from(storage: String) -> AppLanguagePreference {
        switch storage {
        case "system": return .system
        case AppLanguagePreference.english.rawValue: return .english
        case AppLanguagePreference.traditionalChinese.rawValue: return .traditionalChinese
        /// 舊版偏好（簡體代碼）遷移到繁體
        case "zh-Hans": return .traditionalChinese
        case AppLanguagePreference.portuguese.rawValue: return .portuguese
        case AppLanguagePreference.spanish.rawValue: return .spanish
        case AppLanguagePreference.japanese.rawValue: return .japanese
        case AppLanguagePreference.french.rawValue: return .french
        case AppLanguagePreference.german.rawValue: return .german
        default: return .system
        }
    }
}

@MainActor
final class AppLanguageStore: ObservableObject {
    private static let userDefaultsKey = "bbb.appLanguagePreference"

    /// 与 `Localizable.xcstrings` 中 `zh-Hant` 变体对齐
    nonisolated static var traditionalChineseLocale: Locale {
        Locale(identifier: "zh-Hant")
    }

    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var preference: AppLanguagePreference {
        didSet {
            UserDefaults.standard.set(preference.storageValue, forKey: Self.userDefaultsKey)
        }
    }

    init() {
        if UserDefaults.standard.string(forKey: Self.userDefaultsKey) == "zh-Hans" {
            UserDefaults.standard.set(AppLanguagePreference.traditionalChinese.rawValue, forKey: Self.userDefaultsKey)
        }
        let raw = UserDefaults.standard.string(forKey: Self.userDefaultsKey) ?? "system"
        preference = AppLanguagePreference.from(storage: raw)

        /// 在「跟随系统」下，用户从系统设置切换语言回到本应用时刷新界面
        NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        /// 从后台回到前台时再刷一次（部分系统版本上 `NSLocale` 通知不可靠）
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    /// 供根视图在 `scenePhase == .active` 时调用，与前台通知互补
    func refreshUITextForPossibleSystemLocaleChange() {
        objectWillChange.send()
    }

    /// 使用与 `preference` 一致的 Locale 解析 String Catalog。
    /// - iOS 16+：`LocalizedStringResource` 显式 `locale`（可靠）。
    /// - iOS 15：`String(localized:bundle:locale:)` 对 Catalog 编译产物常**不**按传入 `locale` 选语言；改为从对应 `*.lproj` 的 `Bundle` 取 `Localizable`（Xcode 会将 `xcstrings` 展开为各语言 bundle）。
    nonisolated static func localized(_ key: String) -> String {
        let value = String.LocalizationValue(key)
        let locale = localeForStoredPreference()
        if #available(iOS 16.0, *) {
            let resource = LocalizedStringResource(value, locale: locale)
            return String(localized: resource)
        } else {
            return localizedStringIOS15Catalog(key: key)
        }
    }

    /// iOS 15：按当前偏好选择 `语言.lproj`，再查 `Localizable` 表。
    nonisolated private static func localizedStringIOS15Catalog(key: String) -> String {
        let bundle = bundleForIOS15LocalizedTable()
        var s = bundle.localizedString(forKey: key, value: nil, table: nil)
        if s == key, bundle !== Bundle.main,
           let enPath = Bundle.main.path(forResource: "en", ofType: "lproj"),
           let enBundle = Bundle(path: enPath) {
            s = enBundle.localizedString(forKey: key, value: nil, table: nil)
        }
        return s
    }

    /// 与 `localeForStoredPreference` / 接口 `locale` 逻辑一致，映射到 Xcode 生成的 `.lproj` 目录名（与 `Localizable.xcstrings` 中语言代码一致，如 `en`、`zh-Hant`）。
    nonisolated private static func bundleForIOS15LocalizedTable() -> Bundle {
        let raw = UserDefaults.standard.string(forKey: userDefaultsKey) ?? "system"
        let langCode: String
        switch AppLanguagePreference.from(storage: raw) {
        case .english:
            langCode = "en"
        case .traditionalChinese:
            langCode = "zh-Hant"
        case .portuguese:
            langCode = "pt"
        case .spanish:
            langCode = "es"
        case .japanese:
            langCode = "ja"
        case .french:
            langCode = "fr"
        case .german:
            langCode = "de"
        case .system:
            let preferred = Locale.preferredLanguages.first ?? ""
            if preferred.hasPrefix("zh") { langCode = "zh-Hant" }
            else if preferred.hasPrefix("pt") { langCode = "pt" }
            else if preferred.hasPrefix("es") { langCode = "es" }
            else if preferred.hasPrefix("ja") { langCode = "ja" }
            else if preferred.hasPrefix("fr") { langCode = "fr" }
            else if preferred.hasPrefix("de") { langCode = "de" }
            else { langCode = "en" }
        }
        if let path = Bundle.main.path(forResource: langCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }

    nonisolated private static func localeForStoredPreference() -> Locale {
        let raw = UserDefaults.standard.string(forKey: userDefaultsKey) ?? "system"
        switch AppLanguagePreference.from(storage: raw) {
        case .system:
            return Locale.autoupdatingCurrent
        case .english:
            return Locale(identifier: "en")
        case .traditionalChinese:
            return Self.traditionalChineseLocale
        case .portuguese:
            return Locale(identifier: "pt")
        case .spanish:
            return Locale(identifier: "es")
        case .japanese:
            return Locale(identifier: "ja")
        case .french:
            return Locale(identifier: "fr")
        case .german:
            return Locale(identifier: "de")
        }
    }

    func setPreference(_ value: AppLanguagePreference) {
        guard preference != value else { return }
        preference = value
    }

    /// 供 `Text` / `String(localized:)` 使用的 SwiftUI 区域设置
    var effectiveLocale: Locale {
        switch preference {
        case .system:
            return Locale.autoupdatingCurrent
        case .english:
            return Locale(identifier: "en")
        case .traditionalChinese:
            return Self.traditionalChineseLocale
        case .portuguese:
            return Locale(identifier: "pt")
        case .spanish:
            return Locale(identifier: "es")
        case .japanese:
            return Locale(identifier: "ja")
        case .french:
            return Locale(identifier: "fr")
        case .german:
            return Locale(identifier: "de")
        }
    }

    /// 与 `/v1/catalogs`、模板列表等接口的 `locale` 参数一致（短标识）
    var templateAPICatalogLocaleIdentifier: String {
        switch preference {
        case .english:
            return "en"
        case .traditionalChinese:
            return "zh-Hant"
        case .portuguese:
            return "pt"
        case .spanish:
            return "es"
        case .japanese:
            return "ja"
        case .french:
            return "fr"
        case .german:
            return "de"
        case .system:
            let id = Locale.autoupdatingCurrent.identifier
            if id.hasPrefix("zh") { return "zh-Hant" }
            if id.hasPrefix("pt") { return "pt" }
            if id.hasPrefix("es") { return "es" }
            if id.hasPrefix("ja") { return "ja" }
            if id.hasPrefix("fr") { return "fr" }
            if id.hasPrefix("de") { return "de" }
            return "en"
        }
    }

    /// 设置页「语言」一行右侧摘要（跟随系统时附带当前系统界面语言说明）
    var currentLanguageDisplayName: String {
        switch preference {
        case .system:
            let base = Self.localized("language.option.system")
            let sys = Self.systemPrimaryLanguageDisplayName()
            if sys.isEmpty { return base }
            return "\(base) · \(sys)"
        case .english:
            return Self.localized("language.option.english")
        case .traditionalChinese:
            return Self.localized("language.option.chinese")
        case .portuguese:
            return Self.localized("language.option.portuguese")
        case .spanish:
            return Self.localized("language.option.spanish")
        case .japanese:
            return Self.localized("language.option.japanese")
        case .french:
            return Self.localized("language.option.french")
        case .german:
            return Self.localized("language.option.german")
        }
    }

    /// 设备首选语言在系统中的本地化名称，用于「跟随系统」旁注
    nonisolated private static func systemPrimaryLanguageDisplayName() -> String {
        guard let first = Locale.preferredLanguages.first else { return "" }
        let code = String(first.prefix(while: { $0 != "-" }))
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }
}

// MARK: - SwiftUI：随语言偏好刷新（静态 `localized` 不会自动订阅 ObservableObject）

struct BBBAppLanguageRefreshModifier: ViewModifier {
    @EnvironmentObject private var appLanguage: AppLanguageStore

    func body(content: Content) -> some View {
        let _ = appLanguage.preference
        content
    }
}

extension View {
    /// 挂接在依赖 `AppLanguageStore.localized` 的根容器上，使 `preference` 变化时重算 `body`。
    func bbbRefreshOnAppLanguage() -> some View {
        modifier(BBBAppLanguageRefreshModifier())
    }
}
