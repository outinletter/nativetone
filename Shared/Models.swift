import Foundation

/// Style presets cycled in the keyboard and chosen in the app.
enum Tone: String, CaseIterable, Codable, Identifiable {
    case casual, academic, slang

    var id: String { rawValue }

    /// Older builds stored sweet / polite / short; map them onto the new styles instead of failing to decode.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "academic", "polite": self = .academic
        case "slang": self = .slang
        default: self = .casual
        }
    }

    var label: String {
        switch self {
        case .casual: return L("캐주얼", "Casual")
        case .academic: return L("학술", "Academic")
        case .slang: return L("슬랭", "Slang")
        }
    }

    /// Adjective used in the keyboard hint, e.g. "casual native English version".
    var adjective: String {
        switch self {
        case .casual: return L("캐주얼한", "casual")
        case .academic: return L("전문적이고 학술적인", "professional, academic")
        case .slang: return L("슬랭이 섞인", "slangy")
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
