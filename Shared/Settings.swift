import Foundation

struct KeyboardRecord: Codable {
    let text: String
    let tone: Tone
    let date: Date
}

/// Language the text is rewritten into (default English).
enum TargetLanguage: String, CaseIterable, Identifiable {
    case english, korean, japanese, chinese, spanish
    var id: String { rawValue }
    /// Name sent to the server prompt.
    var promptName: String {
        switch self {
        case .english: return "English"
        case .korean: return "Korean"
        case .japanese: return "Japanese"
        case .chinese: return "Chinese"
        case .spanish: return "Spanish"
        }
    }
    var nativeName: String {
        switch self {
        case .english: return "English"
        case .korean: return "한국어"
        case .japanese: return "日本語"
        case .chinese: return "中文"
        case .spanish: return "Español"
        }
    }
    /// Name used inside the keyboard hint, in the app language.
    var hintName: String {
        switch self {
        case .english: return L("영어", "English")
        case .korean: return L("한국어", "Korean")
        case .japanese: return L("일본어", "Japanese")
        case .chinese: return L("중국어", "Chinese")
        case .spanish: return L("스페인어", "Spanish")
        }
    }
}

/// Japanese keyboard layout.
enum JapaneseLayout: String, CaseIterable, Identifiable {
    case kana, romaji
    var id: String { rawValue }
    var label: String { self == .kana ? L("가나 (플릭)", "Kana (flick)") : L("로마자", "Romaji") }
}

/// Extra input languages the keyboard can type in (English is always available).
enum InputLanguage: String, CaseIterable, Identifiable {
    case korean, japanese, chinese
    var id: String { rawValue }
    var nativeName: String {
        switch self {
        case .korean: return "한국어"
        case .japanese: return "日本語"
        case .chinese: return "中文"
        }
    }
    /// Short label of the key that switches to this language.
    var keyLabel: String {
        switch self {
        case .korean: return "한"
        case .japanese: return "日"
        case .chinese: return "中"
        }
    }
}

/// Keyboard height preset (points, excluding the Korean compose bar).
enum KeyboardHeight: String, CaseIterable, Identifiable {
    case compact, normal, tall
    var id: String { rawValue }
    var label: String {
        switch self {
        case .compact: return L("작게", "Small")
        case .normal: return L("보통", "Medium")
        case .tall: return L("크게", "Large")
        }
    }
    var points: CGFloat {
        switch self {
        case .compact: return 246
        case .normal: return 276
        case .tall: return 310
        }
    }
}

/// Language of the app and keyboard UI (separate from the language used to explain changes).
enum AppLanguage: String, CaseIterable, Identifiable {
    case ko, en
    var id: String { rawValue }
    var nativeName: String { self == .ko ? "한국어" : "English" }
}

/// Picks the Korean or English text for the current UI language.
func L(_ ko: String, _ en: String) -> String {
    AppSettings.uiLanguage == .ko ? ko : en
}

extension Notification.Name {
    static let uiLanguageChanged = Notification.Name("uiLanguageChanged")
}

enum AppConfig {
    static let appGroup = "group.com.addvalue.nativetone"
    /// Local dev proxy (see server/). Replace with the deployed proxy URL for release builds.
    static let defaultBaseURL = "https://nativetone.outinletter.workers.dev"
    static let maxInputLength = 600
}

