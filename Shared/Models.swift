import Foundation

/// Tone presets shown as chips in the app and cycled in the keyboard.
enum Tone: String, CaseIterable, Codable, Identifiable {
    case casual, sweet, polite, short

    var id: String { rawValue }

    var label: String {
        switch self {
        case .casual: return L("캐주얼", "Casual")
        case .sweet: return L("다정함", "Sweet")
        case .polite: return L("정중함", "Polite")
        case .short: return L("짧게", "Short")
        }
    }

    /// Adjective used in the keyboard hint, e.g. "casual native-speaker version".
    var adjective: String {
        switch self {
        case .casual: return L("캐주얼한", "casual")
        case .sweet: return L("다정한", "warm")
        case .polite: return L("정중한", "polite")
        case .short: return L("짧고 간결한", "concise")
        }
    }

    var emoji: String {
        switch self {
        case .casual: return "🙂"
        case .sweet: return "💗"
        case .polite: return "🤝"
        case .short: return "⚡️"
        }
    }

    var next: Tone {
        let all = Tone.allCases
        let i = all.firstIndex(of: self) ?? 0
        return all[(i + 1) % all.count]
    }
}

/// Language used to explain *why* something was changed.
enum ExplainLanguage: String, CaseIterable, Codable, Identifiable {
    case ko, ja, zh, es, vi, en

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .ko: return "한국어"
        case .ja: return "日本語"
        case .zh: return "中文"
        case .es: return "Español"
        case .vi: return "Tiếng Việt"
        case .en: return "English"
        }
    }

    /// Name sent to the server prompt.
    var promptName: String {
        switch self {
        case .ko: return "Korean"
        case .ja: return "Japanese"
        case .zh: return "Chinese"
        case .es: return "Spanish"
        case .vi: return "Vietnamese"
        case .en: return "English"
        }
    }
}

struct RewriteChange: Codable, Hashable, Identifiable {
    let from: String
    let to: String
    let why: String

    var id: String { "\(from)→\(to)" }
}

struct RewriteResult: Codable, Hashable {
    let best: String
    let alternatives: [String]
    let changes: [RewriteChange]

    init(best: String, alternatives: [String] = [], changes: [RewriteChange] = []) {
        self.best = best
        self.alternatives = alternatives
        self.changes = changes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        best = try c.decode(String.self, forKey: .best)
        alternatives = try c.decodeIfPresent([String].self, forKey: .alternatives) ?? []
        changes = try c.decodeIfPresent([RewriteChange].self, forKey: .changes) ?? []
    }

    private enum CodingKeys: String, CodingKey { case best, alternatives, changes }
}
