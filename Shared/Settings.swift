import Foundation

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
    }

    static var tone: Tone {
        get { Tone(rawValue: defaults.string(forKey: Key.tone) ?? "") ?? .casual }
        set { defaults.set(newValue.rawValue, forKey: Key.tone) }
    }

    static var explainLanguage: ExplainLanguage {
        get { ExplainLanguage(rawValue: defaults.string(forKey: Key.explainLanguage) ?? "") ?? .ko }
        set { defaults.set(newValue.rawValue, forKey: Key.explainLanguage) }
    }

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