/// Settings shared between the app and the keyboard extension through the App Group.
/// Falls back to standard defaults when the group is unavailable (e.g. unsigned simulator builds).
enum AppSettings {
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppConfig.appGroup) ?? .standard
    }

    private enum Key {
        static let tone = "tone"
        static let explainLanguage = "explainLanguage"
        static let baseURL = "baseURL"
        static let appToken = "appToken"
        static let autoSuggest = "autoSuggest"
        static let hasSeenGuide = "hasSeenGuide"
        static let uiLanguage = "uiLanguage"
        static let saveHistory = "saveHistory"
        static let japaneseLayout = "japaneseLayout"
        static let targetLanguage = "targetLanguage"
        static let composeEnglish = "composeEnglish"
        static let aiEnabled = "aiEnabled"
        static let lastLanguage = "lastLanguage"
        static let keyboardQueue = "keyboardQueue"
        static let inputLanguages = "inputLanguages"
        static let keyboardHeight = "keyboardHeight"
        static let haptics = "haptics"
        static let autoCapitalize = "autoCapitalize"
    }

    /// Master switch for AI rewriting in the keyboard. Off = a plain keyboard that sends nothing (default on).
    static var aiEnabled: Bool {
        get { defaults.object(forKey: Key.aiEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.aiEnabled) }
    }

    /// The keyboard layout used last ("english", "korean", "japanese", "chinese"), restored the next time it opens.
    static var lastLanguage: String {
        get { defaults.string(forKey: Key.lastLanguage) ?? "english" }
        set { defaults.set(newValue, forKey: Key.lastLanguage) }
    }

    /// English typing also goes through the top bar and is converted live (default on).
    static var composeEnglish: Bool {
        get { defaults.object(forKey: Key.composeEnglish) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.composeEnglish) }
    }

    static var targetLanguage: TargetLanguage {
        get { TargetLanguage(rawValue: defaults.string(forKey: Key.targetLanguage) ?? "") ?? .english }
        set { defaults.set(newValue.rawValue, forKey: Key.targetLanguage) }
    }

    static var japaneseLayout: JapaneseLayout {
        get { JapaneseLayout(rawValue: defaults.string(forKey: Key.japaneseLayout) ?? "") ?? .kana }
        set { defaults.set(newValue.rawValue, forKey: Key.japaneseLayout) }
    }

    /// Save converted sentences to the on-device history (default on). Original input is never saved.
    static var saveHistory: Bool {
        get { defaults.object(forKey: Key.saveHistory) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.saveHistory) }
    }

    /// Keyboard -> app hand-off: converted sentences applied in the keyboard, imported into history by the app.
    static func queueKeyboardResult(_ text: String, tone: Tone) {
        guard saveHistory else { return }
        var list = (try? JSONDecoder().decode([KeyboardRecord].self, from: defaults.data(forKey: Key.keyboardQueue) ?? Data())) ?? []
        list.append(KeyboardRecord(text: text, tone: tone, date: Date()))
        if list.count > 50 { list.removeFirst(list.count - 50) }
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: Key.keyboardQueue) }
    }

    static func takeKeyboardResults() -> [KeyboardRecord] {
        guard let data = defaults.data(forKey: Key.keyboardQueue),
              let list = try? JSONDecoder().decode([KeyboardRecord].self, from: data) else { return [] }
        defaults.removeObject(forKey: Key.keyboardQueue)
        return list
    }

    /// Defaults to Korean on Korean devices, English elsewhere.
    static var uiLanguage: AppLanguage {
        get {
            if let raw = defaults.string(forKey: Key.uiLanguage), let v = AppLanguage(rawValue: raw) { return v }
            return Locale.preferredLanguages.first?.hasPrefix("ko") == true ? .ko : .en
        }
        set { defaults.set(newValue.rawValue, forKey: Key.uiLanguage) }
    }

    /// Enabled extra input languages (all on by default).
    static var inputLanguages: Set<InputLanguage> {
        get {
            guard let raw = defaults.array(forKey: Key.inputLanguages) as? [String] else { return Set(InputLanguage.allCases) }
            return Set(raw.compactMap(InputLanguage.init(rawValue:)))
        }
        set { defaults.set(newValue.map(\.rawValue), forKey: Key.inputLanguages) }
    }

    static var keyboardHeight: KeyboardHeight {
        get { KeyboardHeight(rawValue: defaults.string(forKey: Key.keyboardHeight) ?? "") ?? .normal }
        set { defaults.set(newValue.rawValue, forKey: Key.keyboardHeight) }
    }

    /// Keyboard: light tap feedback on each key (default on).
    static var haptics: Bool {
        get { defaults.object(forKey: Key.haptics) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.haptics) }
    }

    /// Keyboard: shift automatically at the start of a sentence (default on).
    static var autoCapitalize: Bool {
        get { defaults.object(forKey: Key.autoCapitalize) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.autoCapitalize) }
    }

    static var tone: Tone {
        get { Tone(rawValue: defaults.string(forKey: Key.tone) ?? "") ?? .casual }
        set { defaults.set(newValue.rawValue, forKey: Key.tone) }
    }

    /// Explanations follow the app language (no separate setting).
    static var explainLanguage: ExplainLanguage { uiLanguage == .ko ? .ko : .en }

    /// Fixed server address (no user setting); old saved values are ignored.
    static var baseURL: String { AppConfig.defaultBaseURL }

    static var appToken: String { "" }

    /// Keyboard: suggest a natural rewrite automatically whenever typing pauses (default on).
    static var autoSuggest: Bool {
        get { defaults.object(forKey: Key.autoSuggest) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.autoSuggest) }
    }

    static var hasSeenGuide: Bool {
        get { defaults.bool(forKey: Key.hasSeenGuide) }
        set { defaults.set(newValue, forKey: Key.hasSeenGuide) }
    }
}
